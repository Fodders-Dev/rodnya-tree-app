import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/graph_person_access_capable_family_tree_service.dart';
import '../widgets/access_grants_incoming_tab.dart';
import '../widgets/access_grants_outgoing_tab.dart';

/// Phase 3.4 chunk 3 (PHASE-3.4-UI-PROPOSAL.md §2.3): экран
/// «Доступы» — единая точка для viewer'а посмотреть/отозвать
/// права на edit/merge/soft-delete по graphPerson'ам.
///
/// Два таба:
///   • outgoing («Кому я разрешил») — grants, выписанные текущим
///     юзером. Группировка по graphPersonId; tap row → revoke
///     с confirm-dialog'ом.
///   • incoming («Что мне разрешено») — grants, выписанные мне на
///     чужие graphPerson'ы. Informational, без revoke (отзывает
///     только grantor).
///
/// Backend не hydrate'ит grantor preview через
/// `/v1/me/edit-grants` (см. edit_grant.dart комментарий) — incoming
/// показывает «эта карточка» + список scopes без имени того кто
/// разрешил. Это deliberate: сама идея edit-grant в том что viewer
/// может редактировать, *кто именно разрешил* — собственник может
/// быть любой из claim chain'а.
///
/// Скрываем экран целиком если backend service не implements
/// [GraphPersonAccessCapableFamilyTreeService] (старый сервер без
/// Phase 3.2/3.4-prep) — empty-state с пояснением.
class AccessGrantsScreen extends StatelessWidget {
  const AccessGrantsScreen({
    super.key,
    this.familyTreeService,
    this.authService,
  });

  /// Override для тестов; production читает из `GetIt`.
  final FamilyTreeServiceInterface? familyTreeService;

  /// Override для тестов; production читает из `GetIt`.
  final AuthServiceInterface? authService;

  @override
  Widget build(BuildContext context) {
    final service = familyTreeService ?? GetIt.I<FamilyTreeServiceInterface>();
    final auth = authService ?? GetIt.I<AuthServiceInterface>();
    final viewerUserId = auth.currentUserId;

    final accessService = service is GraphPersonAccessCapableFamilyTreeService
        ? service as GraphPersonAccessCapableFamilyTreeService
        : null;

    if (accessService == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Доступы')),
        body: const _UnsupportedState(),
      );
    }

    if (viewerUserId == null || viewerUserId.isEmpty) {
      // Не авторизован — guards должны были redirect'нуть, но
      // защищаемся defensive'но.
      return Scaffold(
        appBar: AppBar(title: const Text('Доступы')),
        body: const _SignInRequiredState(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Доступы'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Кому я разрешил'),
              Tab(text: 'Что мне разрешено'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            AccessGrantsOutgoingTab(
              accessService: accessService,
              viewerUserId: viewerUserId,
            ),
            AccessGrantsIncomingTab(
              accessService: accessService,
              viewerUserId: viewerUserId,
            ),
          ],
        ),
      ),
    );
  }
}

class _UnsupportedState extends StatelessWidget {
  const _UnsupportedState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Управление доступами недоступно',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Обновите приложение или дождитесь обновления сервера, '
              'чтобы видеть выданные и полученные права на карточки.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _SignInRequiredState extends StatelessWidget {
  const _SignInRequiredState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          'Войдите, чтобы посмотреть доступы',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
