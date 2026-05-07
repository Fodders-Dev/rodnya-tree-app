import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/family_tree.dart';
import '../providers/tree_provider.dart';
import '../theme/app_theme.dart';

/// Phase 6.1: compact branch switcher widget for the top bar.
/// Shows the active branch's name + chevron; tap opens a bottom
/// sheet with every branch the user belongs to plus a "+ Создать
/// ветку" entry. Hidden when the user has no branches yet (a
/// fresh-account state — TreeProvider hasn't loaded anything).
///
/// Plumbing-only: switching just calls TreeProvider.selectTree —
/// existing screens already react to selectedTreeId via their own
/// listeners, so feed/relatives/tree all reload under the new
/// branch with no additional wiring.
class BranchSwitcherChip extends StatelessWidget {
  const BranchSwitcherChip({super.key, this.maxNameWidth = 180});

  /// Max width for the branch-name label. The chip auto-truncates
  /// with an ellipsis when the name doesn't fit. Pass smaller
  /// values for cramped top bars (default 180 is comfortable on
  /// the 320–768px column widths the home/relatives screens use).
  final double maxNameWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Consumer<TreeProvider>(
      builder: (context, treeProvider, _) {
        final selectedName = treeProvider.selectedTreeName;
        final selectedId = treeProvider.selectedTreeId;
        final available = treeProvider.availableTrees;
        // Hide when there's nothing to switch to AND no active
        // branch — a fresh user with no trees would just see an
        // empty chip taking up space. The "+ Создать ветку" path
        // is reachable through the regular /trees screen anyway.
        if (selectedId == null && available.isEmpty) {
          return const SizedBox.shrink();
        }
        final label = selectedName?.trim().isNotEmpty == true
            ? selectedName!.trim()
            : 'Выберите ветку';
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _openSwitcherSheet(
              context,
              treeProvider: treeProvider,
              tokens: tokens,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tokens.surfaceStrong.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: tokens.surfaceLine.withValues(alpha: 0.7),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    size: 16,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxNameWidth),
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: tokens.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: tokens.inkSecondary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSwitcherSheet(
    BuildContext context, {
    required TreeProvider treeProvider,
    required RodnyaDesignTokens tokens,
  }) async {
    // Refresh in the background so the sheet reflects any new
    // branches created on another device. Best-effort; the sheet
    // renders immediately with whatever's already loaded.
    treeProvider.refreshAvailableTrees();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => _BranchSwitcherSheet(
        outerContext: context,
        treeProvider: treeProvider,
      ),
    );
  }
}

class _BranchSwitcherSheet extends StatelessWidget {
  const _BranchSwitcherSheet({
    required this.outerContext,
    required this.treeProvider,
  });

  /// The original context the chip lives in. We use this for
  /// navigation pushes after the sheet pops, since the sheet's
  /// own context is gone by the time the push runs.
  final BuildContext outerContext;
  final TreeProvider treeProvider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle pill — same affordance as the rest of
            // the app's bottom sheets.
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: tokens.surfaceLine,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Ветки',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: tokens.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Каждая ветка — отдельная лента, отдельные истории, отдельные родственники.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.inkSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            for (final tree in treeProvider.availableTrees) ...[
              _BranchSwitcherTile(
                tree: tree,
                isActive: tree.id == treeProvider.selectedTreeId,
                onTap: () async {
                  await treeProvider.selectTree(
                    tree.id,
                    tree.name,
                    treeKind: tree.kind,
                  );
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                outerContext.push('/trees');
              },
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Создать или управлять ветками'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchSwitcherTile extends StatelessWidget {
  const _BranchSwitcherTile({
    required this.tree,
    required this.isActive,
    required this.onTap,
  });

  final FamilyTree tree;
  final bool isActive;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    final memberLabel = tree.isFriendsTree ? 'Круг друзей' : 'Семейная ветка';
    return Material(
      color: isActive
          ? tokens.accent.withValues(alpha: 0.12)
          : tokens.surfaceStrong.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTap(),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tokens.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  tree.isFriendsTree
                      ? Icons.diversity_3_rounded
                      : Icons.account_tree_outlined,
                  size: 20,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tree.name.trim().isEmpty ? 'Без названия' : tree.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: tokens.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      memberLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActive)
                Icon(
                  Icons.check_circle_rounded,
                  color: tokens.accent,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
