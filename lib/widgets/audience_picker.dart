import 'package:flutter/material.dart';

import '../models/circle.dart';

class AudiencePicker extends StatelessWidget {
  const AudiencePicker({
    super.key,
    required this.circles,
    required this.selectedCircleId,
    required this.onChanged,
    this.isLoading = false,
    this.isUnavailable = false,
    this.onRetry,
  });

  final List<FamilyCircle> circles;
  final String? selectedCircleId;
  final ValueChanged<String?> onChanged;
  final bool isLoading;
  final bool isUnavailable;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedValue = _resolveSelectedValue();
    final hasChoices = circles.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Кому видно',
            prefixIcon: Icon(
              Icons.group_work_outlined,
              color: theme.colorScheme.primary,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedValue,
              isExpanded: true,
              items: hasChoices
                  ? circles
                      .map(
                        (circle) => DropdownMenuItem<String>(
                          value: circle.id,
                          child: _AudienceOption(circle: circle),
                        ),
                      )
                      .toList(growable: false)
                  : const [
                      DropdownMenuItem<String>(
                        value: '',
                        child: Text('Всё дерево'),
                      ),
                    ],
              onChanged: isLoading || !hasChoices ? null : onChanged,
            ),
          ),
        ),
        if (isLoading || isUnavailable) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              if (isLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                Icon(
                  Icons.cloud_off_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isLoading ? 'Загружаем круги' : 'Круги недоступны',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (!isLoading && onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Повторить'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String? _resolveSelectedValue() {
    if (circles.isEmpty) {
      return '';
    }
    final selected = selectedCircleId;
    if (selected != null && circles.any((circle) => circle.id == selected)) {
      return selected;
    }
    for (final circle in circles) {
      if (circle.isAllTree) {
        return circle.id;
      }
    }
    return circles.first.id;
  }
}

class _AudienceOption extends StatelessWidget {
  const _AudienceOption({required this.circle});

  final FamilyCircle circle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memberLabel = _memberLabel(circle.memberCount);

    return Text(
      '${circle.name} · $memberLabel',
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium,
    );
  }

  String _memberLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    final suffix = mod10 == 1 && mod100 != 11
        ? 'человек'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
            ? 'человека'
            : 'человек';
    return '$count $suffix';
  }
}
