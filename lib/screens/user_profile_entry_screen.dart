// Public-facing profile view (`/u/<userId>` and similar deep links).
//
// Renders someone else's profile with the same Profile Redesign hero
// card as the self-profile screen — warm avatar to flag «not me», a
// kinship rel-badge when there's a tree match, and pill actions for
// «Написать» / «Карточка в дереве». Hidden sections (when the
// viewing user lacks permission) collapse to an unobtrusive notice
// instead of half-empty rows.

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
import '../theme/app_theme.dart';
import '../utils/relative_details_route.dart';
import '../widgets/profile_redesign.dart';

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
    final tokens = Theme.of(context).extension<RodnyaDesignTokens>() ??
        RodnyaDesignTokens.light;
    return Scaffold(
      backgroundColor: tokens.bgBase,
      appBar: AppBar(
        backgroundColor: tokens.bgBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _isCurrentUser ? 'Мой профиль' : 'Профиль',
          style: AppTheme.serif(
            color: tokens.ink,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.22,
          ),
        ),
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
    final fullName = profile.fullName.isNotEmpty
        ? profile.fullName
        : profile.displayName;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileHeroCard(
                fullName: fullName,
                firstName: profile.firstName.trim().isEmpty
                    ? null
                    : profile.firstName.trim(),
                lastName: profile.lastName.trim().isEmpty
                    ? null
                    : profile.lastName.trim(),
                patronymic: profile.middleName.trim().isEmpty
                    ? null
                    : profile.middleName.trim(),
                photoUrl: profile.photoURL,
                coverPhotoUrl: profile.coverPhotoURL,
                location: _composeLocation(profile),
                bio: profile.bio.trim().isEmpty ? null : profile.bio.trim(),
                relBadge: _matchingTree != null
                    ? 'В дереве «${_matchingTree!.name}»'
                    : null,
                useWarmAvatar: !_isCurrentUser,
                actions: [
                  if (_isCurrentUser)
                    PillButton(
                      label: 'Открыть мой профиль',
                      icon: Icons.person_outline,
                      onPressed: () => context.go('/profile'),
                    )
                  else if (_relativeId != null)
                    PillButton(
                      label: 'Написать',
                      icon: Icons.message_outlined,
                      onPressed: _openChat,
                    ),
                  if (_relativeId != null)
                    PillButton(
                      label: 'Карточка в дереве',
                      icon: Icons.badge_outlined,
                      variant: PillButtonVariant.outlined,
                      onPressed: () => context.push(
                        relativeDetailsRoute(
                          _relativeId!,
                          treeId: _matchingTree?.id,
                        ),
                      ),
                    ),
                ],
              ),
              if (hiddenSections.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _InfoBanner(
                    icon: Icons.visibility_off_outlined,
                    text:
                        'Часть профиля скрыта настройками видимости этого пользователя.',
                  ),
                ),
              if (_userFactsHaveContent(dossier, profile))
                _buildUserFactsSection(dossier, profile),
              if ((dossier.familySummary.trim().isNotEmpty ||
                  dossier.aboutFamily.trim().isNotEmpty))
                _buildUserFamilySection(dossier),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRelativeFallback(FamilyPerson person) {
    final dossier = PersonDossier.fromPerson(person);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileHeroCard(
                fullName: dossier.displayName,
                photoUrl: dossier.photoUrl,
                bio: (person.bio?.trim().isNotEmpty == true)
                    ? person.bio!.trim()
                    : null,
                relBadge: _matchingTree != null
                    ? 'В дереве «${_matchingTree!.name}»'
                    : null,
                useWarmAvatar: true,
                deceased: !person.isAlive || person.deathDate != null,
                deceasedYears: _composeYears(person),
                actions: [
                  if (!_isCurrentUser && _relativeId != null)
                    PillButton(
                      label: 'Написать',
                      icon: Icons.message_outlined,
                      onPressed: _openChat,
                    ),
                  if (_relativeId != null)
                    PillButton(
                      label: 'Карточка в дереве',
                      icon: Icons.badge_outlined,
                      variant: PillButtonVariant.outlined,
                      onPressed: () => context.push(
                        relativeDetailsRoute(
                          _relativeId!,
                          treeId: _matchingTree?.id,
                        ),
                      ),
                    ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: _InfoBanner(
                  icon: Icons.info_outline,
                  text:
                      'Профиль в приложении ещё не заполнен. Открыта карточка человека из дерева.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _composeLocation(UserProfile profile) {
    final city = profile.city?.trim() ?? '';
    final country = profile.country?.trim() ?? '';
    if (city.isEmpty && country.isEmpty) return null;
    if (city.isEmpty) return country;
    if (country.isEmpty) return city;
    return '$city · $country';
  }

  String? _composeYears(FamilyPerson person) {
    final birth = person.birthDate?.year;
    final death = person.deathDate?.year;
    if (birth == null && death == null) return null;
    if (birth != null && death != null) return '$birth — $death';
    if (birth != null) return '$birth г.';
    return '— $death';
  }

  bool _userFactsHaveContent(PersonDossier d, UserProfile p) {
    return p.birthDate != null ||
        d.hometown.trim().isNotEmpty ||
        d.education.trim().isNotEmpty ||
        d.work.trim().isNotEmpty ||
        d.languages.trim().isNotEmpty ||
        d.interests.trim().isNotEmpty ||
        d.religion.trim().isNotEmpty;
  }

  Widget _buildUserFactsSection(PersonDossier d, UserProfile p) {
    final rows = <Widget>[];
    if (p.birthDate != null) {
      rows.add(InfoRow(
        icon: Icons.cake_outlined,
        label: 'Дата рождения',
        value: _formatRussianDate(p.birthDate!),
        isFirst: rows.isEmpty,
      ));
    }
    if (d.hometown.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.account_tree_outlined,
        label: 'Родом из',
        value: d.hometown.trim(),
        isFirst: rows.isEmpty,
      ));
    }
    if (d.education.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.school_outlined,
        label: 'Образование',
        value: d.education.trim(),
        isFirst: rows.isEmpty,
      ));
    }
    if (d.work.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.work_outline_rounded,
        label: 'Работа',
        value: d.work.trim(),
        isFirst: rows.isEmpty,
      ));
    }
    if (d.languages.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.language_outlined,
        label: 'Языки',
        value: d.languages.trim(),
        isFirst: rows.isEmpty,
      ));
    }
    if (d.interests.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.auto_awesome_outlined,
        label: 'Интересы',
        value: d.interests.trim(),
        isFirst: rows.isEmpty,
      ));
    }
    if (d.religion.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.book_outlined,
        label: 'Мировоззрение',
        value: d.religion.trim(),
        isFirst: rows.isEmpty,
      ));
    }
    if (rows.isNotEmpty) {
      final last = rows.removeLast() as InfoRow;
      rows.add(InfoRow(
        icon: last.icon,
        label: last.label,
        value: last.value,
        isFirst: last.isFirst,
        isLast: true,
      ));
    }
    return ProfileSection(title: 'О человеке', children: rows);
  }

  Widget _buildUserFamilySection(PersonDossier d) {
    final rows = <Widget>[];
    if (d.familySummary.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.notes_outlined,
        label: 'Семейная справка',
        value: d.familySummary.trim(),
        warm: true,
        isFirst: rows.isEmpty,
      ));
    }
    if (d.aboutFamily.trim().isNotEmpty) {
      rows.add(InfoRow(
        icon: Icons.family_restroom_outlined,
        label: 'О семье',
        value: d.aboutFamily.trim(),
        warm: true,
        isFirst: rows.isEmpty,
      ));
    }
    if (rows.isNotEmpty) {
      final last = rows.removeLast() as InfoRow;
      rows.add(InfoRow(
        icon: last.icon,
        label: last.label,
        value: last.value,
        warm: last.warm,
        isFirst: last.isFirst,
        isLast: true,
      ));
    }
    return ProfileSection(title: 'Семья', children: rows);
  }

  String _formatRussianDate(DateTime d) {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
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
    final tokens = Theme.of(context).extension<RodnyaDesignTokens>() ??
        RodnyaDesignTokens.light;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: tokens.surfaceStrong,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: tokens.surfaceLine),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 56, color: tokens.accent),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTheme.serif(
                    color: tokens.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTheme.sans(
                    color: tokens.inkMuted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    height: 1.5,
                  ),
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
    final tokens = Theme.of(context).extension<RodnyaDesignTokens>() ??
        RodnyaDesignTokens.light;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.bgTintWarm,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.surfaceLine),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tokens.warm),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTheme.sans(
                color: tokens.ink,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                height: 1.4,
              ),
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
