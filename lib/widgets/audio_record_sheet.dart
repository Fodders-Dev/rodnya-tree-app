// Profile Phase 2b-2 audio (2026-05-29): voice-recording sheet — record
// the person's living voice and SAVE it as a playable artifact in the
// article. This is NOT the STT accelerator (that's voice_input_sheet.dart
// → text); here the sound is kept (transcript = null, no mic/STT
// conflict).
//
// Reuses ChatRecordingController (the chat voice-note recorder on the
// `record` package — same m4a/AAC encoder, RECORD_AUDIO permission flow,
// duration tracking). Returns the recorded file + duration; the editor
// uploads it and creates the audio block. Releases the mic on Готово /
// Отмена / dispose. 15-minute cap (Profile Q7) auto-stops.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../controllers/chat_recording_controller.dart';

class AudioRecordResult {
  const AudioRecordResult({
    required this.file,
    required this.mimeType,
    required this.durationSec,
  });

  final XFile file;
  final String mimeType;
  final int durationSec;
}

const int _maxRecordSeconds = 15 * 60; // Profile Q7

/// Shows the voice-recording sheet. Returns the recorded artifact, or
/// null if cancelled / permission denied.
Future<AudioRecordResult?> showAudioRecordSheet(BuildContext context) {
  return showModalBottomSheet<AudioRecordResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _AudioRecordSheet(),
  );
}

class _AudioRecordSheet extends StatefulWidget {
  const _AudioRecordSheet();

  @override
  State<_AudioRecordSheet> createState() => _AudioRecordSheetState();
}

class _AudioRecordSheetState extends State<_AudioRecordSheet> {
  final ChatRecordingController _rec = ChatRecordingController();
  bool _capping = false;

  @override
  void initState() {
    super.initState();
    _rec.addListener(_onTick);
  }

  void _onTick() {
    if (_rec.state == ChatRecordingState.recording &&
        _rec.durationSeconds >= _maxRecordSeconds &&
        !_capping) {
      _capping = true;
      _rec.stopToPreview();
    }
  }

  @override
  void dispose() {
    _rec.removeListener(_onTick);
    // Release the mic / drop any in-flight recording.
    _rec.cancelCurrent();
    _rec.dispose();
    super.dispose();
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _accept() {
    final file = _rec.previewFile;
    if (file == null) return;
    Navigator.of(context).pop(AudioRecordResult(
      file: file,
      mimeType: _rec.preview?.mimeType ?? 'audio/m4a',
      durationSec: _rec.previewDurationSeconds,
    ));
  }

  Future<void> _cancel() async {
    await _rec.cancelCurrent();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: AnimatedBuilder(
          animation: _rec,
          builder: (context, _) {
            final state = _rec.state;
            final Widget body;
            switch (state) {
              case ChatRecordingState.denied:
                body = _buildDenied(theme);
                break;
              case ChatRecordingState.recording:
              case ChatRecordingState.locked:
                body = _buildRecording(theme);
                break;
              case ChatRecordingState.preview:
                body = _buildPreview(theme);
                break;
              case ChatRecordingState.requestingPermission:
                body = const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
                break;
              default:
                body = _buildIdle(theme);
            }
            return body;
          },
        ),
      ),
    );
  }

  Widget _title(ThemeData theme, String text) => Text(
        text,
        style:
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      );

  Widget _buildIdle(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(theme, 'Записать голос'),
        const SizedBox(height: 6),
        Text(
          'Живой голос человека сохранится в биографии — его можно будет '
          'послушать.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const Key('audio-record-start'),
          onPressed: () => _rec.start(),
          icon: const Icon(Icons.mic_rounded),
          label: const Text('Начать запись'),
        ),
      ],
    );
  }

  Widget _buildRecording(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.fiber_manual_record_rounded,
                color: theme.colorScheme.error, size: 18),
            const SizedBox(width: 8),
            _title(theme, 'Идёт запись · ${_fmt(_rec.durationSeconds)}'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'до 15 минут',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const Key('audio-record-stop'),
          onPressed: () => _rec.stopToPreview(),
          icon: const Icon(Icons.stop_rounded),
          label: const Text('Стоп'),
        ),
      ],
    );
  }

  Widget _buildPreview(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(theme, 'Запись готова · ${_fmt(_rec.previewDurationSeconds)}'),
        const SizedBox(height: 16),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          overflowAlignment: OverflowBarAlignment.end,
          overflowSpacing: 4,
          children: [
            TextButton.icon(
              key: const Key('audio-record-redo'),
              onPressed: () {
                _capping = false;
                _rec.discardPreview();
                _rec.start();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Заново'),
            ),
            TextButton(
              key: const Key('audio-record-cancel'),
              onPressed: _cancel,
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('audio-record-done'),
              onPressed: _accept,
              child: const Text('Вставить'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDenied(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(theme, 'Микрофон недоступен'),
        const SizedBox(height: 8),
        Text(
          _rec.errorText ??
              'Разрешите доступ к микрофону в настройках телефона, чтобы '
                  'записать голос.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('audio-record-close'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ),
      ],
    );
  }
}
