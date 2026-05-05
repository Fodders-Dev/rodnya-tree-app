import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Opens a Hive `Box<T>` with one-shot corruption recovery.
///
/// Vanilla `Hive.openBox` will throw if the on-disk box is corrupted
/// (interrupted write / OS crash / FS issue) or if the schema of the
/// stored data is incompatible with the current adapter set. Either
/// case used to leave the cache permanently broken — the app would
/// keep retrying the same `openBox` call forever and silently lose
/// the cache surface.
///
/// This helper:
///   1. Returns the already-open box if any.
///   2. Tries `openBox`. Returns it on success.
///   3. On any error, calls `deleteBoxFromDisk` and tries once more.
///   4. If the second attempt still fails, rethrows. Callers are
///      expected to catch and degrade gracefully (e.g. fall back to
///      in-memory cache or skip cache).
///
/// All cache implementations route through this so the recovery path
/// stays consistent.
Future<Box<T>> openBoxWithRecovery<T>(String boxName) async {
  if (Hive.isBoxOpen(boxName)) {
    return Hive.box<T>(boxName);
  }

  try {
    return await Hive.openBox<T>(boxName);
  } catch (error, stackTrace) {
    debugPrint(
      'Hive box "$boxName" failed to open — deleting and retrying: '
      '$error\n$stackTrace',
    );
    try {
      await Hive.deleteBoxFromDisk(boxName);
    } catch (deleteError) {
      debugPrint(
        'Hive box "$boxName" delete-on-corruption failed: $deleteError',
      );
    }
    // Second attempt. If this also fails, let the exception bubble
    // up so the caller can decide whether to fall back to memory.
    return Hive.openBox<T>(boxName);
  }
}
