// ignore_for_file: avoid_web_libraries_in_flutter, uri_does_not_exist, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;

const String _pendingCommandStorageKey = '__rodnyaE2E_pending_command';

Map<String, dynamic> _existingBridgePayload() {
  final existingPayload =
      js_util.getProperty<Object?>(html.window, '__rodnyaE2E');
  final dartPayload =
      existingPayload == null ? null : js_util.dartify(existingPayload);
  if (dartPayload is Map) {
    return Map<String, dynamic>.from(
      dartPayload.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
  }
  return <String, dynamic>{};
}

Map<String, dynamic> _existingScreens() {
  final bridge = _existingBridgePayload();
  final currentScreens = bridge['screens'];
  if (currentScreens is! Map) {
    return <String, dynamic>{};
  }

  return Map<String, dynamic>.from(
    currentScreens.map(
      (key, value) => MapEntry(key.toString(), value),
    ),
  );
}

Map<String, dynamic> _existingCommands() {
  final bridge = _existingBridgePayload();
  final commands = bridge['commands'];
  if (commands is! Map) {
    return <String, dynamic>{};
  }

  return Map<String, dynamic>.from(
    commands.map(
      (key, value) => MapEntry(key.toString(), value),
    ),
  );
}

Map<String, dynamic>? _consumePendingCommand() {
  try {
    final rawPayload = html.window.sessionStorage[_pendingCommandStorageKey];
    if (rawPayload == null || rawPayload.isEmpty) {
      return null;
    }
    html.window.sessionStorage.remove(_pendingCommandStorageKey);
    final decoded = jsonDecode(rawPayload);
    if (decoded is Map) {
      return Map<String, dynamic>.from(
        decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }
  } catch (_) {
    html.window.sessionStorage.remove(_pendingCommandStorageKey);
  }
  return null;
}

void _storePendingCommand(Map<String, dynamic> payload) {
  html.window.sessionStorage[_pendingCommandStorageKey] = jsonEncode(payload);
}

void _setBridgePayload(Map<String, dynamic> payload) {
  js_util.setProperty(
    html.window,
    '__rodnyaE2E',
    js_util.jsify(payload),
  );
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

  commands['login'] = js_util.allowInterop(
    (String email, String password, [String? targetPath]) {
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
      return js_util.jsify(
        _commandAck(
          'login',
          <String, dynamic>{
            'targetPath': targetPath,
          },
        ),
      );
    },
  );
  commands['logout'] = js_util.allowInterop(([String? targetPath]) {
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
    return js_util.jsify(
      _commandAck(
        'logout',
        <String, dynamic>{
          'targetPath': targetPath,
        },
      ),
    );
  });
  commands['status'] = js_util.allowInterop(() {
    final bridgePayload = _existingBridgePayload();
    final screens = bridgePayload['screens'];
    final appState = screens is Map ? screens['app'] : null;
    return js_util.jsify(
      appState is Map
          ? Map<String, dynamic>.from(
              appState.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : <String, dynamic>{},
    );
  });
  commands['go'] = js_util.allowInterop((String path) {
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
    return js_util.jsify(
      _commandAck(
        'go',
        <String, dynamic>{'path': path},
      ),
    );
  });
  commands['openTree'] = js_util.allowInterop(
    (String treeId, [String? treeName, String? targetPath]) {
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
      return js_util.jsify(
        _commandAck(
          'openTree',
          <String, dynamic>{
            'treeId': treeId,
            'treeName': treeName,
            'targetPath': targetPath,
          },
        ),
      );
    },
  );
  commands['openRelative'] = js_util.allowInterop((String personId) {
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
    return js_util.jsify(
      _commandAck(
        'openRelative',
        <String, dynamic>{'personId': personId},
      ),
    );
  });
  commands['openAddRelative'] = js_util.allowInterop((Object? rawConfig) {
    final dartConfig = rawConfig == null ? null : js_util.dartify(rawConfig);
    if (dartConfig is! Map) {
      return js_util.jsify(
        _commandFailure(
          'openAddRelative',
          'Expected openAddRelative config map',
        ),
      );
    }

    final treeId = dartConfig['treeId']?.toString() ?? '';
    if (treeId.isEmpty) {
      return js_util.jsify(
        _commandFailure(
          'openAddRelative',
          'treeId is required',
        ),
      );
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
    return js_util.jsify(
      _commandAck(
        'openAddRelative',
        <String, dynamic>{
          'treeId': treeId,
          'contextPersonId': dartConfig['contextPersonId']?.toString(),
          'relationType': dartConfig['relationType']?.toString(),
          'quickAddMode': dartConfig['quickAddMode'] == true,
        },
      ),
    );
  });
  commands['openStoryViewer'] = js_util.allowInterop((Object? rawConfig) {
    final dartConfig = rawConfig == null ? null : js_util.dartify(rawConfig);
    if (dartConfig != null && dartConfig is! Map) {
      return js_util.jsify(
        _commandFailure(
          'openStoryViewer',
          'Expected openStoryViewer config map',
        ),
      );
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
        html.window.location.hash = normalizedRoute;
        html.window.location.reload();
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
    return js_util.jsify(
      _commandAck(
        'openStoryViewer',
        <String, dynamic>{
          'treeId': config['treeId']?.toString(),
          'authorId': config['authorId']?.toString(),
        },
      ),
    );
  });

  _setBridgePayload(
    <String, dynamic>{
      ...bridge,
      'enabled': true,
      'initializedAt': DateTime.now().toIso8601String(),
      'screens': _existingScreens(),
      'commands': commands,
      'lastCommand': pendingCommand ?? bridge['lastCommand'],
      'runtime': <String, dynamic>{
        'href': html.window.location.href,
        'hash': html.window.location.hash,
        'userAgent': html.window.navigator.userAgent,
      },
    },
  );
}
