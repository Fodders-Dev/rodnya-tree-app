import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'navigation/app_router.dart';
import 'services/local_storage_service.dart';
import 'package:get_it/get_it.dart';
import 'providers/tree_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/scheduler.dart'; // Для postFrameCallback
import 'package:shared_preferences/shared_preferences.dart';
import 'backend/interfaces/app_startup_service_interface.dart';
import 'backend/interfaces/auth_service_interface.dart';
import 'backend/interfaces/story_service_interface.dart';
import 'backend/backend_runtime_config.dart';
import 'services/app_startup_service.dart';
import 'services/call_coordinator_service.dart';
import 'startup/startup_failure_policy.dart';
import 'startup/app_warmup_coordinator.dart';
import 'widgets/call_runtime_host.dart';
import 'widgets/startup_failure_view.dart';
import 'utils/e2e_state_bridge.dart';

// --- Переменная для хранения SnackBarContext ---
// Используем GlobalKey, чтобы получить доступ к ScaffoldMessenger
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
Object? _e2eSemanticsHandle;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _bootstrapAndRunApp();
}

Future<void> _bootstrapAndRunApp() async {
  try {
    if (!GetIt.I.isRegistered<AppStartupServiceInterface>()) {
      GetIt.I
          .registerSingleton<AppStartupServiceInterface>(AppStartupService());
    }
    await GetIt.I<AppStartupServiceInterface>().initializeForeground();

    final localStorageService = GetIt.I<LocalStorageService>();
    final runtimeConfig = BackendRuntimeConfig.current;

    if (kIsWeb && runtimeConfig.enableE2e) {
      _e2eSemanticsHandle ??= WidgetsBinding.instance.ensureSemantics();
    }

    // На web не тянем .env как asset, чтобы не получать лишний 404 в консоли.
    if (!kIsWeb && kDebugMode) {
      try {
        await dotenv.load(fileName: ".env");
        debugPrint('.env file loaded successfully.');
      } catch (e) {
        debugPrint(
          'Error loading .env file: $e. Ensure the file exists at the project root and is listed in pubspec.yaml assets.',
        );
      }
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(
            create: (_) => GetIt.I<TreeProvider>(),
          ),
          Provider<LocalStorageService>.value(value: localStorageService),
        ],
        child: const MyApp(),
      ),
    );
  } catch (error, stackTrace) {
    final canResetSession = await _shouldOfferSessionReset(error);
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'rodnya_bootstrap',
        context: ErrorDescription('while starting the application'),
      ),
    );
    runApp(
      _StartupFailureApp(
        error: error,
        stackTrace: stackTrace,
        onRetry: _bootstrapAndRunApp,
        onResetSessionAndRetry:
            canResetSession ? _resetRecoverableSessionAndRetry : null,
        canResetSession: canResetSession,
      ),
    );
  }
}

Future<void> _resetRecoverableSessionAndRetry() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.remove('custom_api_session_v1');
  await _bootstrapAndRunApp();
}

