import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/models/semya.dart' show SemyaError;
import '../backend/models/semya_browse_token.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../widgets/interactive_family_tree.dart';
import '../widgets/pull_person_sheet.dart';

/// Ship FE6a (2026-05-26): read-only browse view of someone else's
/// семя tree via shared capability token. Backend Ship 7 endpoint
/// GET /v1/browse/:token returns privacy-filtered persons + relations.
///
/// Mirrors `PublicTreeViewerScreen` pattern для familiar canvas
/// rendering. Persons tap fires `PullPersonSheet` (FE5 entry point) —
/// recipient can copy интересного relative к caller's own семя.
///
/// Route registered as anonymous-allowed via app_router_guards (mirror
/// /public/tree/:id exemption pattern).
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

  SemyaCapableFamilyTreeService? get _service {
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) return null;
    final raw = GetIt.I<FamilyTreeServiceInterface>();
    if (raw is SemyaCapableFamilyTreeService) {
      return raw as SemyaCapableFamilyTreeService;
    }
    return null;
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
        _errorMessage = error is SemyaError
            ? error.message
            : 'Не удалось загрузить дерево';
      });
    }
  }

  void _handlePersonTap(FamilyPerson person) {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    // FE5 entry point: launch PullPersonSheet с source семя ID
    // (from browse snapshot) + source person ID (from tap). Recipient
    // picks target семя where they're editor+ → backend handles copy.
    unawaited(
      showPullPersonSheet(
        context,
        sourceSemyaId: snapshot.semyaId,
        sourcePersonId: person.id,
        sourcePersonName: person.name,
      ).then((result) {
        if (result?.success == true && mounted) {
          final targetName = result?.targetSemya?.name ?? 'свою семью';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${person.name} добавлен(а) в $targetName',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }),
    );
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
        _ReadOnlyBanner(semya: snapshot),
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
              onPersonTap: _handlePersonTap,
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

  // Adapter: BrowsedPerson → FamilyPerson чтобы reuse существующий
  // InteractiveFamilyTree renderer без refactor. Privacy-filtered fields
  // map prosto — backend explicitly omits photos/bio.
  FamilyPerson _toFamilyPerson(BrowsedPerson p, String treeId) {
    return FamilyPerson(
      id: p.id,
      treeId: treeId,
      identityId: p.identityId,
      name: p.name,
      maidenName: p.maidenName,
      gender: _genderFromString(p.gender),
      birthDate: _parseDate(p.birthDate),
      // D3: точность дат едет в FamilyPerson — всё, что ниже по течению
      // (карточки, шиты), остаётся честным для «знаю только год».
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

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.semya});

  final BrowsedSemyaTree semya;

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
      child: Row(
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
                  'Это дерево семьи «${semya.semyaName}». '
                  'Нажмите на человека, чтобы добавить его в свою семью.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
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

// Tiny helper для fire-and-forget — local instead of importing dart:async
// чтобы keep imports minimal.
void unawaited(Future<void> future) {}
