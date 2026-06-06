import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'relatives_screen.dart';
import 'tree_view_screen.dart';

/// Which body the «Семья» tab is showing.
enum FamilyView { list, tree }

/// UX-core S1: the unified «Семья» tab. It merges the former «Родные»
/// (people list) and «Дерево» (canvas) tabs behind one segmented toggle
/// (Список ⇄ Дерево), so the family lives in a single place instead of two
/// tabs that each linked to the other.
///
/// Per the agreed design (Option A): the toggle is a slim shared strip; the
/// list view hosts the relatives screen and the tree view hosts the canvas
/// **with their existing chrome untouched** (the canvas internals/toolbar are
/// a separate cohesion phase). The selected tree/branch is shared state
/// (TreeProvider), so flipping the toggle keeps the same family in view.
class FamilyScreen extends StatefulWidget {
  const FamilyScreen({
    super.key,
    this.initialView = FamilyView.list,
    this.listBuilder,
    this.treeBuilder,
  });

  /// Which view to open on first build (driven by the `?view=` deep-link
  /// param: `list` ⇒ Список, `tree` ⇒ Дерево).
  final FamilyView initialView;

  /// Test seams — production falls back to the real screens.
  final WidgetBuilder? listBuilder;
  final WidgetBuilder? treeBuilder;

  /// Maps a `?view=` query value to a [FamilyView] (defaults to list).
  static FamilyView viewFromQuery(String? value) =>
      value == 'tree' ? FamilyView.tree : FamilyView.list;

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  late FamilyView _view = widget.initialView;

  // The tree canvas is heavy (data load + layout), so we don't build it until
  // the user first opens the Дерево view. Once visited it stays mounted inside
  // the IndexedStack, preserving its zoom/scroll state across toggles.
  bool _treeVisited = false;

  void _select(FamilyView view) {
    if (_view == view) return;
    setState(() => _view = view);
  }

  Widget _listChild() =>
      widget.listBuilder?.call(context) ?? const RelativesScreen();

  Widget _treeChild() =>
      widget.treeBuilder?.call(context) ?? const TreeViewScreen();

  @override
  Widget build(BuildContext context) {
    if (_view == FamilyView.tree) {
      _treeVisited = true;
    }

    return Column(
      children: [
        _FamilyViewToggle(
          view: _view,
          onChanged: _select,
        ),
        Expanded(
          child: IndexedStack(
            index: _view == FamilyView.list ? 0 : 1,
            children: [
              _listChild(),
              // Deferred until first visited, then kept alive.
              _treeVisited ? _treeChild() : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Slim segmented [Список | Дерево] control sitting above both bodies.
class _FamilyViewToggle extends StatelessWidget {
  const _FamilyViewToggle({
    required this.view,
    required this.onChanged,
  });

  final FamilyView view;
  final ValueChanged<FamilyView> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: tokens.surfaceStrong,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tokens.surfaceLine),
          ),
          child: Row(
            children: [
              _segment(
                tokens: tokens,
                key: const Key('family-view-list'),
                icon: Icons.people_outline_rounded,
                label: 'Список',
                selected: view == FamilyView.list,
                onTap: () => onChanged(FamilyView.list),
              ),
              _segment(
                tokens: tokens,
                key: const Key('family-view-tree'),
                icon: Icons.account_tree_outlined,
                label: 'Дерево',
                selected: view == FamilyView.tree,
                onTap: () => onChanged(FamilyView.tree),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment({
    required RodnyaDesignTokens tokens,
    required Key key,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: selected ? tokens.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? tokens.accentInk : tokens.inkMuted,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: AppTheme.sans(
                    color: selected ? tokens.accentInk : tokens.inkMuted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
