import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/graph_person_access_capable_family_tree_service.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/models/edit_grant.dart';
import '../models/family_person.dart';
import '../models/family_tree.dart';
import '../models/user_profile.dart';
import '../providers/tree_provider.dart';
import '../utils/user_facing_error.dart';

/// Opens a bottom sheet letting a card owner inspect active [EditGrant]s on a
/// graph person and grant `edit`, `merge-consent`, or `soft-delete` access to a
/// family member or searched user. Returns `true` if any grant was added or
/// revoked.
Future<bool?> showGrantEditAccessSheet(
  BuildContext context, {
  required GraphPersonAccessCapableFamilyTreeService accessService,
  required String viewerUserId,
  String? initialGraphPersonId,
  String? initialPersonName,
  List<GrantPreviewSubject> initialCardCandidates =
      const <GrantPreviewSubject>[],
  List<GrantPreviewSubject> initialGranteeCandidates =
      const <GrantPreviewSubject>[],
  FamilyTreeServiceInterface? familyTreeService,
  ProfileServiceInterface? profileService,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GrantEditAccessSheet(
      accessService: accessService,
      viewerUserId: viewerUserId,
      initialGraphPersonId: initialGraphPersonId,
      initialPersonName: initialPersonName,
      initialCardCandidates: initialCardCandidates,
      initialGranteeCandidates: initialGranteeCandidates,
      familyTreeService: familyTreeService,
      profileService: profileService,
    ),
  );
}

class _GrantEditAccessSheet extends StatefulWidget {
  const _GrantEditAccessSheet({
    required this.accessService,
    required this.viewerUserId,
    this.initialGraphPersonId,
    this.initialPersonName,
    this.initialCardCandidates = const <GrantPreviewSubject>[],
    this.initialGranteeCandidates = const <GrantPreviewSubject>[],
    this.familyTreeService,
    this.profileService,
  });

  final GraphPersonAccessCapableFamilyTreeService accessService;
  final String viewerUserId;
  final String? initialGraphPersonId;
  final String? initialPersonName;
  final List<GrantPreviewSubject> initialCardCandidates;
  final List<GrantPreviewSubject> initialGranteeCandidates;
  final FamilyTreeServiceInterface? familyTreeService;
  final ProfileServiceInterface? profileService;

  @override
  State<_GrantEditAccessSheet> createState() => _GrantEditAccessSheetState();
}

class _GrantEditAccessSheetState extends State<_GrantEditAccessSheet> {
  final TextEditingController _searchController = TextEditingController();

  List<GrantPreviewSubject> _cardCandidates = const <GrantPreviewSubject>[];
  String? _selectedGraphPersonId;
  String _selectedPersonName = '';

  List<GrantPreviewSubject> _familyCandidates = const <GrantPreviewSubject>[];
  List<GrantPreviewSubject> _searchResults = const <GrantPreviewSubject>[];
  GrantPreviewSubject? _selectedGrantee;

  List<EditGrant> _existingGrants = const <EditGrant>[];
  final Set<EditGrantScope> _selectedScopes = <EditGrantScope>{
    EditGrantScope.edit,
  };
  final Set<String> _revokingGrantIds = <String>{};

  bool _loadingCandidates = false;
  bool _loadingGrants = false;
  bool _searchingUsers = false;
  bool _submitting = false;
  bool _mutated = false;
  String? _error;

  FamilyTreeServiceInterface? get _treeService {
    if (widget.familyTreeService != null) return widget.familyTreeService;
    if (widget.accessService is FamilyTreeServiceInterface) {
      return widget.accessService as FamilyTreeServiceInterface;
    }
    if (GetIt.I.isRegistered<FamilyTreeServiceInterface>()) {
      return GetIt.I<FamilyTreeServiceInterface>();
    }
    return null;
  }

