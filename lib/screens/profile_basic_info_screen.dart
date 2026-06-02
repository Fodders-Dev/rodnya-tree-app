// Viewer §3.2.1 (2026-06-02): «Основная информация» — a read-view of the
// person's structured fields (имя / девичья / даты / отношение / пол +
// место / работа / учёба …), with a [Редактировать] button that opens the
// existing structured-field editor. Moves these facts OFF the main card
// (which becomes read-first: шапка → биография → «Семья»); the editor and
// the data are unchanged — this is just the read surface + an edit entry.

import 'package:flutter/material.dart';

/// One labelled field. [memorial] appends a «✓ Память» badge (death date).
class BasicInfoField {
  const BasicInfoField(this.label, this.value, {this.memorial = false});
  final String label;
  final String value;
  final bool memorial;
}

class ProfileBasicInfoScreen extends StatelessWidget {
  const ProfileBasicInfoScreen({
    super.key,
    required this.fields,
    this.canEdit = false,
    this.onEdit,
  });

  final List<BasicInfoField> fields;
  final bool canEdit;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Основная информация')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          if (fields.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'Пока ничего не заполнено.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (var i = 0; i < fields.length; i++) _row(theme, fields[i], i),
          if (canEdit) ...[
            const SizedBox(height: 22),
            FilledButton.tonalIcon(
              key: const Key('basic-info-edit'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Редактировать'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, BasicInfoField field, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (index > 0)
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                field.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      field.value,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontFamily: 'Lora',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (field.memorial) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '✓ Память',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
