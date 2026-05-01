import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:rodnya/services/call_preferences.dart';

void main() {
  late Directory hiveDirectory;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'rodnya_call_preferences_test_',
    );
    Hive.init(hiveDirectory.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await hiveDirectory.exists()) {
      await hiveDirectory.delete(recursive: true);
    }
  });

  test('HiveCallPreferences persists call defaults', () async {
    const boxName = 'call_preferences_test';
    final store = HiveCallPreferences(boxName: boxName);

    final snapshot = CallPreferencesSnapshot.defaults().copyWith(
      defaultMicrophoneDeviceId: 'mic-usb',
      defaultCameraDeviceId: 'camera-front',
      defaultAudioOutputId: 'speaker',
      ringtoneAsset: 'soft',
      vibrationOnIncoming: false,
    );

    await store.save(snapshot);
    final restored = await HiveCallPreferences(boxName: boxName).load();

    expect(restored.defaultMicrophoneDeviceId, 'mic-usb');
    expect(restored.defaultCameraDeviceId, 'camera-front');
    expect(restored.defaultAudioOutputId, 'speaker');
    expect(restored.ringtoneAsset, 'soft');
    expect(restored.ringtonePreset.label, 'Мягкий');
    expect(restored.vibrationOnIncoming, isFalse);
  });

  test('CallPreferencesSnapshot sanitizes stale ringtone ids', () {
    final snapshot = CallPreferencesSnapshot.fromJson(
      const <String, dynamic>{
        'defaultMicrophoneDeviceId': '',
        'defaultCameraDeviceId': 'camera-back',
        'defaultAudioOutputId': 'speaker',
        'ringtoneAsset': 'missing',
        'vibrationOnIncoming': true,
      },
    );

    expect(snapshot.defaultMicrophoneDeviceId, isNull);
    expect(snapshot.defaultCameraDeviceId, 'camera-back');
    expect(snapshot.defaultAudioOutputId, 'speaker');
    expect(snapshot.ringtoneAsset, 'classic');
    expect(snapshot.vibrationOnIncoming, isTrue);
  });
}
