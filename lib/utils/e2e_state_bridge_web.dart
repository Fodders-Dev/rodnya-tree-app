import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

const String _pendingCommandStorageKey = '__rodnyaE2E_pending_command';

Map<String, dynamic> _asStringMap(Object? raw) {
  if (raw is Map) {
    return Map<String, dynamic>.from(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
  return <String, dynamic>{};
}

Map<String, dynamic> _existingBridgePayload() {
  final existingPayload = web.window.getProperty<JSAny?>('__rodnyaE2E'.toJS);
  final dartPayload = existingPayload?.dartify();
  return _asStringMap(dartPayload);
}

Map<String, dynamic> _existingScreens() {
  final bridge = _existingBridgePayload();
  return _asStringMap(bridge['screens']);
}

Map<String, dynamic> _existingCommands() {
  final bridge = _existingBridgePayload();
  return _asStringMap(bridge['commands']);
}

Map<String, dynamic>? _consumePendingCommand() {
  try {
    final rawPayload =
        web.window.sessionStorage.getItem(_pendingCommandStorageKey);
    if (rawPayload == null || rawPayload.isEmpty) {
      return null;
    }
    web.window.sessionStorage.removeItem(_pendingCommandStorageKey);
    final decoded = jsonDecode(rawPayload);
    if (decoded is Map) {
      return _asStringMap(decoded);
    }
  } catch (_) {
    web.window.sessionStorage.removeItem(_pendingCommandStorageKey);
  }
  return null;
}

void _storePendingCommand(Map<String, dynamic> payload) {
  web.window.sessionStorage.setItem(
    _pendingCommandStorageKey,
    jsonEncode(payload),
  );
}

void _setBridgePayload(Map<String, dynamic> payload) {
  web.window.setProperty('__rodnyaE2E'.toJS, payload.jsify());
}

Map<String, dynamic> _commandAck(
  String name, [
  Map<String, dynamic> details = const <String, dynamic>{},
]) {
  return <String, dynamic>{
    'accepted': true,
    'command': name,
    'requestedAt': DateTime.now().toIso8601String(),
    ...details,
  };
}

Map<String, dynamic> _commandFailure(
  String name,
  String message,
) {
  return <String, dynamic>{
    'accepted': false,
    'command': name,
    'requestedAt': DateTime.now().toIso8601String(),
    'message': message,
  };
}

void _publishCommandResult({
  required String name,
  Map<String, dynamic>? result,
  Object? error,
}) {
  final bridge = _existingBridgePayload();
  _setBridgePayload(
    <String, dynamic>{
      ...bridge,
      'lastCommand': <String, dynamic>{
        'name': name,
        'completedAt': DateTime.now().toIso8601String(),
        if (result != null) 'result': result,
        if (error != null) 'error': error.toString(),
      },
      'screens': _existingScreens(),
      'commands': _existingCommands(),
    },
  );
}

void publishState(Map<String, dynamic> payload) {
  final existingScreens = _existingScreens();
  final bridge = _existingBridgePayload();
  final screen = payload['screen']?.toString() ?? 'unknown';
  existingScreens[screen] = payload['state'];

  _setBridgePayload(
    <String, dynamic>{
      ...bridge,
      ...payload,
      'enabled': true,
      'screens': existingScreens,
      'commands': _existingCommands(),
      'lastCommand': bridge['lastCommand'],
    },
  );
}

void initializeBridge({
  required Future<Map<String, dynamic>> Function(
    String email,
    String password,
    String? targetPath,
  ) onLogin,
  required Future<Map<String, dynamic>> Function(String? targetPath) onLogout,
  required Future<Map<String, dynamic>> Function() onStatus,
  required Future<Map<String, dynamic>> Function(String path) onNavigate,
  required Future<Map<String, dynamic>> Function(
    String treeId,
    String? treeName,
    String? targetPath,
  ) onOpenTree,
  required Future<Map<String, dynamic>> Function({
    required String treeId,
    String? contextPersonId,
    String? relationType,
    bool quickAddMode,
  }) onOpenAddRelative,
  required Future<Map<String, dynamic>> Function({
    String? treeId,
    String? authorId,
  }) onOpenStoryViewer,
}) {
  final bridge = _existingBridgePayload();
  final commands = _existingCommands();
  final pendingCommand = _consumePendingCommand();

  commands['login'] = ((
    String email,
    String password, [
    String? targetPath,
  ]) {
    onLogin(email, password, targetPath)
        .then(
          (result) => _publishCommandResult(
            name: 'login',
            result: result,
          ),
        )
        .catchError(
          (Object error) => _publishCommandResult(
            name: 'login',
            error: error,
          ),
        );
    return _commandAck(
      'login',
      <String, dynamic>{
        'targetPath': targetPath,
      },
    ).jsify();
  }).toJS;
  commands['logout'] = (([String? targetPath]) {
    onLogout(targetPath)
        .then(
          (result) => _publishCommandResult(
            name: 'logout',
            result: result,
          ),
        )
        .catchError(
          (Object error) => _publishCommandResult(
            name: 'logout',
            error: error,
          ),
        );
    return _commandAck(
      'logout',
      <String, dynamic>{
        'targetPath': targetPath,
      },
    ).jsify();
  }).toJS;
  commands['status'] = (() {
    final bridgePayload = _existingBridgePayload();
    final screens = bridgePayload['screens'];
    final appState = screens is Map ? screens['app'] : null;
    return _asStringMap(appState).jsify();
  }).toJS;
  commands['go'] = ((String path) {
    onNavigate(path)
        .then(
          (result) => _publishCommandResult(
            name: 'go',
            result: result,
          ),
        )
        .catchError(
          (Object error) => _publishCommandResult(
            name: 'go',
            error: error,
          ),
        );
    return _commandAck(
      'go',
      <String, dynamic>{'path': path},
    ).jsify();
  }).toJS;
  commands['openTree'] = ((
    String treeId, [
    String? treeName,
    String? targetPath,
  ]) {
    onOpenTree(treeId, treeName, targetPath)
        .then(
          (result) => _publishCommandResult(
            name: 'openTree',
            result: result,
          ),
        )
        .catchError(
          (Object error) => _publishCommandResult(
            name: 'openTree',
            error: error,
          ),
        );
    return _commandAck(
      'openTree',
      <String, dynamic>{
        'treeId': treeId,
        'treeName': treeName,
        'targetPath': targetPath,
      },
    ).jsify();
  }).toJS;
  commands['openRelative'] = ((String personId) {
    onNavigate('/relative/details/$personId')
        .then(
          (result) => _publishCommandResult(
            name: 'openRelative',
            result: result,
          ),
        )
        .catchError(
          (Object error) => _publishCommandResult(
            name: 'openRelative',
            error: error,
          ),
        );
    return _commandAck(
      'openRelative',
      <String, dynamic>{'personId': personId},
    ).jsify();
  }).toJS;
  commands['openAddRelative'] = ((JSAny? rawConfig) {
    final dartConfig = rawConfig?.dartify();
    if (dartConfig is! Map) {
      return _commandFailure(
        'openAddRelative',
        'Expected openAddRelative config map',
      ).jsify();
    }

    final treeId = dartConfig['treeId']?.toString() ?? '';
    if (treeId.isEmpty) {
      return _commandFailure(
        'openAddRelative',
        'treeId is required',
      ).jsify();
    }

    onOpenAddRelative(
      treeId: treeId,
      contextPersonId: dartConfig['contextPersonId']?.toString(),
      relationType: dartConfig['relationType']?.toString(),
      quickAddMode: dartConfig['quickAddMode'] == true,
    )
        .then(
          (result) => _publishCommandResult(
            name: 'openAddRelative',
            result: result,
          ),
        )
        .catchError(
          (Object error) => _publishCommandResult(
            name: 'openAddRelative',
            error: error,
          ),
        );
    return _commandAck(
      'openAddRelative',
      <String, dynamic>{
        'treeId': treeId,
        'contextPersonId': dartConfig['contextPersonId']?.toString(),
        'relationType': dartConfig['relationType']?.toString(),
        'quickAddMode': dartConfig['quickAddMode'] == true,
      },
    ).jsify();
  }).toJS;
  commands['openStoryViewer'] = ((JSAny? rawConfig) {
    final dartConfig = rawConfig?.dartify();
    if (dartConfig != null && dartConfig is! Map) {
      return _commandFailure(
        'openStoryViewer',
        'Expected openStoryViewer config map',
      ).jsify();
    }

    final config = dartConfig is Map ? dartConfig : const <Object?, Object?>{};
    onOpenStoryViewer(
      treeId: config['treeId']?.toString(),
      authorId: config['authorId']?.toString(),
    ).then((result) async {
      final route = result['storyViewerRoute']?.toString();
      if (route != null && route.isNotEmpty) {
        _storePendingCommand(
          <String, dynamic>{
            'name': 'openStoryViewer',
            'completedAt': DateTime.now().toIso8601String(),
            'result': result,
          },
        );
        final normalizedRoute = route.startsWith('/') ? route : '/$route';
        web.window.location.hash = normalizedRoute;
        web.window.location.reload();
        return;
      }
      _publishCommandResult(
        name: 'openStoryViewer',
        result: result,
      );
    }).catchError((Object error) {
      _publishCommandResult(
        name: 'openStoryViewer',
        error: error,
      );
      return null;
    });
    return _commandAck(
      'openStoryViewer',
      <String, dynamic>{
        'treeId': config['treeId']?.toString(),
        'authorId': config['authorId']?.toString(),
      },
    ).jsify();
  }).toJS;

  _setBridgePayload(
    <String, dynamic>{
      ...bridge,
      'enabled': true,
      'initializedAt': DateTime.now().toIso8601String(),
      'screens': _existingScreens(),
      'commands': commands,
      'lastCommand': pendingCommand ?? bridge['lastCommand'],
      'runtime': <String, dynamic>{
        'href': web.window.location.href,
        'hash': web.window.location.hash,
        'userAgent': web.window.navigator.userAgent,
      },
    },
  );
}
