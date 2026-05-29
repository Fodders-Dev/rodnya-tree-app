// Profile Phase 2b-2 (2026-05-29): voice input sheet — speak → Russian
// on-device STT → editable text (the Phase D accelerator). STT quality
// validated on-device (S20 FE: ru_RU, ~0.89 confidence, numerals →
// digits).
//
// Transcript-only: speech_to_text captures the live mic and returns the
// recognized words; we do NOT save the audio (Android won't reliably let
// the recorder hold the mic at the same time — «бабушкин голос» artifact
// is a separate future feature). Returns the transcript, or null if the
// user cancels / permission is denied (caller falls back to typing).

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Shows the voice-input sheet. Returns the recognized text, or null if
/// cancelled / unavailable / permission denied.
Future<String?> showVoiceInputSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _VoiceInputSheet(),
  );
}

class _VoiceInputSheet extends StatefulWidget {
  const _VoiceInputSheet();

  @override
  State<_VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends State<_VoiceInputSheet> {
  final SpeechToText _speech = SpeechToText();
  bool _initDone = false;
  bool _available = false;
  bool _listening = false;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    bool ok = false;
    try {
      ok = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted) setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _initDone = true;
      _available = ok;
    });
    if (ok) _startListening();
  }

  Future<void> _startListening() async {
    if (!_available) return;
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        if (!mounted) return;
        setState(() {
          _text = r.recognizedWords;
          if (r.finalResult) _listening = false;
        });
      },
      listenOptions: SpeechListenOptions(
        localeId: 'ru_RU',
        partialResults: true,
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _stopAndAccept() async {
    await _speech.stop();
    if (!mounted) return;
    Navigator.of(context).pop(_text.trim().isEmpty ? null : _text.trim());
  }

  Future<void> _cancel() async {
    await _speech.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: !_initDone
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : !_available
                ? _buildDenied(theme)
                : _buildListening(theme),
      ),
    );
  }

  Widget _buildDenied(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Микрофон недоступен',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Разрешите доступ к микрофону в настройках телефона — или '
          'закройте это окно и наберите текст руками.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('voice-denied-close'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ),
      ],
    );
  }

  Widget _buildListening(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
              color: _listening
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              _listening ? 'Говорите…' : 'Готово к записи',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60, maxHeight: 220),
          child: SingleChildScrollView(
            child: Text(
              _text.isEmpty ? 'Скажите, что записать в биографию…' : _text,
              key: const Key('voice-transcript'),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFamily: 'Lora',
                fontSize: 18,
                height: 1.5,
                color: _text.isEmpty
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // OverflowBar (не Row+Spacer): action-ряд, устойчивый к нехватке
        // ширины. При узком экране / крупном системном шрифте сам
        // разворачивается в вертикальную колонку вместо overflow.
        // (S20 FE ловил "RIGHT OVERFLOWED BY 15 PIXELS" на Row+Spacer.)
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          overflowAlignment: OverflowBarAlignment.end,
          overflowSpacing: 4,
          children: [
            if (!_listening)
              TextButton.icon(
                key: const Key('voice-restart'),
                onPressed: _startListening,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Записать ещё'),
              ),
            TextButton(
              key: const Key('voice-cancel'),
              onPressed: _cancel,
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('voice-done'),
              onPressed: _text.trim().isEmpty ? null : _stopAndAccept,
              child: const Text('Вставить'),
            ),
          ],
        ),
      ],
    );
  }
}
