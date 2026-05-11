import 'package:flutter/material.dart';

import '../backend/models/identity_field_conflict.dart';

/// Phase 3.4 chunk 5 (PHASE-3.4-UI-PROPOSAL.md §2.5 + расширение
/// surface'а Phase 1.3 sheet'а): reusable conflict resolution
/// sheet. До chunk 5 жил приватно в [`tree_view_screen.dart`]
/// (`_IdentityConflictsSheet` + `_ConflictRow` + `_ConflictSide` +
/// `_kIdentityConflictFieldLabels`); чистый extract без поведения
/// behavior changes.
///
/// One row per diverging field with side-by-side
/// "keep mine" / "accept other branch's value". Plain text
/// rendering of values — good enough for v1; richer formatting
/// (date, photo preview) comes with the Phase 3 lens migration
/// when the conflict surface becomes more central.
///
/// Чтобы открыть как modal — используй [`showIdentityConflictsSheet`]
/// helper'ом, он wrap'ит [`showModalBottomSheet`].

const Map<String, String> kIdentityConflictFieldLabels = <String, String>{
  'name': 'ФИО',
  'maidenName': 'Девичья фамилия',
  'gender': 'Пол',
  'birthDate': 'Дата рождения',
  'deathDate': 'Дата смерти',
  'isAlive': 'Признак "жив"',
  'birthPlace': 'Место рождения',
  'deathPlace': 'Место смерти',
  'photoUrl': 'Фото',
  'primaryPhotoUrl': 'Основное фото',
  'photoGallery': 'Галерея фото',
};

String identityConflictFieldLabel(String field) =>
    kIdentityConflictFieldLabels[field] ?? field;

String formatIdentityConflictValue(String field, dynamic value) {
  if (value == null) return '— пусто —';
  if (field == 'photoGallery') {
    if (value is List) {
      return value.isEmpty ? '— пусто —' : '${value.length} фото';
    }
    return value.toString();
  }
  if (value is bool) return value ? 'да' : 'нет';
  final stringValue = value.toString().trim();
  return stringValue.isEmpty ? '— пусто —' : stringValue;
}

/// Callback signature: caller получает sheetContext (для pop/
/// snackbar после choice'а), сам conflict + 'keep'/'overwrite'.
/// Передача sheetContext важна — caller обычно хочет закрыть sheet
/// после успешного resolve'а через
/// `Navigator.of(sheetContext).pop()`. До extract'а это был builder
/// closure-captured sheetContext в `tree_view_screen.dart`; теперь
/// явная часть API.
typedef IdentityConflictChoiceCallback = Future<void> Function(
  BuildContext sheetContext,
  IdentityFieldConflict conflict,
  String choice,
);

/// Wraps [`showModalBottomSheet`] с правильными defaults
/// (isScrollControlled=true так как сами строки могут быть высокими
/// для photoGallery / длинных адресов).
Future<void> showIdentityConflictsSheet({
  required BuildContext context,
  required List<IdentityFieldConflict> conflicts,
  required IdentityConflictChoiceCallback onChoice,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => IdentityConflictsSheet(
      conflicts: conflicts,
      onChoice: (conflict, choice) =>
          onChoice(sheetContext, conflict, choice),
    ),
  );
}

class IdentityConflictsSheet extends StatelessWidget {
  const IdentityConflictsSheet({
    required this.conflicts,
    required this.onChoice,
    super.key,
  });

  final List<IdentityFieldConflict> conflicts;

  /// Called when the user picks a side. `choice` is `'keep'` или
  /// `'overwrite'`. Внутренний callback — без sheetContext (его
  /// прокидывает [`showIdentityConflictsSheet`] обёртка, чтобы
  /// caller мог Navigator.pop / snackbar). Используется direct'но
  /// в widget-tests без modal-shadow'а.
  final Future<void> Function(IdentityFieldConflict conflict, String choice)
      onChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: scheme.error,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conflicts.length == 1
                            ? 'Расхождение в одной ветке'
                            : 'Расхождения в ${conflicts.length} полях',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Этот человек по-разному заполнен на разных ветках. '
                        'Выберите, какое значение оставить.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final conflict in conflicts) ...[
              _ConflictRow(
                conflict: conflict,
                onChoice: (choice) => onChoice(conflict, choice),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({
    required this.conflict,
    required this.onChoice,
  });

  final IdentityFieldConflict conflict;
  final Future<void> Function(String choice) onChoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fieldLabel = identityConflictFieldLabel(conflict.field);
    final ourValue =
        formatIdentityConflictValue(conflict.field, conflict.targetValue);
    final theirValue =
        formatIdentityConflictValue(conflict.field, conflict.sourceValue);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fieldLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _ConflictSide(
            label: 'Здесь',
            value: ourValue,
            actionLabel: 'Оставить',
            onTap: () => onChoice('keep'),
            isPrimary: false,
          ),
          const SizedBox(height: 8),
          _ConflictSide(
            label: 'На другой ветке',
            value: theirValue,
            actionLabel: 'Принять',
            onTap: () => onChoice('overwrite'),
            isPrimary: true,
          ),
        ],
      ),
    );
  }
}

class _ConflictSide extends StatelessWidget {
  const _ConflictSide({
    required this.label,
    required this.value,
    required this.actionLabel,
    required this.onTap,
    required this.isPrimary,
  });

  final String label;
  final String value;
  final String actionLabel;
  final Future<void> Function() onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 120,
          child: isPrimary
              ? FilledButton(
                  onPressed: () => onTap(),
                  child: Text(actionLabel),
                )
              : OutlinedButton(
                  onPressed: () => onTap(),
                  child: Text(actionLabel),
                ),
        ),
      ],
    );
  }
}
