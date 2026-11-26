import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../services/audio_route_service.dart';

/// Manages ringing audio/haptics and lifecycle one-shot SFX for [CallScreen].
class CallRingerController {
  CallRingerController({
    required AudioRouteService Function() audioRouteService,
    required bool Function() isMounted,
  })  : _audioRouteService = audioRouteService,
        _isMounted = isMounted;

  final AudioRouteService Function() _audioRouteService;
  final bool Function() _isMounted;

  Timer? _ringerTimer;
  Timer? _vibrationPulseTimer;
  AudioPlayer? _ringerPlayer;
  final Set<AudioPlayer> _oneShotPlayers = <AudioPlayer>{};
  bool _ringerActive = false;

  /// Start the ringer loop when the call is ringing — incoming gets
  /// the loud `ringtone.wav` arpeggio with haptic pulses, outgoing
  /// gets the classic `ringback.wav` (gudok) without vibration. Stop
  /// on any non-ringing state.
  void syncRinger({required bool isRinging, required bool isIncoming}) {
    if (!_isMounted()) return;
    if (isRinging && !_ringerActive) {
      startRinger(incoming: isIncoming);
    } else if (!isRinging && _ringerActive) {
      stopRinger();
    }
  }

  void startRinger({required bool incoming}) {
    // Skip ringer in flutter_test's binding so widget tests don't
    // hang on the periodic Timer / pumpAndSettle. Detected via
    // binding-name comparison so we don't import flutter_test from
    // production code.
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    if (bindingName.contains('TestWidgetsFlutterBinding')) return;
    _ringerActive = true;
    final player = _ringerPlayer ??= AudioPlayer();

    // Bundled WAVs: ringtone.wav (~2.8s arpeggio) for incoming,
    // ringback.wav (~4s 1s-on / 3s-off RBT pattern) for outgoing.
    // Both loop seamlessly via ReleaseMode.loop. The asset path
    // omits `assets/` because audioplayers' AssetSource resolves
    // against the asset bundle root.
    final asset = incoming ? 'audio/ringtone.wav' : 'audio/ringback.wav';
    unawaited(() async {
      try {
        // Critical: route through the telephony usage type so
        // Android plays the audio on the **ringtone stream** (or
        // VoIP stream for ringback). Without this, audioplayers
        // defaults to `usageType: media` which is silenced when the
        // device is on Vibrate-only or DND, *and* gets ducked when
        // any media is playing — that's why the user reported
        // «никакого аудио нет». On iOS, set the playAndRecord
        // category with default-to-speaker so the ringer comes out
        // of the loudspeaker even mid-call.
        await player.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              isSpeakerphoneOn: true,
              audioMode: incoming
                  ? AndroidAudioMode.ringtone
                  : AndroidAudioMode.inCommunication,
              stayAwake: true,
              contentType: AndroidContentType.music,
              usageType: incoming
                  ? AndroidUsageType.notificationRingtone
                  : AndroidUsageType.voiceCommunicationSignalling,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playAndRecord,
              options: const {
                AVAudioSessionOptions.defaultToSpeaker,
                AVAudioSessionOptions.allowBluetooth,
              },
            ),
          ),
        );
        await player.setReleaseMode(ReleaseMode.loop);
        // Lower volume for the gudok — it's a confirmation tone, not
        // a wake-the-house alert. Incoming stays loud.
        await player.setVolume(incoming ? 1.0 : 0.55);
        await player.play(AssetSource(asset));
      } catch (error) {
        debugPrint('[call] ringer audio failed: $error');
      }
    }());

    if (incoming) {
      // Haptic pulses ride alongside the audio — works on silent
      // mode and gives mid-range Samsung devices the «double-tap»
      // rhythm that's easier to feel than a single buzz.
      void pulse() {
        if (!_ringerActive || !_isMounted()) return;
        HapticFeedback.vibrate();
        _vibrationPulseTimer?.cancel();
        _vibrationPulseTimer = Timer(const Duration(milliseconds: 700), () {
          _vibrationPulseTimer = null;
          if (!_ringerActive || !_isMounted()) return;
          HapticFeedback.heavyImpact();
        });
      }

      pulse();
      _ringerTimer = Timer.periodic(
        const Duration(milliseconds: 1400),
        (_) => pulse(),
      );
    }
  }

  void stopRinger() {
    _ringerActive = false;
    _ringerTimer?.cancel();
    _ringerTimer = null;
    _vibrationPulseTimer?.cancel();
    _vibrationPulseTimer = null;
    final player = _ringerPlayer;
    _ringerPlayer = null;
    // audioplayers выставляет AudioManager.MODE_RINGTONE под входящий рингер
    // (AndroidAudioMode.ringtone) и НЕ восстанавливает его на stop/dispose.
    // Если звонок закончился на этапе звонка (никогда не было startCallAudio),
    // режим RINGTONE залипал → кнопки громкости телефона переставали работать
    // (фантомный вызов). Возвращаем NORMAL ПОСЛЕ полного teardown плеера;
    // натив сам гардит на активную сессию (см. resetRingtoneModeIfIdle), так
    // что переход ringing→active его не затронет.
    unawaited(() async {
      try {
        await player?.stop();
      } catch (_) {}
      try {
        await player?.dispose();
      } catch (_) {}
      try {
        await _audioRouteService().resetRingtoneModeIfIdle();
      } catch (_) {}
    }());
  }

  /// One-shot SFX for call lifecycle transitions — `connect.wav` when
  /// the remote picks up, `hangup.wav` when the line drops. Plays on
  /// a separate AudioPlayer so it doesn't clobber the ringer loop.
  void playOneShot(String asset) {
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    if (bindingName.contains('TestWidgetsFlutterBinding')) return;
    final player = AudioPlayer();
    _oneShotPlayers.add(player);
    unawaited(() async {
      StreamSubscription<void>? completeSub;
      Future<void> disposePlayer() async {
        _oneShotPlayers.remove(player);
        await completeSub?.cancel();
        try {
          await player.dispose();
        } catch (_) {}
      }

      try {
        await player.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: true,
              audioMode: AndroidAudioMode.normal,
              stayAwake: false,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.assistanceSonification,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.ambient,
              options: const {AVAudioSessionOptions.mixWithOthers},
            ),
          ),
        );
        await player.setReleaseMode(ReleaseMode.stop);
        completeSub = player.onPlayerComplete.listen((_) {
          unawaited(disposePlayer());
        });
        await player.play(AssetSource(asset));
      } catch (error) {
        debugPrint('[call] one-shot audio failed: $error');
        await disposePlayer();
      }
    }());
  }

  void dispose() {
    stopRinger();
    for (final player in _oneShotPlayers.toList()) {
      unawaited(player.dispose().catchError((_) {}));
    }
    _oneShotPlayers.clear();
  }
}
