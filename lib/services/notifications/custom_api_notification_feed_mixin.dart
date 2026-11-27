part of '../custom_api_notification_service.dart';

mixin _CustomApiNotificationFeedMixin on _CustomApiNotificationBase {
  @override
  Future<int> refreshUnreadNotificationsCount() async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      _updateUnreadNotificationsCount(0);
      return 0;
    }

    final token = authService.accessToken;
    if (token == null || token.isEmpty) {
      _updateUnreadNotificationsCount(0);
      return 0;
    }

    try {
      StartupTrace.logRequest('GET', '/v1/notifications/unread-count');
      final response = await _httpClient.get(
        _buildUri(runtimeConfig, '/v1/notifications/unread-count'),
        headers: _headers(token),
      );
      final payload = _decodeResponse(response);
      final totalUnread = _coerceUnreadCount(payload['totalUnread']);
      _updateUnreadNotificationsCount(totalUnread);
      return totalUnread;
    } on CustomApiException catch (error) {
      if (await _handleUnauthorizedError(error)) {
        _updateUnreadNotificationsCount(0);
        return 0;
      }
      rethrow;
    }
  }

  /// Страница ленты активности (все статусы): keyset-курсор бэкенда.
  /// [cursor] null — первая страница; nextCursor null — лента кончилась.
  Future<NotificationsPageResult> fetchNotificationsPage({
    String? status,
    String? cursor,
    int limit = 30,
  }) async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return const NotificationsPageResult(
        items: <AppNotificationItem>[],
        nextCursor: null,
      );
    }
    final token = authService.accessToken;
    if (token == null || token.isEmpty) {
      return const NotificationsPageResult(
        items: <AppNotificationItem>[],
        nextCursor: null,
      );
    }

    final query = StringBuffer('/v1/notifications?limit=$limit'
        '&cursor=${Uri.encodeQueryComponent(cursor ?? '')}');
    if (status != null && status.isNotEmpty) {
      query.write('&status=${Uri.encodeQueryComponent(status)}');
    }
    late final Map<String, dynamic> payload;
    try {
      final response = await _httpClient.get(
        _buildUri(runtimeConfig, query.toString()),
        headers: _headers(token),
      );
      payload = _decodeResponse(response);
    } on CustomApiException catch (error) {
      // Протухшая сессия гасится единым путём (как fetchUnread) — иначе
      // подгрузчик истории молча объявлял бы ленту исчерпанной.
      if (await _handleUnauthorizedError(error)) {
        return const NotificationsPageResult(
          items: <AppNotificationItem>[],
          nextCursor: null,
        );
      }
      rethrow;
    }
    final rawNotifications = payload['notifications'];
    final items = rawNotifications is List<dynamic>
        ? rawNotifications
            .whereType<Map<String, dynamic>>()
            .map(AppNotificationItem.fromBackendJson)
            .toList(growable: false)
        : const <AppNotificationItem>[];
    return NotificationsPageResult(
      items: items,
      nextCursor: payload['nextCursor']?.toString(),
    );
  }

  /// «Прочитать всё» одним запросом. Бэкенд без роута (домиграционный,
  /// маловероятно) отвечает 404 — тогда честный фолбэк на поштучный цикл
  /// по [fallbackIds]. Возвращает сколько помечено.
  Future<int> markAllNotificationsRead({
    List<String> fallbackIds = const <String>[],
  }) async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return 0;
    }
    final token = authService.accessToken;
    if (token == null || token.isEmpty) {
      return 0;
    }
    try {
      final response = await _httpClient.post(
        _buildUri(runtimeConfig, '/v1/notifications/read-all'),
        headers: _headers(token),
      );
      final payload = _decodeResponse(response);
      _updateUnreadNotificationsCount(0);
      final marked = payload['marked'];
      return marked is num ? marked.toInt() : 0;
    } on CustomApiException catch (error) {
      if (error.statusCode == 404 && fallbackIds.isNotEmpty) {
        await markNotificationsRead(fallbackIds);
        _updateUnreadNotificationsCount(0);
        return fallbackIds.length;
      }
      if (await _handleUnauthorizedError(error)) {
        return 0;
      }
      rethrow;
    }
  }

  Future<List<AppNotificationItem>> fetchUnreadNotifications({
    int limit = 50,
  }) async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return const <AppNotificationItem>[];
    }

    final token = authService.accessToken;
    if (token == null || token.isEmpty) {
      return const <AppNotificationItem>[];
    }

    try {
      final response = await _httpClient.get(
        _buildUri(
            runtimeConfig, '/v1/notifications?status=unread&limit=$limit'),
        headers: _headers(token),
      );
      final payload = _decodeResponse(response);
      final rawNotifications = payload['notifications'];
      if (rawNotifications is! List<dynamic>) {
        _updateUnreadNotificationsCount(0);
        return const <AppNotificationItem>[];
      }

      final notifications = rawNotifications
          .whereType<Map<String, dynamic>>()
          .map(AppNotificationItem.fromBackendJson)
          .toList()
        ..sort((left, right) {
          final leftCreatedAt =
              left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final rightCreatedAt =
              right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return rightCreatedAt.compareTo(leftCreatedAt);
        });
      _updateUnreadNotificationsCount(notifications.length);
      return notifications;
    } on CustomApiException catch (error) {
      if (await _handleUnauthorizedError(error)) {
        _updateUnreadNotificationsCount(0);
        return const <AppNotificationItem>[];
      }
      rethrow;
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return;
    }

    final normalizedId = notificationId.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final token = authService.accessToken;
    if (token == null || token.isEmpty) {
      return;
    }

    try {
      final response = await _httpClient.post(
        _buildUri(runtimeConfig, '/v1/notifications/$normalizedId/read'),
        headers: _headers(token),
      );
      _decodeResponse(response);
      _updateUnreadNotificationsCount(_unreadNotificationsCount - 1);
    } on CustomApiException catch (error) {
      if (await _handleUnauthorizedError(error)) {
        _updateUnreadNotificationsCount(0);
        return;
      }
      rethrow;
    }
  }

  Future<void> markNotificationsRead(Iterable<String> notificationIds) async {
    final ids = notificationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) {
      return;
    }

    for (final id in ids) {
      await markNotificationRead(id);
    }
  }

  void openNotificationPayload(String payload) {
    if (payload.isEmpty) {
      return;
    }
    _schedulePayloadNavigation(payload);
  }

  Future<void> _handleRealtimeNotification(
    Map<String, dynamic> notification,
  ) async {
    final id = notification['id']?.toString() ?? '';
    if (id.isEmpty || _deliveredNotificationIds.contains(id)) {
      return;
    }

    await _showBackendNotification(notification);
    _deliveredNotificationIds.add(id);
    _updateUnreadNotificationsCount(_unreadNotificationsCount + 1);
    await _persistDeliveredNotificationIds();
  }

  @override
  void _updateUnreadNotificationsCount(int count) {
    final normalizedCount = count < 0 ? 0 : count;
    if (_unreadNotificationsCount == normalizedCount) {
      return;
    }
    _unreadNotificationsCount = normalizedCount;
    if (!_unreadNotificationsCountController.isClosed) {
      _unreadNotificationsCountController.add(normalizedCount);
    }
  }

  int _coerceUnreadCount(dynamic rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    return int.tryParse(rawValue?.toString() ?? '') ?? 0;
  }

  @override
  Future<void> _restoreLaunchNotificationPayload() async {
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final payload = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.isNotEmpty) {
      _schedulePayloadNavigation(payload);
    }
  }

  @override
  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }
    _schedulePayloadNavigation(payload);
  }

  @override
  void _schedulePayloadNavigation(String payload, {int attempt = 0}) {
    final authService = _authService;
    if (authService != null && (authService.currentUserId ?? '').isEmpty) {
      _pendingNavigationPayload = payload;
      return;
    }

    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null) {
      _pendingNavigationPayload = payload;
      if (attempt >= 12) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          _schedulePayloadNavigation(payload, attempt: attempt + 1);
        });
      });
      return;
    }

    _pendingNavigationPayload = null;
    unawaited(_handlePayloadNavigation(payload, navigatorContext));
  }

  Future<void> _handlePayloadNavigation(
    String payload,
    BuildContext navigatorContext,
  ) async {
    final rootPayload = _tryDecodePayload(payload);
    final type = rootPayload['type']?.toString() ?? '';
    final data = _asStringDynamicMap(rootPayload['data']);
    final router = GoRouter.of(navigatorContext);

    if (type == 'chat' || type == 'chat_message') {
      final chatId =
          rootPayload['chatId']?.toString() ?? data['chatId']?.toString() ?? '';
      final chatType = rootPayload['chatType']?.toString() ??
          data['chatType']?.toString() ??
          'direct';
      final chatTitle = rootPayload['chatTitle']?.toString() ??
          data['chatTitle']?.toString() ??
          '';
      final senderId =
          rootPayload['senderId']?.toString() ?? data['senderId']?.toString();
      final senderName = rootPayload['senderName']?.toString() ??
          data['senderName']?.toString() ??
          'Пользователь';
      final encodedTitle =
          Uri.encodeComponent(chatTitle.isNotEmpty ? chatTitle : senderName);

      if (chatId.isNotEmpty) {
        final userQuery =
            senderId != null && senderId.isNotEmpty ? '&userId=$senderId' : '';
        _navigateOverHome(
          router,
          '/chats/view/$chatId?type=$chatType&title=$encodedTitle$userQuery',
        );
        return;
      }

      if (senderId == null || senderId.isEmpty) {
        return;
      }

      final relativeId = await _resolveRelativeIdForUser(senderId);
      if (relativeId == null || relativeId.isEmpty) {
        _navigateOverHome(router, '/user/$senderId');
        return;
      }

      final encodedName = Uri.encodeComponent(senderName);
      _navigateOverHome(
        router,
        '/chat/$senderId?relativeId=$relativeId&name=$encodedName',
      );
      return;
    }

    if (type == 'call' || type == 'call_invite') {
      if (!GetIt.I.isRegistered<CallCoordinatorService>()) {
        return;
      }
      final callCoordinator = GetIt.I<CallCoordinatorService>();
      final callId =
          rootPayload['callId']?.toString() ?? data['callId']?.toString() ?? '';
      await callCoordinator.ensureRuntimeReady();
      final call = await callCoordinator.hydrateIncomingCall(
        callId: callId,
        chatId: data['chatId']?.toString(),
      );
      if (call != null && !call.state.isTerminal) {
        await callCoordinator.activateCall(call);
      }
      return;
    }

    if (type == 'birthday') {
      final personId =
          rootPayload['personId']?.toString() ?? data['personId']?.toString();
      // P0: если пуш несёт treeId — прокидываем, чтобы карточка открылась
      // сразу в правильном дереве; без него экран резолвит сам.
      final treeId =
          rootPayload['treeId']?.toString() ?? data['treeId']?.toString();
      if (personId != null && personId.isNotEmpty) {
        _navigateOverHome(
          router,
          relativeDetailsRoute(personId, treeId: treeId),
        );
      }
      return;
    }

    if (type == 'relation_request') {
      final treeId =
          rootPayload['treeId']?.toString() ?? data['treeId']?.toString();
      if (treeId != null && treeId.isNotEmpty) {
        _navigateOverHome(router, '/relatives/requests/$treeId');
      }
      return;
    }

    if (type == 'tree_invitation') {
      _navigateOverHome(router, '/trees?tab=invitations');
      return;
    }

    if (type == 'semya_invitation_received') {
      final token =
          (rootPayload['token']?.toString() ?? data['token']?.toString() ?? '')
              .trim();
      if (token.isNotEmpty) {
        _navigateOverHome(router, '/invite/${Uri.encodeComponent(token)}');
      } else {
        _navigateOverHome(router, '/trees?tab=invitations');
      }
      return;
    }

    if (type == 'semya_invitation_accepted') {
      final treeId = (rootPayload['treeId']?.toString() ??
              data['treeId']?.toString() ??
              '')
          .trim();
      if (treeId.isNotEmpty) {
        _navigateOverHome(router, '/tree/view/$treeId');
      } else {
        _navigateOverHome(router, '/trees');
      }
      return;
    }

    if (type == 'merge_proposal' || type == 'identity_claim') {
      _navigateOverHome(router, '/identity/review');
      return;
    }

    if (type == 'tree_update') {
      final treeId =
          rootPayload['treeId']?.toString() ?? data['treeId']?.toString();
      if (treeId != null && treeId.isNotEmpty) {
        _navigateOverHome(router, '/tree/view/$treeId');
      }
      return;
    }

    // Phase 6 chunk 4b (PHASE-6-PROPOSAL.md §2.6): kinship-check
    // «мы родственники?» bilateral consent flow. Three types map к
    // different views на discover screen:
    //   • received → action sheet (target подтверждает либо
    //     отклоняет; ?incoming=<id> auto-opens sheet).
    //   • confirmed → result step (initiator видит chain;
    //     ?result=<id> deep-links к result view).
    //   • declined / expired → discover entry default (status
    //     visible в «Ваши запросы» history).
    if (type == 'kinship_check_received') {
      final checkId = rootPayload['kinshipCheckId']?.toString() ??
          data['kinshipCheckId']?.toString();
      final query = checkId != null && checkId.isNotEmpty
          ? '?incoming=${Uri.encodeQueryComponent(checkId)}'
          : '';
      _navigateOverHome(router, '/discover/relatives$query');
      return;
    }
    if (type == 'kinship_check_confirmed') {
      final checkId = rootPayload['kinshipCheckId']?.toString() ??
          data['kinshipCheckId']?.toString();
      final query = checkId != null && checkId.isNotEmpty
          ? '?result=${Uri.encodeQueryComponent(checkId)}'
          : '';
      _navigateOverHome(router, '/discover/relatives$query');
      return;
    }
    if (type == 'kinship_check_declined' || type == 'kinship_check_expired') {
      _navigateOverHome(router, '/discover/relatives');
      return;
    }

    // MVP-1 «Спросить историю» (STORY-REQUEST-MVP1-BRIEF.md §1 route
    // table + §3.5): received → the voice-first answer screen (needs
    // just requestId); answered/declined/expired → back to the hero's
    // page, where the answer (or the initiator's status line) lives.
    // `revoked` carries only `requestId` per contract (no treeId/
    // personId) — there's nowhere useful to deep-link the addressee to,
    // so it deliberately falls through to the generic treeId tail below
    // (a no-op, since that payload has no treeId either) rather than
    // guessing a destination.
    if (type == 'story_request_received') {
      final requestId = rootPayload['requestId']?.toString() ??
          data['requestId']?.toString() ??
          '';
      if (requestId.isNotEmpty) {
        _navigateOverHome(router, '/story-requests/$requestId/answer');
      }
      return;
    }
    if (type == 'story_request_answered' ||
        type == 'story_request_declined' ||
        type == 'story_request_expired') {
      final personId =
          rootPayload['personId']?.toString() ?? data['personId']?.toString();
      final treeId =
          rootPayload['treeId']?.toString() ?? data['treeId']?.toString();
      if (personId != null && personId.isNotEmpty) {
        _navigateOverHome(
          router,
          relativeDetailsRoute(personId, treeId: treeId),
        );
      }
      return;
    }

    // Post-creation fan-out notifications + reactions / comment
    // replies all live on the home feed (audience-mode shows
    // every post the viewer is the audience for, regardless of
    // selected branch). No standalone post-detail screen exists,
    // so we land the user on home and let the post show at the
    // top — the freshly-published one is by construction the
    // most recent. Worth replacing with a real `/post/:postId`
    // screen + scroll-to-post when single-post permalinks become
    // a thing, but for now this is the most useful fallback.
    if (type == 'post_created' ||
        type == 'post_reaction' ||
        type == 'comment_reaction' ||
        type == 'comment_reply') {
      final postId =
          rootPayload['postId']?.toString() ?? data['postId']?.toString();
      if (postId != null && postId.isNotEmpty) {
        _navigateOverHome(router, '/post/$postId');
      } else {
        router.go('/');
      }
      return;
    }

    final treeId =
        rootPayload['treeId']?.toString() ?? data['treeId']?.toString();
    if (treeId != null && treeId.isNotEmpty) {
      _navigateOverHome(router, '/tree/view/$treeId');
    }
  }

  /// Navigate to a deep-link target while preserving a sane
  /// back-stack: home → target. Pop/swipe-back from the target
  /// returns the user to the feed instead of stranding them.
  ///
  /// User-reported: «нажимаю на уведомление о сообщении, перехожу
  /// в чат и из этого чата я никуда не могу выйти». Корень: payload
  /// navigation использовал `router.go(...)`, а GoRouter.go REPLACES
  /// весь стек — на target экране Navigator.canPop() = false, кнопка
  /// «назад» исчезает / не работает.
  ///
  /// `pushReplacement('/')` сначала ставит home как корень, затем
  /// `push(location)` кладёт target поверх. Стэк [home, target] —
  /// pop возвращает в home shell с нижней навигацией.
  ///
  /// Для cold-start (приложение запущено через тап push'а из killed
  /// state) initial location уже на '/', так что pushReplacement
  /// безопасен. Для warm-start (юзер был в app и тапнул по
  /// уведомлению в шторке) поведение тоже консистентно: текущая
  /// branch заменяется на home, далее target кладётся поверх.
  /// Идеальный «вернуться к экрану ДО клика» требовал бы хранить
  /// стек до payload navigation — это уже мульти-уровневый Navigator
  /// rework, оставляем под отдельную задачу.
  void _navigateOverHome(GoRouter router, String location) {
    // Если уже на target — ничего не делаем (повторный тап по тому же
    // уведомлению).
    final currentUri =
        router.routerDelegate.currentConfiguration.uri.toString();
    if (currentUri == location) {
      return;
    }
    final isAtRoot = currentUri == '/' || currentUri.startsWith('/?');
    if (isAtRoot) {
      // Уже на корне — просто push поверх.
      router.push(location);
      return;
    }
    // Сбрасываем стек до '/' через replace, потом кладём target
    // поверх в следующем кадре чтобы GoRouter успел обработать
    // первый переход.
    router.go('/');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.push(location);
    });
  }

  Future<String?> _resolveRelativeIdForUser(String userId) async {
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) {
      return null;
    }

    final familyTreeService = GetIt.I<FamilyTreeServiceInterface>();
    final treeProvider =
        GetIt.I.isRegistered<TreeProvider>() ? GetIt.I<TreeProvider>() : null;

    final candidateTreeIds = <String>[];
    final selectedTreeId = treeProvider?.selectedTreeId;
    if (selectedTreeId != null && selectedTreeId.isNotEmpty) {
      candidateTreeIds.add(selectedTreeId);
    }

    try {
      final userTrees = await familyTreeService.getUserTrees();
      for (final tree in userTrees) {
        if (!candidateTreeIds.contains(tree.id)) {
          candidateTreeIds.add(tree.id);
        }
      }
    } catch (_) {
      // Если список деревьев не загрузился, пробуем хотя бы выбранное.
    }

    for (final treeId in candidateTreeIds) {
      try {
        final relatives = await familyTreeService.getRelatives(treeId);
        for (final person in relatives) {
          if (person.userId == userId) {
            return person.id;
          }
        }
      } catch (_) {
        // Переходим к следующему дереву.
      }
    }

    return null;
  }

  @override
  Future<void> _handleRealtimeNotificationSafely(
    Map<String, dynamic> notification,
  ) async {
    try {
      await _handleRealtimeNotification(notification);
    } catch (error, stackTrace) {
      debugPrint('Custom API realtime notification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