Future<bool> _shouldOfferSessionReset(Object error) async {
  if (looksLikeRecoverableSessionIssue(error)) {
    return true;
  }

  final preferences = await SharedPreferences.getInstance();
  return preferences.containsKey('custom_api_session_v1');
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AppRouter _appRouter;
  VoidCallback? _routerE2EListener;

  @override
  void initState() {
    super.initState();
    _appRouter = AppRouter();
    _configureE2EBridge();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !GetIt.I.isRegistered<AppWarmupCoordinator>()) {
        return;
      }
      unawaited(
        GetIt.I<AppWarmupCoordinator>().start(scaffoldMessengerKey),
      );
    });
  }

  @override
  void dispose() {
    final routerE2EListener = _routerE2EListener;
    if (routerE2EListener != null) {
      _appRouter.router.routerDelegate.removeListener(routerE2EListener);
    }
    if (GetIt.I.isRegistered<AppWarmupCoordinator>()) {
      unawaited(GetIt.I<AppWarmupCoordinator>().dispose());
    }
    super.dispose();
  }

  void _configureE2EBridge() {
    if (!kIsWeb || !BackendRuntimeConfig.current.enableE2e) {
      return;
    }

    E2EStateBridge.initialize(
      onLogin: _handleE2ELogin,
      onLogout: _handleE2ELogout,
      onStatus: _collectE2EStatus,
      onNavigate: _handleE2ENavigate,
      onOpenTree: _handleE2EOpenTree,
      onOpenAddRelative: _handleE2EOpenAddRelative,
      onOpenStoryViewer: _handleE2EOpenStoryViewer,
    );

    _routerE2EListener ??= _publishAppE2EState;
    _appRouter.router.routerDelegate.addListener(_routerE2EListener!);
    _publishAppE2EState();
  }

  Future<Map<String, dynamic>> _handleE2ELogin(
    String email,
    String password,
    String? targetPath,
  ) async {
    await GetIt.I<AuthServiceInterface>().loginWithEmail(email, password);
    final targetTreeId = _extractTreeIdFromPath(targetPath);
    final targetTreeName = _extractTreeNameFromPath(targetPath);
    await _syncTreeProviderAfterLogin(
      preferredTreeId: targetTreeId,
      preferredTreeName: targetTreeName,
    );
    await _navigateE2E(
      targetPath != null && targetPath.isNotEmpty ? targetPath : '/',
    );
    return _collectE2EStatus();
  }

  Future<Map<String, dynamic>> _handleE2ELogout(String? targetPath) async {
    await _navigateE2E('/__e2e__/idle');
    await Future<void>.delayed(const Duration(milliseconds: 220));
    await GetIt.I<AuthServiceInterface>().signOut();
    await _clearTreeProviderSelection();
    await _navigateE2E(
      targetPath != null && targetPath.isNotEmpty ? targetPath : '/login',
    );
    return _collectE2EStatus();
  }

  Future<Map<String, dynamic>> _collectE2EStatus() async {
    final authService = GetIt.I<AuthServiceInterface>();
    final treeProvider =
        GetIt.I.isRegistered<TreeProvider>() ? GetIt.I<TreeProvider>() : null;
    final isLoggedIn = authService.currentUserId != null;
    final profileStatus = isLoggedIn
        ? await authService.checkProfileCompleteness()
        : <String, dynamic>{
            'isComplete': false,
            'missingFields': const <String>['auth'],
          };

    return <String, dynamic>{
      'isLoggedIn': authService.currentUserId != null,
      'currentUserId': authService.currentUserId,
      'currentUserEmail': authService.currentUserEmail,
      'currentUserDisplayName': authService.currentUserDisplayName,
      'selectedTreeId': treeProvider?.selectedTreeId,
      'selectedTreeName': treeProvider?.selectedTreeName,
      'selectedTreeKind': treeProvider?.selectedTreeKind?.name,
      'profileStatus': profileStatus,
      'currentUrl': Uri.base.toString(),
      'currentPath': Uri.base.path,
      'currentHash': Uri.base.fragment,
    };
  }

  Future<Map<String, dynamic>> _handleE2ENavigate(String path) async {
    if (path.isEmpty) {
      return _collectE2EStatus();
    }
    return _navigateE2E(path);
  }

  Future<Map<String, dynamic>> _handleE2EOpenTree(
    String treeId,
    String? treeName,
    String? targetPath,
  ) async {
    await _selectTreeForE2E(treeId, treeName);
    final resolvedTarget = targetPath?.isNotEmpty == true
        ? targetPath!
        : _buildTreeRoute(treeId, treeName);
    return _navigateE2E(resolvedTarget);
  }

  Future<Map<String, dynamic>> _handleE2EOpenAddRelative({
    required String treeId,
    String? contextPersonId,
    String? relationType,
    bool quickAddMode = false,
  }) async {
    await _selectTreeForE2E(treeId, null);
    final uri = Uri(
      path: '/relatives/add/$treeId',
      queryParameters: <String, String>{
        if (contextPersonId != null && contextPersonId.isNotEmpty)
          'contextPersonId': contextPersonId,
        if (relationType != null && relationType.isNotEmpty)
          'relationType': relationType,
        if (quickAddMode) 'quickAddMode': '1',
      },
    );
    return _navigateE2E(uri.toString());
  }

  Future<Map<String, dynamic>> _handleE2EOpenStoryViewer({
    String? treeId,
    String? authorId,
  }) async {
    final authService = GetIt.I<AuthServiceInterface>();
    final resolvedAuthorId = authorId?.trim().isNotEmpty == true
        ? authorId!.trim()
        : authService.currentUserId;
    final selectedTreeId = GetIt.I.isRegistered<TreeProvider>()
        ? GetIt.I<TreeProvider>().selectedTreeId
        : null;
    final resolvedTreeId =
        treeId?.trim().isNotEmpty == true ? treeId!.trim() : selectedTreeId;

    if (resolvedTreeId == null || resolvedTreeId.isEmpty) {
      throw StateError('No tree selected for story viewer');
    }
    if (resolvedAuthorId == null || resolvedAuthorId.isEmpty) {
      throw StateError('No author resolved for story viewer');
    }

    await _selectTreeForE2E(resolvedTreeId, null);
    final stories = await GetIt.I<StoryServiceInterface>().getStories(
      treeId: resolvedTreeId,
      authorId: resolvedAuthorId,
    );
    if (stories.isEmpty) {
      throw StateError('No stories available for author $resolvedAuthorId');
    }

    final route = '/stories/view/$resolvedTreeId/$resolvedAuthorId';
    final status = await _collectE2EStatus();
    return <String, dynamic>{
      ...status,
      'storyViewerRequested': true,
      'storyViewerRoute': route,
      'storyCount': stories.length,
      'currentStoryId': stories.first.id,
    };
  }

  void _publishAppE2EState() {
    if (!mounted || !kIsWeb || !BackendRuntimeConfig.current.enableE2e) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final status = await _collectE2EStatus();
      if (!mounted) {
        return;
      }
      E2EStateBridge.publish(
        screen: 'app',
        state: status,
      );
    });
  }

  Future<Map<String, dynamic>> _navigateE2E(String path) async {
    _appRouter.router.go(path);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    _publishAppE2EState();
    return _collectE2EStatus();
  }

  Future<void> _syncTreeProviderAfterLogin({
    String? preferredTreeId,
    String? preferredTreeName,
  }) async {
    if (!GetIt.I.isRegistered<TreeProvider>()) {
      return;
    }

    final treeProvider = GetIt.I<TreeProvider>();
    if (preferredTreeId != null && preferredTreeId.isNotEmpty) {
      await treeProvider.selectTree(preferredTreeId, preferredTreeName);
      return;
    }

    await treeProvider.clearSelection();
    await treeProvider.selectDefaultTreeIfNeeded();
  }

  Future<void> _clearTreeProviderSelection() async {
    if (!GetIt.I.isRegistered<TreeProvider>()) {
      return;
    }
    await GetIt.I<TreeProvider>().clearSelection();
  }

  Future<void> _selectTreeForE2E(
    String treeId,
    String? treeName,
  ) async {
    if (!GetIt.I.isRegistered<TreeProvider>()) {
      return;
    }
    final treeProvider = GetIt.I<TreeProvider>();
    final resolvedTreeName = (treeName != null && treeName.isNotEmpty)
        ? treeName
        : (treeProvider.selectedTreeId == treeId
            ? treeProvider.selectedTreeName
            : null);
    await treeProvider.selectTree(treeId, resolvedTreeName);
  }

  String _buildTreeRoute(String treeId, String? treeName) {
    final uri = Uri(
      path: '/tree/view/$treeId',
      queryParameters: <String, String>{
        if (treeName != null && treeName.isNotEmpty) 'name': treeName,
      },
    );
    return uri.toString();
  }

  String? _extractTreeIdFromPath(String? targetPath) {
    if (targetPath == null || targetPath.trim().isEmpty) {
      return null;
    }
    final normalizedPath =
        targetPath.startsWith('#') ? targetPath.substring(1) : targetPath;
    final uri = Uri.tryParse(normalizedPath);
    final segments = uri?.pathSegments ?? const <String>[];
    if (segments.length >= 3 &&
        segments[0] == 'tree' &&
        segments[1] == 'view') {
      final treeId = segments[2].trim();
      return treeId.isEmpty ? null : treeId;
    }
    return null;
  }

  String? _extractTreeNameFromPath(String? targetPath) {
    if (targetPath == null || targetPath.trim().isEmpty) {
      return null;
    }
    final normalizedPath =
        targetPath.startsWith('#') ? targetPath.substring(1) : targetPath;
    final uri = Uri.tryParse(normalizedPath);
    final treeName = uri?.queryParameters['name']?.trim();
    if (treeName == null || treeName.isEmpty) {
      return null;
    }
    return treeName;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp.router(
      scaffoldMessengerKey: scaffoldMessengerKey,
      routerConfig: _appRouter.router,
      title: 'Родня',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [const Locale('ru', 'RU'), const Locale('en', 'US')],
      locale: const Locale('ru', 'RU'),
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (!GetIt.I.isRegistered<CallCoordinatorService>()) {
          return content;
        }
        return CallRuntimeHost(child: content);
      },
    );
  }
}

class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({
    required this.error,
    required this.stackTrace,
    required this.onRetry,
    required this.canResetSession,
    this.onResetSessionAndRetry,
  });

  final Object error;
  final StackTrace stackTrace;
  final Future<void> Function() onRetry;
  final bool canResetSession;
  final Future<void> Function()? onResetSessionAndRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: StartupFailureView(
                  title: 'Не удалось открыть Родню',
                  message: startupFailureMessageFor(
                    error,
                    canResetSession: canResetSession,
                  ),
                  onRetry: onRetry,
                  onResetSessionAndRetry: onResetSessionAndRetry,
                  showTechnicalDetails: kDebugMode,
                  technicalDetails: [
                    error.toString(),
                    '',
                    stackTrace.toString(),
                  ].join('\n'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
