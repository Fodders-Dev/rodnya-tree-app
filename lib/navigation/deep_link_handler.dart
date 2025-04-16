import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';

class DeepLinkHandler {
  final GoRouter router;
  final BuildContext? context;
  
  DeepLinkHandler({required this.router, this.context});
  
  /// Инициализация обработчика динамических ссылок
  Future<void> initDynamicLinks() async {
    // Обработка ссылки, если приложение уже запущено
    FirebaseDynamicLinks.instance.onLink.listen((dynamicLinkData) {
      _handleDeepLink(dynamicLinkData.link);
    }).onError((error) {
      debugPrint('Ошибка обработки динамической ссылки: $error');
    });

    // Проверка, было ли приложение открыто по динамической ссылке
    final PendingDynamicLinkData? data = 
        await FirebaseDynamicLinks.instance.getInitialLink();
    
    if (data != null) {
      _handleDeepLink(data.link);
    }
  }
  
  /// Обработка deeplink
  void _handleDeepLink(Uri link) {
    debugPrint('DeepLinkHandler: Получена deeplink: ${link.toString()}');
    
    // --- NEW: Проверяем, является ли это нашей ссылкой-приглашением --- 
    // Мы обрабатываем ее в main.dart для сохранения данных,
    // здесь навигация по ней не нужна.
    if (link.path == '/invite') {
       debugPrint('DeepLinkHandler: Игнорируем /invite, обработано в main.dart');
       return; // Просто выходим, ничего не делаем
    }
    // --- END NEW ---
    
    final queryParams = link.queryParameters;
    final pathSegments = link.pathSegments;
    
    if (pathSegments.isEmpty) return;
    
    // Распознаем различные типы deeplink и направляем пользователя
    switch (pathSegments[0]) {
      case 'tree':
        if (pathSegments.length > 1) {
          final treeId = pathSegments[1];
          final treeName = queryParams['name'] ?? 'Семейное дерево';
          _navigateToTreeView(treeId, treeName);
        }
        break;
        
      case 'profile':
        if (pathSegments.length > 1) {
          final userId = pathSegments[1];
          _navigateToUserProfile(userId);
        }
        break;
        
      case 'post':
        if (pathSegments.length > 1) {
          final postId = pathSegments[1];
          _navigateToPost(postId);
        }
        break;
        
      case 'invite':
        if (pathSegments.length > 1) {
          final treeId = pathSegments[1];
          _handleTreeInvite(treeId, queryParams);
        }
        break;
        
      default:
        // Неизвестный тип ссылки - направляем на главную
        _navigateToHome();
        break;
    }
  }
  
  // Методы для навигации к различным экранам
  
  void _navigateToTreeView(String treeId, String treeName) {
    debugPrint('Навигация к дереву: $treeId, $treeName');
    router.go('/tree/view/$treeId?name=$treeName');
  }
  
  void _navigateToUserProfile(String userId) {
    // Предположим, что у вас есть маршрут для просмотра профиля другого пользователя
    debugPrint('Навигация к профилю: $userId');
    router.go('/user/$userId');
  }
  
  void _navigateToPost(String postId) {
    debugPrint('Навигация к посту: $postId');
    router.go('/post/view/$postId');
  }
  
  void _handleTreeInvite(String treeId, Map<String, String> params) {
    final inviteType = params['type'] ?? 'member';
    final inviterId = params['from'] ?? '';
    
    debugPrint('Обработка приглашения к дереву: $treeId, тип: $inviteType');
    
    // Здесь вы можете показать диалог принятия приглашения
    // или перенаправить на специальный экран принятия приглашения
    router.go('/invite/tree/$treeId?type=$inviteType&from=$inviterId');
  }
  
  void _navigateToHome() {
    debugPrint('Навигация на главную страницу');
    router.go('/');
  }
  
  /// Создание динамической ссылки для приглашения в дерево
  Future<String> createTreeInviteLink(String treeId, String treeName) async {
    final DynamicLinkParameters parameters = DynamicLinkParameters(
      uriPrefix: 'https://lineage.page.link',
      link: Uri.parse('https://lineage.app/invite/$treeId?name=$treeName'),
      androidParameters: const AndroidParameters(
        packageName: 'com.example.lineage',
        minimumVersion: 0,
      ),
      iosParameters: const IOSParameters(
        bundleId: 'com.example.lineage',
        minimumVersion: '0',
      ),
      socialMetaTagParameters: SocialMetaTagParameters(
        title: 'Приглашение в семейное дерево',
        description: 'Вас приглашают присоединиться к дереву "$treeName"',
      ),
    );

    final link = await FirebaseDynamicLinks.instance.buildShortLink(parameters);
    return link.shortUrl.toString();
  }
} 