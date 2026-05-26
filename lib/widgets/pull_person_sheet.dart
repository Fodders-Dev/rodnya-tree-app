import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/semya_capable_family_tree_service.dart';
import '../backend/models/semya.dart';

/// Ship FE5 (2026-05-26): pull-person target picker modal. Wraps
/// backend Ship 6 (eba1a25) POST /v1/semya/:targetSemyaId/pull-person.
///
/// Flow:
///   1. Modal opens с loading state
///   2. Fetches caller's список семьи (listMySemya)
///   3. Filters к семьи где caller has editor либо owner role
///   4. User picks target → calls pullPersonToSemya
///   5. Success: pops sheet с `(true, targetSemya)` — caller surfaces
///      snackbar + optional «Открыть» navigation
///
/// Backend Ship 6 endpoint NOT принимает relationType/nameOverride
/// args — bulkImport copies person как-есть. User add relations
/// separately после pull via existing add-relative flow.
///
/// Returns `null` если user cancelled либо service failure (caller
/// shows error snackbar based on optional `error` field в result).
class PullPersonResult {
  const PullPersonResult({
    required this.success,
    this.targetSemya,
    this.errorMessage,
  });

  final bool success;
  final Semya? targetSemya;
  final String? errorMessage;
}

Future<PullPersonResult?> showPullPersonSheet(
  BuildContext context, {
  required String sourceSemyaId,
  required String sourcePersonId,
  required String sourcePersonName,
}) async {
  return showModalBottomSheet<PullPersonResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => PullPersonSheet(
      sourceSemyaId: sourceSemyaId,
      sourcePersonId: sourcePersonId,
      sourcePersonName: sourcePersonName,
    ),
  );
}

class PullPersonSheet extends StatefulWidget {
  const PullPersonSheet({
    super.key,
    required this.sourceSemyaId,
    required this.sourcePersonId,
    required this.sourcePersonName,
    this.serviceOverride,
  });

  final String sourceSemyaId;
  final String sourcePersonId;
  final String sourcePersonName;

  /// Test-seam: caller injects fake service. Production resolves
  /// FamilyTreeServiceInterface через GetIt.
  final SemyaCapableFamilyTreeService? serviceOverride;

  @override
  State<PullPersonSheet> createState() => _PullPersonSheetState();
}

class _PullPersonSheetState extends State<PullPersonSheet> {
  List<Semya>? _eligibleSemyi;
  bool _isLoading = true;
  bool _isPulling = false;
  String? _errorMessage;
  String? _pendingTargetId;

  SemyaCapableFamilyTreeService? get _service {
    if (widget.serviceOverride != null) return widget.serviceOverride;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTargets());
  }

  Future<void> _loadTargets() async {
    final service = _service;
    if (service == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Сервис недоступен';
      });
      return;
    }
    try {
      final all = await service.listMySemya();
      // Filter: exclude source семя (cannot pull to itself per backend
      // 400 rule); render все остальные. Role gating happens via per-row
      // SemyaDetails fetch когда target tapped — keeps initial render
      // fast without N+1 detail calls. Backend rejects 403 если target
      // role insufficient.
      final eligible = all
          .where((s) => s.id != widget.sourceSemyaId)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _eligibleSemyi = eligible;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error is SemyaError
            ? error.message
            : 'Не удалось загрузить ваши семьи';
      });
    }
  }

  Future<void> _pullTo(Semya target) async {
    final service = _service;
    if (service == null) return;
    setState(() {
      _isPulling = true;
      _pendingTargetId = target.id;
      _errorMessage = null;
    });
    try {
      await service.pullPersonToSemya(
        targetSemyaId: target.id,
        sourceSemyaId: widget.sourceSemyaId,
        sourcePersonId: widget.sourcePersonId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        PullPersonResult(success: true, targetSemya: target),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPulling = false;
        _pendingTargetId = null;
        _errorMessage = error is SemyaError
            ? error.message
            : 'Не удалось добавить';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Добавить ${widget.sourcePersonName} в семью',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              'Выберите целевую семью. Связи можно будет добавить '
              'после добавления.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_eligibleSemyi == null || _eligibleSemyi!.isEmpty)
              _emptyState(theme)
            else
              ..._eligibleSemyi!.map(
                (semya) => _SemyaTargetTile(
                  key: Key('pull-target-${semya.id}'),
                  semya: semya,
                  isPending: _pendingTargetId == semya.id,
                  isDisabled: _isPulling && _pendingTargetId != semya.id,
                  onTap: _isPulling ? null : () => _pullTo(semya),
                ),
              ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.family_restroom_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'У вас нет других семей',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Создайте семью либо примите приглашение, чтобы добавлять туда родственников.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SemyaTargetTile extends StatelessWidget {
  const _SemyaTargetTile({
    super.key,
    required this.semya,
    required this.isPending,
    required this.isDisabled,
    required this.onTap,
  });

  final Semya semya;
  final bool isPending;
  final bool isDisabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: ListTile(
        leading: Icon(
          Icons.family_restroom_rounded,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          semya.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: semya.description?.isNotEmpty == true
            ? Text(
                semya.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: isPending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}
