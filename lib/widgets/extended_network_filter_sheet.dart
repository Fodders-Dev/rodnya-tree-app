import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/extended_network_controller.dart';

/// Branch chip entry shape. (Records requires Dart 3+, у нас pubspec
/// allows 2.17.0+ — поэтому plain class.)
class BranchFilterOption {
  const BranchFilterOption({required this.treeId, required this.displayName});

  final String treeId;
  final String displayName;
}

/// Phase 4 chunk 2 (PHASE-4-PROPOSAL.md §2.5 + DECISIONS.md 2026-05-12
/// Q6.A/Q7.A): mobile filter sheet для extended-network view.
///
/// Controls:
///   • Slider depth **2..4 default 4** — labels «Ближний круг» / «Средний
///     круг» / «Полная сеть» (Q6.A).
///   • Chips «По веткам» — horizontal scrollable (Q7.A). Branch list
///     приходит из `branchOptions` — caller передаёт известные tree'ы
///     (плюс «Все» implicit).
///   • Switch «Показывать anonymous'ы (не привязанные к user'у)».
///
/// Sheet open'ится через [showExtendedNetworkFilterSheet] helper.
class ExtendedNetworkFilterSheet extends StatelessWidget {
  const ExtendedNetworkFilterSheet({
    required this.branchOptions,
    super.key,
  });

  /// Список known branches/trees для chip select'а. Каждая entry —
  /// `(treeId, displayName)`. Если empty — chips не показываются.
  final List<BranchFilterOption> branchOptions;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return _FilterSheetBody(
          branchOptions: branchOptions,
          scrollController: scrollController,
        );
      },
    );
  }
}

class _FilterSheetBody extends StatelessWidget {
  const _FilterSheetBody({
    required this.branchOptions,
    required this.scrollController,
  });

  final List<BranchFilterOption> branchOptions;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<ExtendedNetworkController>();
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Фильтры расширенной сети',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
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
            _BranchChips(
              branchOptions: branchOptions,
              controller: controller,
            ),
            const SizedBox(height: 16),
          ],
          _AnonymousSwitch(controller: controller),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Глубина связи',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              _hopsCaption(hops),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: hops.toDouble(),
          min: 2,
          max: 4,
          divisions: 2,
          label: _hopsCaption(hops),
          onChanged: (value) => controller.setMaxHops(value.round()),
        ),
        Text(
          'Слайдер не выходит за пределы 4 поколений — это граница '
          'приватности (доступно только то, что вы и так можете видеть).',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String _hopsCaption(int hops) {
    switch (hops) {
      case 2:
        return '2 — Ближний круг';
      case 3:
        return '3 — Средний круг';
      case 4:
      default:
        return '4 — Полная сеть';
    }
  }
}

class _BranchChips extends StatelessWidget {
  const _BranchChips({
    required this.branchOptions,
    required this.controller,
  });

  final List<BranchFilterOption> branchOptions;
  final ExtendedNetworkController controller;

  @override
  Widget build(BuildContext context) {
    final filter = controller.branchFilter;
    final isAllSelected = filter.isEmpty;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          FilterChip(
            label: const Text('Все'),
            selected: isAllSelected,
            onSelected: (_) {
              controller.setBranchFilter(<String>{});
            },
          ),
          for (final option in branchOptions) ...[
            const SizedBox(width: 8),
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
        ],
      ),
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
      title: const Text('Показывать карточки без аккаунта'),
      subtitle: const Text(
        'Анонимные предки/потомки, вписанные родственниками без '
        'привязки к user-аккаунту.',
      ),
      value: controller.includeAnonymous,
      onChanged: controller.setIncludeAnonymous,
    );
  }
}

/// Helper для открытия sheet'а из tree_view_screen.
Future<void> showExtendedNetworkFilterSheet(
  BuildContext context, {
  required ExtendedNetworkController controller,
  required List<BranchFilterOption> branchOptions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return ChangeNotifierProvider<ExtendedNetworkController>.value(
        value: controller,
        child: ExtendedNetworkFilterSheet(branchOptions: branchOptions),
      );
    },
  );
}
