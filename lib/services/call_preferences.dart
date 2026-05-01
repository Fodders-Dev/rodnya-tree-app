import 'dart:convert';

import 'package:hive/hive.dart';

const Object _unset = Object();

class CallRingtonePreset {
  const CallRingtonePreset({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

const List<CallRingtonePreset> callRingtonePresets = <CallRingtonePreset>[
  CallRingtonePreset(
    id: 'classic',
    label: 'Классический',
    description: 'Звонок Родни по умолчанию',
  ),
  CallRingtonePreset(
    id: 'soft',
    label: 'Мягкий',
    description: 'Тише для домашних звонков',
  ),
  CallRingtonePreset(
    id: 'none',
    label: 'Без звука',
    description: 'Только экран и вибрация',
  ),
];

CallRingtonePreset callRingtonePresetById(String id) {
  for (final preset in callRingtonePresets) {
    if (preset.id == id) {
      return preset;
    }
  }
  return callRingtonePresets.first;
}

class CallPreferencesSnapshot {
  const CallPreferencesSnapshot({
    this.defaultMicrophoneDeviceId,
    this.defaultCameraDeviceId,
    this.defaultAudioOutputId,
    required this.ringtoneAsset,
    required this.vibrationOnIncoming,
  });

  final String? defaultMicrophoneDeviceId;
  final String? defaultCameraDeviceId;
  final String? defaultAudioOutputId;
  final String ringtoneAsset;
  final bool vibrationOnIncoming;

  factory CallPreferencesSnapshot.defaults() {
    return const CallPreferencesSnapshot(
      ringtoneAsset: 'classic',
      vibrationOnIncoming: true,
    );
  }

  CallRingtonePreset get ringtonePreset =>
      callRingtonePresetById(ringtoneAsset);

  CallPreferencesSnapshot copyWith({
    Object? defaultMicrophoneDeviceId = _unset,
    Object? defaultCameraDeviceId = _unset,
    Object? defaultAudioOutputId = _unset,
    String? ringtoneAsset,
    bool? vibrationOnIncoming,
  }) {
    return CallPreferencesSnapshot(
      defaultMicrophoneDeviceId: defaultMicrophoneDeviceId == _unset
          ? this.defaultMicrophoneDeviceId
          : defaultMicrophoneDeviceId as String?,
      defaultCameraDeviceId: defaultCameraDeviceId == _unset
          ? this.defaultCameraDeviceId
          : defaultCameraDeviceId as String?,
      defaultAudioOutputId: defaultAudioOutputId == _unset
          ? this.defaultAudioOutputId
          : defaultAudioOutputId as String?,
      ringtoneAsset: ringtoneAsset ?? this.ringtoneAsset,
      vibrationOnIncoming: vibrationOnIncoming ?? this.vibrationOnIncoming,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'defaultMicrophoneDeviceId': defaultMicrophoneDeviceId,
      'defaultCameraDeviceId': defaultCameraDeviceId,
      'defaultAudioOutputId': defaultAudioOutputId,
      'ringtoneAsset': ringtoneAsset,
      'vibrationOnIncoming': vibrationOnIncoming,
    };
  }

  factory CallPreferencesSnapshot.fromJson(Map<String, dynamic> json) {
    String? optionalString(Object? value) {
      final text = value?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }

    final ringtoneAsset = optionalString(json['ringtoneAsset']) ?? 'classic';
    return CallPreferencesSnapshot(
      defaultMicrophoneDeviceId:
          optionalString(json['defaultMicrophoneDeviceId']),
      defaultCameraDeviceId: optionalString(json['defaultCameraDeviceId']),
      defaultAudioOutputId: optionalString(json['defaultAudioOutputId']),
      ringtoneAsset: callRingtonePresetById(ringtoneAsset).id,
      vibrationOnIncoming: json['vibrationOnIncoming'] is bool
          ? json['vibrationOnIncoming'] as bool
          : true,
    );
  }
}

abstract class CallPreferences {
  Future<CallPreferencesSnapshot> load();

  Future<void> save(CallPreferencesSnapshot snapshot);
}

class DisabledCallPreferences implements CallPreferences {
  const DisabledCallPreferences();

  @override
  Future<CallPreferencesSnapshot> load() async {
    return CallPreferencesSnapshot.defaults();
  }

  @override
  Future<void> save(CallPreferencesSnapshot snapshot) async {}
}

class MemoryCallPreferences implements CallPreferences {
  MemoryCallPreferences([CallPreferencesSnapshot? initialSnapshot])
      : _snapshot = initialSnapshot ?? CallPreferencesSnapshot.defaults();

  CallPreferencesSnapshot _snapshot;

  @override
  Future<CallPreferencesSnapshot> load() async {
    return _snapshot;
  }

  @override
  Future<void> save(CallPreferencesSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}

class HiveCallPreferences implements CallPreferences {
  HiveCallPreferences({
    this.boxName = 'call_preferences_v1',
  });

  final String boxName;
  static const String _snapshotKey = 'snapshot';
  Future<Box<String>>? _openTask;

  Future<Box<String>> _openBox() {
    if (Hive.isBoxOpen(boxName)) {
      return Future<Box<String>>.value(Hive.box<String>(boxName));
    }
    return _openTask ??= Hive.openBox<String>(boxName);
  }

  @override
  Future<CallPreferencesSnapshot> load() async {
    final box = await _openBox();
    final raw = box.get(_snapshotKey);
    if (raw == null || raw.isEmpty) {
      return CallPreferencesSnapshot.defaults();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return CallPreferencesSnapshot.defaults();
      }
      return CallPreferencesSnapshot.fromJson(decoded);
    } catch (_) {
      return CallPreferencesSnapshot.defaults();
    }
  }

  @override
  Future<void> save(CallPreferencesSnapshot snapshot) async {
    final box = await _openBox();
    await box.put(_snapshotKey, jsonEncode(snapshot.toJson()));
  }
}
