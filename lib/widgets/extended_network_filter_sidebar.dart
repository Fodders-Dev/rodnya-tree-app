import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/extended_network_controller.dart';
import 'extended_network_filter_sheet.dart' show BranchFilterOption;

/// Phase 4 chunk 2 (PHASE-4-PROPOSAL.md §2.5 wide layout): persistent
/// sidebar 280px wide для wide layout (`MediaQuery.size.width >= 1500`,
/// per relatives_screen breakpoint).
///
/// Те же controls что в filter sheet, но всегда видимые + chips wrap
/// (не scroll, там есть место). Sidebar показывается только в
/// `extended` mode'е — в `mine` контролов нет.
class ExtendedNetworkFilterSidebar extends StatelessWidget {
  const ExtendedNetworkFilterSidebar({
    required this.branchOptions,
    super.key,
  });

  final List<BranchFilterOption> branchOptions;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ExtendedNetworkController>();
    if (controller.mode != ExtendedNetworkMode.extended) {
      // В mine mode sidebar пуст; tree_view_screen решает рендерить
      // его или нет, но defensive shrink-cast если caller всё-таки
      // показывает.
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
      ),
      child: ListView(
        children: [
          Text(
            'Расширенная сеть',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _DepthSlider(controller: controller),
          const SizedBox(height: 16),
          if (branchOptions.isNotEmpty) ...[
            Text(
              'По веткам',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _BranchChipsWrap(
              branchOptions: branchOptions,
              controller: controller,
            ),
            const SizedBox(height: 16),
          ],
          _AnonymousSwitch(controller: controller),
          const SizedBox(height: 16),
          _StatsPreview(controller: controller),
        ],
      ),
    );
  }
}

class _DepthSlider extends StatelessWidget {
  const _DepthSlider({required this.controller});

  final ExtendedNetworkController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hops = controller.maxHops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Глубина',
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Slider(
          value: hops.toDouble(),
          min: 2,
          max: 4,
          divisions: 2,
          label: '$hops',
          onChanged: (value) => controller.setMaxHops(value.round()),
        ),
        Text(
          _hopsCaption(hops),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  static String _hopsCaption(int hops) {
    switch (hops) {
      case 2:
        return 'Ближний круг (близкие связи)';
      case 3:
        return 'Средний круг (+ кузены, прабабушки)';
      case 4:
      default:
        return 'Полная сеть (== privacy fence)';
    }
  }
}

class _BranchChipsWrap extends StatelessWidget {
  const _BranchChipsWrap({
    required this.branchOptions,
    required this.controller,
  });

  final List<BranchFilterOption> branchOptions;
  final ExtendedNetworkController controller;

  @override
  Widget build(BuildContext context) {
    final filter = controller.branchFilter;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        FilterChip(
          label: const Text('Все'),
          selected: filter.isEmpty,
          onSelected: (_) {
            controller.setBranchFilter(<String>{});
          },
        ),
        for (final option in branchOptions)
          FilterChip(
            label: Text(option.displayName),
            selected: filter.contains(option.treeId),
            onSelected: (selected) {
              final next = Set<String>.from(filter);
              if (selected) {
                next.add(option.treeId);
              } else {
                next.remove(option.treeId);
              }
              controller.setBranchFilter(next);
            },
          ),
      ],
    );
  }
}

class _AnonymousSwitch extends StatelessWidget {
  const _AnonymousSwitch({required this.controller});

  final ExtendedNetworkController controller;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: const Text('Анонимные'),
      subtitle: const Text('Без user-аккаунта'),
      value: controller.includeAnonymous,
      onChanged: controller.setIncludeAnonymous,
    );
  }
}

class _StatsPreview extends StatelessWidget {
  const _StatsPreview({required this.controller});

  final ExtendedNetworkController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slice = controller.slice;
    if (controller.isFetching) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Загружаем сеть...',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }
    if (controller.error != null) {
      return Text(
        'Ошибка: ${controller.error}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }
    if (slice == null) {
      return Text(
        'Слайс не загружен',
        style: theme.textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Показано: ${slice.stats.totalCount} человек',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Из моего дерева: ${slice.stats.myCount}, '
          'расширенная сеть: ${slice.stats.extendedCount}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (slice.stats.capReached)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Достигнут лимит — сузьте через фильтры',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
