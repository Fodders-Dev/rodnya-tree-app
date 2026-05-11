import 'package:flutter/material.dart';

import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/graph_person_access_capable_family_tree_service.dart';
import '../backend/models/visibility_choice.dart';

/// Phase 3.4 chunk 2 (PHASE-3.4-UI-PROPOSAL §2.2): visibility
/// toggle section, рендерится на person card в profile-editor
/// mode. Скрывается полностью если:
///   • host service не implements [GraphPersonAccessCapable...]
///     (старый backend без Phase 3.2/3.4-prep);
///   • viewer не owner graphPerson'а (sensitive privacy controls
///     — owner-only-всегда per DECISIONS.md ответ A);
///   • read-state fetch вернул null (no access / network).
///
/// Owner иconfusing UX в proposal §6.A: «Моим родственникам» /
/// «Только мне» / «Всем» вместо технических hops/identity strings.
/// Override checkbox объясняет «по умолчанию авто-public после
/// 100 лет» в одной фразе.
class VisibilityToggleSection extends StatefulWidget {
  const VisibilityToggleSection({
    required this.graphPersonId,
    required this.viewerUserId,
    required this.familyTreeService,
    super.key,
  });

  /// graphPerson.id (= identityId). На relative_details_screen
  /// доступен через `person.identityId`.
  final String graphPersonId;

  /// Текущий viewer (auth.currentUserId). Сравниваем с
  /// `snapshot.effectiveOwnerUserId` чтобы решить показывать ли
  /// section вообще.
  final String viewerUserId;

  final FamilyTreeServiceInterface familyTreeService;

  @override
  State<VisibilityToggleSection> createState() =>
      _VisibilityToggleSectionState();
}

class _VisibilityToggleSectionState extends State<VisibilityToggleSection> {
  GraphPersonAccessSnapshot? _snapshot;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSnapshot();
  }

  GraphPersonAccessCapableFamilyTreeService? get _accessService {
    final service = widget.familyTreeService;
    if (service is GraphPersonAccessCapableFamilyTreeService) {
      return service as GraphPersonAccessCapableFamilyTreeService;
    }
    return null;
  }

  Future<void> _loadSnapshot() async {
    final service = _accessService;
    if (service == null) {
      // Backend без Phase 3.4 capability — section скрывается.
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final snapshot = await service.getGraphPersonAccessSnapshot(
        graphPersonId: widget.graphPersonId,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '$error';
      });
    }
  }

  /// Phase 3.4 chunk 2 (DECISIONS.md follow-up verify-1):
  /// override semantics — radio выбор сам управляет override flag'ом
  /// без отдельного checkbox'а. Tap default radio
  /// ([connectedViaBloodGraph]) сбрасывает override — приватность
  /// продолжает auto-resolve со временем (deceased + 100 лет →
  /// public). Tap non-default ([ownerOnly] / [publicEveryone])
  /// фиксирует выбор (server PATCH автоматом ставит
  /// override=true).
  ///
  /// Reasoning: separate checkbox добавлял ментальную нагрузку без
  /// увеличения expressivity. «Зафиксировать default» как opt-in
  /// — это narrow use-case для deceased предков; который покрывается
  /// выбором non-default «Только мне» / «Всем» (lock).
  Future<void> _onChoiceSelected(VisibilityChoice next) async {
    final service = _accessService;
    if (service == null || _snapshot == null) return;
    setState(() => _isSaving = true);
    try {
      final GraphPersonVisibility updated;
      if (next == VisibilityChoice.connectedViaBloodGraph) {
        // Default radio → clear override. Если override уже был
        // false — endpoint всё равно возвращает 200 idempotent.
        updated = await service.clearGraphPersonVisibilityOverride(
          graphPersonId: widget.graphPersonId,
        );
      } else {
        // Non-default radio → server auto-sets override=true.
        updated = await service.setGraphPersonVisibility(
          graphPersonId: widget.graphPersonId,
          choice: next,
        );
      }
      if (!mounted) return;
      setState(() {
        _snapshot = _snapshot!.copyWithVisibility(updated);
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final snapshot = _snapshot;
    if (snapshot == null) {
      // Не получили — backend без access capability либо access
      // denied. В обоих случаях скрываем section полностью (не
      // leak'аем «secret card exists, but you don't see it»).
      return const SizedBox.shrink();
    }
    final isOwner =
        snapshot.effectiveOwnerUserId == widget.viewerUserId;
    if (!isOwner) {
      // Не-owner не видит section. Per DECISIONS.md ответ A:
      // visibility — owner-only-всегда (даже edit grants не
      // открывают). UI просто не показывает controls.
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Кому видна эта карточка?',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<VisibilityChoice>(
          groupValue: snapshot.visibility.choice,
          onChanged: (value) {
            if (value != null && !_isSaving) {
              _onChoiceSelected(value);
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final option in VisibilityChoice.values)
                RadioListTile<VisibilityChoice>(
                  value: option,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    option.russianLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(option.russianHint),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Footnote — explainer для default-choice case. Non-default
        // radio (Только мне / Всем) автоматом фиксирует выбор;
        // default («Моим родственникам») продолжает auto-resolve со
        // временем. Без отдельного checkbox — UX чище (один control).
        Text(
          'Через 100 лет с рождения карточка автоматически становится '
          'публичной как историческая запись — это работает только '
          'для варианта «Моим родственникам». «Только мне» и «Всем» '
          'фиксируют выбор навсегда.',
          style: theme.textTheme.bodySmall,
        ),
        if (_isSaving)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

extension on GraphPersonAccessSnapshot {
  GraphPersonAccessSnapshot copyWithVisibility(GraphPersonVisibility next) {
    return GraphPersonAccessSnapshot(
      graphPersonId: graphPersonId,
      visibility: next,
      userId: userId,
      createdBy: createdBy,
    );
  }
}
