import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/app_notification_item.dart';

/// On-disk cache for the notifications inbox.
///
/// Same shape as `ChatPreviewCache` — a single JSON-encoded list under
/// a fixed key. The list is small (typically up to ~50 items) so we
/// just rewrite the whole thing every time the screen receives a
/// fresh batch from the API. Used by the notifications screen to
/// serve cached items immediately on cold-start / offline so the
/// inbox isn't blank while the network call is in flight.
abstract class NotificationsCache {
  Future<List<AppNotificationItem>> read();

  Future<void> write(List<AppNotificationItem> items);

  Future<void> clear();
}

class HiveNotificationsCache implements NotificationsCache {
  HiveNotificationsCache({this.boxName = 'notifications_v1'});

  final String boxName;
  static const String _key = 'items';
  Future<Box<String>>? _openTask;

  Future<Box<String>> _box() {
    if (Hive.isBoxOpen(boxName)) {
      return Future<Box<String>>.value(Hive.box<String>(boxName));
    }
    return _openTask ??= Hive.openBox<String>(boxName);
  }

  @override
  Future<List<AppNotificationItem>> read() async {
    try {
      final raw = (await _box()).get(_key);
      if (raw == null || raw.trim().isEmpty) {
        return const <AppNotificationItem>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return const <AppNotificationItem>[];
      return decoded
          .whereType<Map>()
          .map((entry) => AppNotificationItem.fromCacheMap(
                Map<String, dynamic>.from(entry),
              ))
          .toList(growable: false);
    } catch (_) {
      // Corrupt cache → swallow, let API repopulate.
      return const <AppNotificationItem>[];
    }
  }

  @override
  Future<void> write(List<AppNotificationItem> items) async {
    try {
      await (await _box()).put(
        _key,
        jsonEncode(items.map((i) => i.toMap()).toList(growable: false)),
      );
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await (await _box()).delete(_key);
    } catch (_) {}
  }
}

class InMemoryNotificationsCache implements NotificationsCache {
  List<AppNotificationItem> _items = const <AppNotificationItem>[];

  @override
  Future<List<AppNotificationItem>> read() async => List.of(_items);

  @override
  Future<void> write(List<AppNotificationItem> items) async {
    _items = List.of(items);
  }

  @override
  Future<void> clear() async {
    _items = const <AppNotificationItem>[];
  }
}
