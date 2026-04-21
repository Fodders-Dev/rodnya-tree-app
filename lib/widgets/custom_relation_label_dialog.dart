import 'package:flutter/material.dart';

import '../models/family_person.dart';

class CustomRelationLabels {
  const CustomRelationLabels({
    required this.relation1to2,
    required this.relation2to1,
  });

  final String relation1to2;
  final String relation2to1;
}

class _CustomRelationPreset {
  const _CustomRelationPreset({
    required this.label,
    required this.relation1to2,
    required this.relation2to1,
  });

  final String label;
  final String relation1to2;
  final String relation2to1;
}

Future<CustomRelationLabels?> showCustomRelationLabelDialog({
  required BuildContext context,
  required String person1Name,
  required String person2Name,
  Gender? person1Gender,
  Gender? person2Gender,
  String? initialRelation1to2,
  String? initialRelation2to1,
}) {
  final relation1Controller = TextEditingController(
    text: initialRelation1to2?.trim() ?? '',
  );
  final relation2Controller = TextEditingController(
    text: initialRelation2to1?.trim() ?? '',
  );
  final presets = <_CustomRelationPreset>[
    _CustomRelationPreset(
      label: 'Кум / кума',
      relation1to2: _godparentLabelForGender(person1Gender),
      relation2to1: _godparentLabelForGender(person2Gender),
    ),
    const _CustomRelationPreset(
      label: 'Побратимы',
      relation1to2: 'Побратим',
      relation2to1: 'Побратим',
    ),
    const _CustomRelationPreset(
      label: 'Свояки',
      relation1to2: 'Свояк',
      relation2to1: 'Свояк',
    ),
    const _CustomRelationPreset(
      label: 'Примак',
      relation1to2: 'Примак',
      relation2to1: 'Родня по браку',
    ),
  ];

  return showDialog<CustomRelationLabels>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          void applyPreset(_CustomRelationPreset preset) {
            relation1Controller.text = preset.relation1to2;
            relation2Controller.text = preset.relation2to1;
            setDialogState(() {});
          }

          return AlertDialog(
            title: const Text('Другое родство'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Укажите, кем люди приходятся друг другу. Это пригодится для редких связей вроде кума, побратима или примака.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: presets
                          .map(
                            (preset) => ActionChip(
                              label: Text(preset.label),
                              onPressed: () => applyPreset(preset),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: relation1Controller,
                      decoration: InputDecoration(
                        labelText: '$person1Name для $person2Name',
                        hintText: 'Например, кум',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: relation2Controller,
                      decoration: InputDecoration(
                        labelText: '$person2Name для $person1Name',
                        hintText: 'Например, кума',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  var relation1to2 = relation1Controller.text.trim();
                  var relation2to1 = relation2Controller.text.trim();
                  if (relation1to2.isEmpty && relation2to1.isEmpty) {
                    return;
                  }
                  if (relation1to2.isEmpty) {
                    relation1to2 = relation2to1;
                  }
                  if (relation2to1.isEmpty) {
                    relation2to1 = relation1to2;
                  }
                  Navigator.of(dialogContext).pop(
                    CustomRelationLabels(
                      relation1to2: relation1to2,
                      relation2to1: relation2to1,
                    ),
                  );
                },
                child: const Text('Сохранить'),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(() {
    relation1Controller.dispose();
    relation2Controller.dispose();
  });
}

String _godparentLabelForGender(Gender? gender) {
  if (gender == Gender.female) {
    return 'Кума';
  }
  return 'Кум';
}