  ProfileServiceInterface? get _profileService {
    if (widget.profileService != null) return widget.profileService;
    if (GetIt.I.isRegistered<ProfileServiceInterface>()) {
      return GetIt.I<ProfileServiceInterface>();
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _cardCandidates = widget.initialCardCandidates;
    _familyCandidates = widget.initialGranteeCandidates
        .where((c) => c.id.isNotEmpty && c.id != widget.viewerUserId)
        .toList(growable: false);
    final initialId = widget.initialGraphPersonId?.trim();
    if (initialId != null && initialId.isNotEmpty) {
      _selectedGraphPersonId = initialId;
      _selectedPersonName = widget.initialPersonName?.trim() ?? '';
    } else if (_cardCandidates.isNotEmpty) {
      _selectedGraphPersonId = _cardCandidates.first.id;
      _selectedPersonName = _cardCandidates.first.displayName;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait(<Future<void>>[
      if (_selectedGraphPersonId == null || _familyCandidates.isEmpty)
        _loadCardsAndMembers(),
      if (_selectedGraphPersonId != null)
        _loadExistingGrants(_selectedGraphPersonId!),
    ]);
  }

  Future<void> _loadCardsAndMembers() async {
    final treeService = _treeService;
    if (treeService == null) return;
    setState(() => _loadingCandidates = true);
    try {
      String? treeId;
      try {
        treeId = context.read<TreeProvider?>()?.selectedTreeId;
      } catch (_) {
        treeId = null;
      }
      if (treeId == null || treeId.isEmpty) {
        final List<FamilyTree> trees = await treeService.getUserTrees();
        if (trees.isNotEmpty) {
          treeId = trees.first.id;
        }
      }
      if (treeId != null && treeId.isNotEmpty) {
        final List<FamilyPerson> relatives =
            await treeService.getRelatives(treeId);
        if (!mounted) return;
        final ownedCards = <GrantPreviewSubject>[];
        final seenCardIds = <String>{};
        final memberMap = <String, GrantPreviewSubject>{
          for (final item in _familyCandidates) item.id: item,
        };
        for (final person in relatives) {
          final gpId = person.identityId?.trim();
          final isOwner = person.userId == widget.viewerUserId ||
              person.userId == null ||
              person.userId!.isEmpty;
          if (gpId != null &&
              gpId.isNotEmpty &&
              isOwner &&
              seenCardIds.add(gpId)) {
            ownedCards.add(
              GrantPreviewSubject(
                id: gpId,
                displayName: person.name.trim().isNotEmpty
                    ? person.name.trim()
                    : 'Карточка без имени',
                photoUrl: person.photoUrl,
              ),
            );
          }
          final uid = person.userId?.trim();
          if (uid != null && uid.isNotEmpty && uid != widget.viewerUserId) {
            memberMap.putIfAbsent(
              uid,
              () => GrantPreviewSubject(
                id: uid,
                displayName: person.name.trim().isNotEmpty
                    ? person.name.trim()
                    : 'Родственник',
                photoUrl: person.photoUrl,
              ),
            );
          }
        }
        if (treeService is SemyaCapableFamilyTreeService) {
          try {
            final semyi = await (treeService as SemyaCapableFamilyTreeService)
                .listMySemya();
            final targetSemya = semyi.where((s) => s.treeId == treeId);
            for (final semya in targetSemya) {
              final memberships =
                  await (treeService as SemyaCapableFamilyTreeService)
                      .listMembershipsForSemya(semya.id);
              for (final m in memberships) {
                if (m.userId != widget.viewerUserId &&
                    !memberMap.containsKey(m.userId)) {
                  memberMap[m.userId] = GrantPreviewSubject(
                    id: m.userId,
                    displayName: (m.displayName ?? '').trim().isNotEmpty
                        ? m.displayName!.trim()
                        : 'Участник семьи',
                    photoUrl: m.avatarUrl,
                  );
                }
              }
            }
          } catch (_) {
            // Optional semya enrichment; relatives already cover linked users.
          }
        }
        if (!mounted) return;
        setState(() {
          if (_cardCandidates.isEmpty && ownedCards.isNotEmpty) {
            _cardCandidates = ownedCards;
          }
          _familyCandidates = memberMap.values.toList(growable: false);
          if (_selectedGraphPersonId == null && _cardCandidates.isNotEmpty) {
            _selectedGraphPersonId = _cardCandidates.first.id;
            _selectedPersonName = _cardCandidates.first.displayName;
          }
        });
        if (_selectedGraphPersonId != null) {
          await _loadExistingGrants(_selectedGraphPersonId!);
        }
      }
    } catch (_) {
      // Non-fatal: user search remains available.
    } finally {
      if (mounted) {
        setState(() => _loadingCandidates = false);
      }
    }
  }

  Future<void> _loadExistingGrants(String graphPersonId) async {
    setState(() => _loadingGrants = true);
    try {
      final grants = await widget.accessService
          .listGraphPersonGrants(graphPersonId: graphPersonId);
      if (!mounted) return;
      setState(() {
        _existingGrants = grants.where((g) => !g.isRevoked).toList();
        _loadingGrants = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingGrants = false);
    }
  }

  Future<void> _searchUsers(String query) async {
    final clean = query.trim();
    if (clean.length < 2) {
      setState(() {
        _searchResults = const <GrantPreviewSubject>[];
        _searchingUsers = false;
      });
      return;
    }
    final profileService = _profileService;
    if (profileService == null) return;
    setState(() => _searchingUsers = true);
    try {
      final List<UserProfile> users =
          await profileService.searchUsers(clean, limit: 10);
      if (!mounted) return;
      setState(() {
        _searchResults = users
            .where((u) => u.id.isNotEmpty && u.id != widget.viewerUserId)
            .map(
              (u) => GrantPreviewSubject(
                id: u.id,
                displayName: u.displayName.trim().isNotEmpty
                    ? u.displayName.trim()
                    : (u.email.isNotEmpty ? u.email : 'Пользователь'),
                photoUrl: u.photoURL,
              ),
            )
            .toList(growable: false);
        _searchingUsers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searchingUsers = false);
    }
  }

  Future<void> _revokeExisting(EditGrant grant) async {
    setState(() => _revokingGrantIds.add(grant.id));
    try {
      await widget.accessService.revokeGraphPersonGrant(
        graphPersonId: grant.graphPersonId,
        grantId: grant.id,
      );
      if (!mounted) return;
      _mutated = true;
      setState(() {
        _existingGrants =
            _existingGrants.where((g) => g.id != grant.id).toList();
        _revokingGrantIds.remove(grant.id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _revokingGrantIds.remove(grant.id);
        _error = humanizeError(error, fallback: 'Не удалось отозвать доступ');
      });
    }
  }

  Future<void> _submit() async {
    final gpId = _selectedGraphPersonId;
    final grantee = _selectedGrantee;
    if (gpId == null ||
        gpId.isEmpty ||
        grantee == null ||
        _selectedScopes.isEmpty) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      for (final scope in _selectedScopes) {
        await widget.accessService.addGraphPersonGrant(
          graphPersonId: gpId,
          granteeUserId: grantee.id,
          scope: scope,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = humanizeError(error, fallback: 'Не удалось выдать доступ');
      });
    }
  }

  List<GrantPreviewSubject> get _displayedGrantees {
    final q = _searchController.text.trim().toLowerCase();
    if (_searchResults.isNotEmpty) {
      return _searchResults;
    }
    if (q.isEmpty) {
      return _familyCandidates;
    }
    return _familyCandidates
        .where((c) => c.displayName.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasLockedCard = widget.initialGraphPersonId != null &&
        widget.initialGraphPersonId!.trim().isNotEmpty;
    final canSubmit = !_submitting &&
        (_selectedGraphPersonId ?? '').isNotEmpty &&
        _selectedGrantee != null &&
        _selectedScopes.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.of(context).pop(_mutated);
        }
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Соавторы карточки',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (hasLockedCard && _selectedPersonName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _selectedPersonName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (!hasLockedCard) ...[
                  if (_loadingCandidates && _cardCandidates.isEmpty)
                    const Center(child: CircularProgressIndicator())
                  else if (_cardCandidates.isEmpty)
                    Text(
                      'Не найдено карточек в вашем владении для выдачи прав.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      key: const Key('grant-sheet-card-dropdown'),
                      initialValue: _selectedGraphPersonId,
                      decoration: const InputDecoration(
                        labelText: 'Карточка',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final card in _cardCandidates)
                          DropdownMenuItem<String>(
                            value: card.id,
                            child: Text(
                              card.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) {
                              if (value == null || value.isEmpty) return;
                              final picked = _cardCandidates
                                  .firstWhere((c) => c.id == value);
                              setState(() {
                                _selectedGraphPersonId = picked.id;
                                _selectedPersonName = picked.displayName;
                                _existingGrants = const <EditGrant>[];
                              });
                              _loadExistingGrants(picked.id);
                            },
                    ),
                  const SizedBox(height: 12),
                ],
                if (_loadingGrants)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (_existingGrants.isNotEmpty) ...[
                  Text(
                    'Уже имеют доступ',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  for (final grant in _existingGrants)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        (grant.grantee?.displayName ?? '').trim().isNotEmpty
                            ? grant.grantee!.displayName
                            : grant.granteeUserId,
                      ),
                      subtitle: Text(grant.scope.russianLabel),
                      trailing: _revokingGrantIds.contains(grant.id)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              key: Key('grant-sheet-revoke-${grant.id}'),
                              icon: const Icon(Icons.close_rounded),
                              tooltip: 'Отозвать доступ',
                              onPressed: () => _revokeExisting(grant),
                            ),
                    ),
                  const Divider(height: 20),
                ],
                Text(
                  'Кому открыть доступ',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('grant-sheet-search-input'),
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Имя или email родственника…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchingUsers
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() {});
                    _searchUsers(value);
                  },
                ),
                const SizedBox(height: 8),
                if (_displayedGrantees.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Нет подходящих пользователей в списке. Введите имя или email выше.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _displayedGrantees.length,
                      itemBuilder: (context, index) {
                        final candidate = _displayedGrantees[index];
                        final isSelected = _selectedGrantee?.id == candidate.id;
                        return ListTile(
                          key: Key('grant-sheet-grantee-${candidate.id}'),
                          dense: true,
                          selected: isSelected,
                          leading: CircleAvatar(
                            radius: 16,
                            child: Text(
                              candidate.displayName.isNotEmpty
                                  ? candidate.displayName[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(candidate.displayName),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          onTap: () =>
                              setState(() => _selectedGrantee = candidate),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Уровень прав',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                for (final scope in EditGrantScope.values)
                  CheckboxListTile(
                    key: Key('grant-sheet-scope-${scope.serverValue}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _selectedScopes.contains(scope),
                    title: Text(scope.russianLabel),
                    onChanged: _submitting
                        ? null
                        : (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedScopes.add(scope);
                              } else {
                                _selectedScopes.remove(scope);
                              }
                            });
                          },
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  key: const Key('grant-sheet-submit'),
                  onPressed: canSubmit ? _submit : null,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Выдать доступ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
