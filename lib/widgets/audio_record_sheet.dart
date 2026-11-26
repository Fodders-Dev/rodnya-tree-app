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

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
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
/// [confirmLabel] — подпись кнопки подтверждения: в редакторе статьи запись
/// «вставляется» в текст, в ответе на вопрос — «сохраняется» как история.
Future<AudioRecordResult?> showAudioRecordSheet(
  BuildContext context, {
  String confirmLabel = 'Вставить',
  bool autoStart = false,
}) {
  return showModalBottomSheet<AudioRecordResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AudioRecordSheet(
      confirmLabel: confirmLabel,
      autoStart: autoStart,
    ),
  );
}

class _AudioRecordSheet extends StatefulWidget {
  const _AudioRecordSheet({
    this.confirmLabel = 'Вставить',
    this.autoStart = false,
  });

  final String confirmLabel;
  final bool autoStart;

  @override
  State<_AudioRecordSheet> createState() => _AudioRecordSheetState();
}

class _AudioRecordSheetState extends State<_AudioRecordSheet> {
  final ChatRecordingController _rec = ChatRecordingController();
  bool _capping = false;
  bool _accepted = false;
  AudioPlayer? _previewPlayer;
  StreamSubscription<PlayerState>? _playerStateSub;
  PlayerState _playerState = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _rec.addListener(_onTick);
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _rec.state == ChatRecordingState.idle) {
          _rec.start();
        }
      });
    }
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
    unawaited(_playerStateSub?.cancel());
    unawaited(_previewPlayer?.dispose());
    // Release the mic / drop any in-flight recording unless the user accepted it.
    if (!_accepted) {
      _rec.cancelCurrent();
    }
    _rec.dispose();
    super.dispose();
  }

  Future<void> _stopPreviewAudio() async {
    final p = _previewPlayer;
    if (p == null) return;
    try {
      await p.stop();
    } catch (_) {}
    if (mounted) {
      setState(() => _playerState = PlayerState.stopped);
    }
  }

  Future<void> _togglePreviewAudio() async {
    final filePath = _rec.preview?.path;
    if (filePath == null || filePath.isEmpty) return;
    if (_previewPlayer == null) {
      final player = AudioPlayer();
      _previewPlayer = player;
      _playerStateSub = player.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() => _playerState = state);
        }
      });
    }
    final p = _previewPlayer!;
    try {
      if (_playerState == PlayerState.playing) {
        await p.pause();
      } else if (_playerState == PlayerState.paused) {
        await p.resume();
      } else {
        await p.play(
          kIsWeb ? UrlSource(filePath) : DeviceFileSource(filePath),
        );
      }
    } catch (_) {}
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _accept() {
    unawaited(_stopPreviewAudio());
    final file = _rec.previewFile;
    if (file == null) return;
    final mimeType = _rec.preview?.mimeType ?? 'audio/mp4';
    final durationSec = _rec.previewDurationSeconds;
    _accepted = true;
    _rec.completeSend();
    Navigator.of(context).pop(AudioRecordResult(
      file: file,
      mimeType: mimeType,
      durationSec: durationSec,
    ));
  }

  Future<void> _cancel() async {
    await _stopPreviewAudio();
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
              case ChatRecordingState.failed:
                body = _buildFailed(theme);
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
    final isPlaying = _playerState == PlayerState.playing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(theme, 'Запись готова · ${_fmt(_rec.previewDurationSeconds)}'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('audio-record-play'),
          onPressed: _togglePreviewAudio,
          icon: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
          label: Text(isPlaying ? 'Пауза' : 'Послушать запись'),
        ),
        const SizedBox(height: 14),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          overflowAlignment: OverflowBarAlignment.end,
          overflowSpacing: 4,
          children: [
            TextButton.icon(
              key: const Key('audio-record-redo'),
              onPressed: () async {
                await _stopPreviewAudio();
                _capping = false;
                _rec.discardPreview();
                await _rec.start();
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
              child: Text(widget.confirmLabel),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFailed(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(theme, 'Не получилось записать'),
        const SizedBox(height: 8),
        Text(
          _rec.errorText ?? 'Запись не удалась. Попробуйте ещё раз.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const Key('audio-record-close'),
              onPressed: _cancel,
              child: const Text('Закрыть'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('audio-record-retry'),
              onPressed: () {
                _capping = false;
                _rec.start();
              },
              icon: const Icon(Icons.mic_rounded),
              label: const Text('Ещё раз'),
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
