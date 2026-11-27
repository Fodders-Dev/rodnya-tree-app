import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/models/semya.dart' show SemyaError;
import '../backend/models/semya_browse_token.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../utils/person_date_format.dart';
import '../widgets/interactive_family_tree.dart';
import '../widgets/pull_person_sheet.dart';

/// Read-only browse view of a shared family tree via `/browse/:token`.
///
/// Consolidates capability-token tree browsing + guest details inspection +
/// branch focus + optional signed-in «Добавить к себе в семью» action.
class BrowseTreeScreen extends StatefulWidget {
  const BrowseTreeScreen({
    super.key,
    required this.browseToken,
  });

  final String browseToken;

  @override
  State<BrowseTreeScreen> createState() => _BrowseTreeScreenState();
}

class _BrowseTreeScreenState extends State<BrowseTreeScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  BrowsedSemyaTree? _snapshot;
  String? _branchRootPersonId;
  String? _branchRootName;

  SemyaCapableFamilyTreeService? get _service {
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) return null;
    final raw = GetIt.I<FamilyTreeServiceInterface>();
    if (raw is SemyaCapableFamilyTreeService) {
      return raw as SemyaCapableFamilyTreeService;
    }
    return null;
  }

  bool get _isAuthenticated {
    if (!GetIt.I.isRegistered<AuthServiceInterface>()) return false;
    final userId = GetIt.I<AuthServiceInterface>().currentUserId;
    return userId != null && userId.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSnapshot());
  }

  Future<void> _loadSnapshot() async {
    final service = _service;
    if (service == null) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Просмотр недоступен — приложение не поддерживает эту ссылку.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final snapshot = await service.fetchBrowseTree(widget.browseToken);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            error is SemyaError ? error.message : 'Не удалось загрузить дерево';
      });
    }
  }

  void _focusBranch(FamilyPerson person) {
    setState(() {
      _branchRootPersonId = person.id;
      _branchRootName = person.name;
    });
  }

  void _resetBranchFocus() {
    setState(() {
      _branchRootPersonId = null;
      _branchRootName = null;
    });
  }

  void _handlePersonTap(FamilyPerson person) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final isSignedIn = _isAuthenticated;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  person.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (person.maidenName?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    'В девичестве: ${person.maidenName!.trim()}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PersonChip(
                      icon: Icons.person_outline,
                      label: _genderLabel(person.gender),
                    ),
                    if (person.birthDate != null)
                      _PersonChip(
                        icon: Icons.cake_outlined,
                        label: 'Родился: ${formatPersonDate(
                          person.birthDate!,
                          person.birthDatePrecision,
                        )}',
                      ),
                    if (person.deathDate != null)
                      _PersonChip(
                        icon: Icons.history_toggle_off_outlined,
                        label: 'Умер: ${formatPersonDate(
                          person.deathDate!,
                          person.deathDatePrecision,
                        )}',
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  key: const Key('browse-person-focus-branch'),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _focusBranch(person);
                  },
                  icon: const Icon(Icons.alt_route),
                  label: const Text('Показать ветку от этого человека'),
                ),
                const SizedBox(height: 10),
                if (isSignedIn)
                  FilledButton.icon(
                    key: const Key('browse-person-pull'),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _openPullSheet(snapshot, person);
                    },
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Добавить к себе в семью'),
                  )
                else
                  FilledButton.icon(
                    key: const Key('browse-person-login'),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      final from = Uri.encodeComponent(
                        '/browse/${widget.browseToken}',
                      );
                      context.go('/login?from=$from');
                    },
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Войти, чтобы добавить в семью'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPullSheet(
    BrowsedSemyaTree snapshot,
    FamilyPerson person,
  ) async {
    final result = await showPullPersonSheet(
      context,
      sourceSemyaId: snapshot.semyaId,
      sourcePersonId: person.id,
      sourcePersonName: person.name,
    );
    if (result?.success == true && mounted) {
      final targetName = result?.targetSemya?.name ?? 'свою семью';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${person.name} добавлен(а) в $targetName'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  String _genderLabel(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 'Мужчина';
      case Gender.female:
        return 'Женщина';
      case Gender.other:
        return 'Другой пол';
      case Gender.unknown:
        return 'Пол не указан';
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          snapshot?.semyaName ?? 'Дерево семьи',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadSnapshot,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _BrowseErrorState(
        message: _errorMessage!,
        onRetry: _loadSnapshot,
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        _ReadOnlyBanner(
          semya: snapshot,
          isAuthenticated: _isAuthenticated,
          branchRootName: _branchRootName,
          onResetBranch: _branchRootPersonId != null ? _resetBranchFocus : null,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: InteractiveFamilyTree(
              peopleData: snapshot.persons
                  .map(
                    (p) => <String, dynamic>{
                      'person': _toFamilyPerson(p, snapshot.treeId),
                      'userProfile': null,
                    },
                  )
                  .toList(),
              relations: snapshot.relations
                  .map((r) => _toFamilyRelation(r, snapshot.treeId))
                  .toList(),
              currentUserId: null,
              branchRootPersonId: _branchRootPersonId,
              onBranchFocusCleared: _resetBranchFocus,
              onPersonTap: _handlePersonTap,
              onBranchFocusRequested: _focusBranch,
              isEditMode: false,
              onAddRelativeTapWithType: (_, __) {},
              currentUserIsInTree: false,
              onAddSelfTapWithType: (_, __) {},
            ),
          ),
        ),
      ],
    );
  }

  FamilyPerson _toFamilyPerson(BrowsedPerson p, String treeId) {
    return FamilyPerson(
      id: p.id,
      treeId: treeId,
      identityId: p.identityId,
      name: p.name,
      maidenName: p.maidenName,
      gender: _genderFromString(p.gender),
      birthDate: _parseDate(p.birthDate),
      birthDatePrecision:
          FamilyPerson.datePrecisionFromString(p.birthDatePrecision),
      deathDate: _parseDate(p.deathDate),
      deathDatePrecision:
          FamilyPerson.datePrecisionFromString(p.deathDatePrecision),
      isAlive: p.deathDate == null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  FamilyRelation _toFamilyRelation(BrowsedRelation r, String treeId) {
    return FamilyRelation(
      id: r.id,
      treeId: treeId,
      person1Id: r.person1Id,
      person2Id: r.person2Id,
      relation1to2:
          _relationTypeFromString(r.relation1to2) ?? RelationType.other,
      relation2to1:
          _relationTypeFromString(r.relation2to1) ?? RelationType.other,
      isConfirmed: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Gender _genderFromString(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'male':
        return Gender.male;
      case 'female':
        return Gender.female;
      default:
        return Gender.unknown;
    }
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  RelationType? _relationTypeFromString(String? raw) {
    if (raw == null) return null;
    return FamilyRelation.stringToRelationType(raw);
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({
    required this.semya,
    required this.isAuthenticated,
    this.branchRootName,
    this.onResetBranch,
  });

  final BrowsedSemyaTree semya;
  final bool isAuthenticated;
  final String? branchRootName;
  final VoidCallback? onResetBranch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.visibility_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Только просмотр',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    Text(
                      isAuthenticated
                          ? 'Это дерево семьи «${semya.semyaName}». Нажмите на человека для деталей или добавления к себе.'
                          : 'Это дерево семьи «${semya.semyaName}». Нажмите на человека, чтобы посмотреть детали или ветку.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (onResetBranch != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onResetBranch,
              icon: const Icon(Icons.account_tree_outlined, size: 16),
              label: Text(
                branchRootName != null
                    ? 'Вся семья (сейчас ветка: $branchRootName)'
                    : 'Показать всё дерево',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BrowseErrorState extends StatelessWidget {
  const _BrowseErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => onRetry(),
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
