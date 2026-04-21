import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../models/family_person.dart';
import '../models/family_tree.dart';
import '../models/person_dossier.dart';
import '../models/user_profile.dart';
import '../widgets/person_dossier_view.dart';

class UserProfileEntryScreen extends StatefulWidget {
  const UserProfileEntryScreen({
    super.key,
    required this.userId,
  });

  final String userId;

  @override
  State<UserProfileEntryScreen> createState() => _UserProfileEntryScreenState();
}

class _UserProfileEntryScreenState extends State<UserProfileEntryScreen> {
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final ProfileServiceInterface _profileService =
      GetIt.I<ProfileServiceInterface>();
  final FamilyTreeServiceInterface _familyTreeService =
      GetIt.I<FamilyTreeServiceInterface>();
  final ChatServiceInterface _chatService = GetIt.I<ChatServiceInterface>();

  bool _isLoading = true;
  String? _errorMessage;
  UserProfile? _profile;
  String? _relativeId;
  FamilyTree? _matchingTree;
  FamilyPerson? _relativePerson;
  PersonDossier? _dossier;

  bool get _isCurrentUser => _authService.currentUserId == widget.userId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profile = _isCurrentUser
          ? await _profileService.getCurrentUserProfile()
          : await _profileService.getUserProfile(widget.userId);
      final relationContext = await _resolveRelativeContext(widget.userId);
      PersonDossier? dossier;
      if (relationContext.tree != null &&
          relationContext.relativeId != null &&
          relationContext.relativeId!.isNotEmpty) {
        try {
          dossier = await _familyTreeService.getPersonDossier(
            relationContext.tree!.id,
            relationContext.relativeId!,
          );
        } catch (_) {
          dossier = null;
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _relativeId = relationContext.relativeId;
        _matchingTree = relationContext.tree;
        _relativePerson = relationContext.relativePerson;
        _dossier = dossier;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Не удалось загрузить профиль пользователя.';
        _isLoading = false;
      });
    }
  }

  Future<_RelativeContext> _resolveRelativeContext(String userId) async {
    try {
      final trees = await _familyTreeService.getUserTrees();
      for (final tree in trees) {
        final relatives = await _familyTreeService.getRelatives(tree.id);
        for (final person in relatives) {
          if (person.userId == userId) {
            return _RelativeContext(
              relativeId: person.id,
              tree: tree,
              relativePerson: person,
            );
          }
        }
      }
    } catch (_) {
      // Профиль остаётся доступным даже без семейного контекста.
    }
    return const _RelativeContext();
  }

  Future<void> _openChat() async {
    final profile = _profile;
    final relativeId = _relativeId;
    if (profile == null || relativeId == null || relativeId.isEmpty) {
      return;
    }

    final nameParam = Uri.encodeComponent(
      profile.displayName.isNotEmpty ? profile.displayName : profile.fullName,
    );
    final photoParam =
        profile.photoURL != null ? Uri.encodeComponent(profile.photoURL!) : '';

    await _chatService.getOrCreateChat(widget.userId);
    if (!mounted) {
      return;
    }
    context.push(
      '/chat/${widget.userId}?name=$nameParam&photo=$photoParam&relativeId=$relativeId',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isCurrentUser ? 'Мой профиль' : 'Профиль пользователя'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _InfoState(
        icon: Icons.error_outline,
        title: 'Профиль недоступен',
        message: _errorMessage!,
        action: FilledButton.icon(
          onPressed: _loadData,
          icon: const Icon(Icons.refresh),
          label: const Text('Повторить'),
        ),
      );
    }

    final profile = _profile;
    if (profile == null) {
      final relativePerson = _relativePerson;
      if (relativePerson != null) {
        return _buildRelativeFallback(relativePerson);
      }
      return const _InfoState(
        icon: Icons.person_off_outlined,
        title: 'Пользователь не найден',
        message: 'Профиль не удалось найти или он ещё не заполнен.',
      );
    }

    final dossier = _dossier ??
        PersonDossier.fromProfile(
          profile,
          treePerson: _relativePerson,
          isSelf: _isCurrentUser,
        );
    final hiddenSections = dossier.hiddenSections;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: PersonDossierView(
        dossier: dossier,
        headerChips: [
          if (_matchingTree != null)
            _UserMetaChip(
              icon: Icons.account_tree_outlined,
              label: _matchingTree!.name,
              highlighted: true,
            ),
          _UserMetaChip(
            icon: Icons.family_restroom,
            label: _relativeId == null
                ? 'Нет общего дерева'
                : 'Есть в вашем дереве',
          ),
        ],
        actionButtons: [
          if (_isCurrentUser)
            FilledButton.icon(
              onPressed: () => context.go('/profile'),
              icon: const Icon(Icons.person_outline),
              label: const Text('Открыть мой профиль'),
            )
          else if (_relativeId != null)
            FilledButton.icon(
              onPressed: _openChat,
              icon: const Icon(Icons.message_outlined),
              label: const Text('Написать'),
            ),
          if (_relativeId != null)
            OutlinedButton.icon(
              onPressed: () => context.push('/relative/details/$_relativeId'),
              icon: const Icon(Icons.badge_outlined),
              label: const Text('Карточка в дереве'),
            ),
        ],
        banner: hiddenSections.isNotEmpty
            ? const _InfoBanner(
                icon: Icons.visibility_off_outlined,
                text:
                    'Часть профиля скрыта настройками видимости этого пользователя.',
              )
            : null,
      ),
    );
  }

  Widget _buildRelativeFallback(FamilyPerson person) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: PersonDossierView(
        dossier: PersonDossier.fromPerson(person),
        headerChips: [
          if (_matchingTree != null)
            _UserMetaChip(
              icon: Icons.account_tree_outlined,
              label: _matchingTree!.name,
              highlighted: true,
            ),
          const _UserMetaChip(
            icon: Icons.family_restroom,
            label: 'Есть в вашем дереве',
          ),
        ],
        actionButtons: [
          if (!_isCurrentUser && _relativeId != null)
            FilledButton.icon(
              onPressed: _openChat,
              icon: const Icon(Icons.message_outlined),
              label: const Text('Написать'),
            ),
          if (_relativeId != null)
            OutlinedButton.icon(
              onPressed: () => context.push('/relative/details/$_relativeId'),
              icon: const Icon(Icons.badge_outlined),
              label: const Text('Карточка в дереве'),
            ),
        ],
        banner: const _InfoBanner(
          icon: Icons.info_outline,
          text:
              'Профиль в приложении ещё не заполнен. Открыта карточка человека из дерева.',
        ),
      ),
    );
  }
}

class _InfoState extends StatelessWidget {
  const _InfoState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                ),
                if (action != null) ...[
                  const SizedBox(height: 16),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _UserMetaChip extends StatelessWidget {
  const _UserMetaChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted ? colorScheme.primaryContainer : colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: highlighted
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: highlighted
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelativeContext {
  const _RelativeContext({
    this.relativeId,
    this.tree,
    this.relativePerson,
  });

  final String? relativeId;
  final FamilyTree? tree;
  final FamilyPerson? relativePerson;
}
