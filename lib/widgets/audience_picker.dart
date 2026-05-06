import 'package:flutter/material.dart';

import '../models/circle.dart';
import '../theme/app_theme.dart';

/// Audience picker for the create-post screen. Was a flat list of every
/// circle (всё дерево + избранные + N веток + N предков) which on a
/// medium tree blew up to 14+ rows of identical-looking radios — pure
/// paralysis. Reshaped into three collapsible sections + a search
/// field so the common case (Всё дерево / Избранные) is one tap and
/// the long auto-generated branch / ancestor lists are tucked away
/// until the user actively wants them.
class AudiencePicker extends StatefulWidget {
  const AudiencePicker({
    super.key,
    required this.circles,
    required this.selectedCircleId,
    required this.onChanged,
    this.isLoading = false,
    this.isUnavailable = false,
    this.isFriendsTree = false,
    this.onRetry,
  });

  final List<FamilyCircle> circles;
  final String? selectedCircleId;
  final ValueChanged<String?> onChanged;
  final bool isLoading;
  final bool isUnavailable;
  final bool isFriendsTree;
  final VoidCallback? onRetry;

  @override
  State<AudiencePicker> createState() => _AudiencePickerState();
}

class _AudiencePickerState extends State<AudiencePicker> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  // Per-group expanded state. Универсальные always open (and not in this
  // map). Branches / Ancestors collapsed by default; opened automatically
  // if the currently-selected circle lives in that group.
  final Map<_GroupKey, bool> _expanded = {
    _GroupKey.branches: false,
    _GroupKey.ancestors: false,
  };

  @override
  void initState() {
    super.initState();
    _autoExpandSelectedGroup();
  }

  @override
  void didUpdateWidget(covariant AudiencePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCircleId != widget.selectedCircleId ||
        oldWidget.circles != widget.circles) {
      _autoExpandSelectedGroup();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _autoExpandSelectedGroup() {
    final selectedId = widget.selectedCircleId;
    if (selectedId == null) return;
    final selected = widget.circles.firstWhere(
      (c) => c.id == selectedId,
      orElse: () => widget.circles.isNotEmpty
          ? widget.circles.first
          : _placeholderCircle(),
    );
    final group = _groupFor(selected);
    if (group == _GroupKey.branches || group == _GroupKey.ancestors) {
      _expanded[group] = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final selectedValue = _resolveSelectedValue();
    final hasChoices = widget.circles.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasChoices && widget.circles.length > 4) ...[
          _SearchField(
            controller: _searchController,
            tokens: tokens,
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: 10),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.surfaceLine),
          ),
          child: hasChoices
              ? _buildGroupedSections(tokens, selectedValue)
              : _FallbackAudienceTile(
                  isFriendsTree: widget.isFriendsTree,
                  selected: selectedValue == '',
                ),
        ),
        if (widget.isLoading || widget.isUnavailable) ...[
          const SizedBox(height: 10),
          _StatusRow(
            theme: theme,
            isLoading: widget.isLoading,
            onRetry: widget.onRetry,
          ),
        ],
      ],
    );
  }

  Widget _buildGroupedSections(
    RodnyaDesignTokens tokens,
    String? selectedValue,
  ) {
    final groups = _groupCircles(widget.circles);
    final query = _query.toLowerCase();
    final isSearching = query.isNotEmpty;

    final orderedKeys = [
      _GroupKey.universal,
      _GroupKey.branches,
      _GroupKey.ancestors,
    ];

    final sections = <Widget>[];
    for (var i = 0; i < orderedKeys.length; i++) {
      final key = orderedKeys[i];
      final groupCircles = groups[key] ?? const <FamilyCircle>[];
      if (groupCircles.isEmpty) continue;

      final visible = isSearching
          ? groupCircles
              .where((c) => c.name.toLowerCase().contains(query))
              .toList()
          : groupCircles;
      if (isSearching && visible.isEmpty) continue;

      final isUniversal = key == _GroupKey.universal;
      final isOpen = isUniversal || isSearching || (_expanded[key] ?? false);

      sections.add(
        _GroupSection(
          tokens: tokens,
          title: _groupTitle(key),
          subtitle: _groupSubtitle(key, groupCircles.length),
          icon: _groupIcon(key),
          isOpen: isOpen,
          collapsible: !isUniversal && !isSearching,
          onToggle: isUniversal || isSearching
              ? null
              : () => setState(
                    () => _expanded[key] = !(_expanded[key] ?? false),
                  ),
          tiles: [
            for (var j = 0; j < visible.length; j++) ...[
              _AudienceOptionTile(
                circle: visible[j],
                selected: visible[j].id == selectedValue,
                enabled: !widget.isLoading,
                onTap: () => widget.onChanged(visible[j].id),
              ),
              if (j != visible.length - 1)
                Divider(
                  height: 1,
                  indent: 58,
                  color: tokens.surfaceLine,
                ),
            ],
          ],
        ),
      );
      if (i != orderedKeys.length - 1) {
        sections.add(Divider(height: 1, color: tokens.surfaceLine));
      }
    }

    if (sections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Ничего не нашли по запросу «$_query».',
          style: TextStyle(color: tokens.inkSecondary),
        ),
      );
    }

    return Column(children: sections);
  }

  String? _resolveSelectedValue() {
    if (widget.circles.isEmpty) {
      return '';
    }
    final selected = widget.selectedCircleId;
    if (selected != null &&
        widget.circles.any((circle) => circle.id == selected)) {
      return selected;
    }
    for (final circle in widget.circles) {
      if (circle.isAllTree) {
        return circle.id;
      }
    }
    return widget.circles.first.id;
  }

  static _GroupKey _groupFor(FamilyCircle circle) {
    switch (circle.kind) {
      case FamilyCircleKind.allTree:
      case FamilyCircleKind.favorites:
      case FamilyCircleKind.custom:
        return _GroupKey.universal;
      case FamilyCircleKind.descendantsOf:
      case FamilyCircleKind.pair:
        return _GroupKey.branches;
      case FamilyCircleKind.ancestorsOf:
        return _GroupKey.ancestors;
    }
  }

  static Map<_GroupKey, List<FamilyCircle>> _groupCircles(
    List<FamilyCircle> circles,
  ) {
    final map = <_GroupKey, List<FamilyCircle>>{
      _GroupKey.universal: [],
      _GroupKey.branches: [],
      _GroupKey.ancestors: [],
    };
    for (final c in circles) {
      map[_groupFor(c)]!.add(c);
    }
    // Inside универсальные: allTree first, then favorites, then custom.
    map[_GroupKey.universal]!.sort((a, b) {
      int rank(FamilyCircle c) => c.isAllTree
          ? 0
          : c.isFavorites
              ? 1
              : 2;
      return rank(a).compareTo(rank(b));
    });
    return map;
  }

  static String _groupTitle(_GroupKey key) {
    switch (key) {
      case _GroupKey.universal:
        return 'Главное';
      case _GroupKey.branches:
        return 'Ветви потомков';
      case _GroupKey.ancestors:
        return 'Линии предков';
    }
  }

  static String _groupSubtitle(_GroupKey key, int count) {
    switch (key) {
      case _GroupKey.universal:
        return 'Самые частые варианты';
      case _GroupKey.branches:
      case _GroupKey.ancestors:
        return '$count ${_branchWordForm(count)} · авто-сборка';
    }
  }

  static String _branchWordForm(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'вариант';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'варианта';
    }
    return 'вариантов';
  }

  static IconData _groupIcon(_GroupKey key) {
    switch (key) {
      case _GroupKey.universal:
        return Icons.star_outline_rounded;
      case _GroupKey.branches:
        return Icons.account_tree_outlined;
      case _GroupKey.ancestors:
        return Icons.history_edu_outlined;
    }
  }

  static FamilyCircle _placeholderCircle() {
    return FamilyCircle(
      id: '__placeholder__',
      treeId: '',
      kind: FamilyCircleKind.allTree,
      name: '',
      isSystem: true,
      memberCount: 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

enum _GroupKey { universal, branches, ancestors }

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.tokens,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isOpen,
    required this.collapsible,
    required this.onToggle,
    required this.tiles,
  });

  final RodnyaDesignTokens tokens;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isOpen;
  final bool collapsible;
  final VoidCallback? onToggle;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: collapsible ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: tokens.inkSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: tokens.inkSecondary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (collapsible)
                    AnimatedRotation(
                      turns: isOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: tokens.inkSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isOpen
              ? Column(children: tiles)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.tokens,
    required this.onChanged,
  });

  final TextEditingController controller;
  final RodnyaDesignTokens tokens;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Поиск по веткам',
        prefixIcon: Icon(Icons.search, color: tokens.inkSecondary),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Очистить поиск',
                icon: Icon(Icons.close, color: tokens.inkSecondary),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: tokens.surface.withValues(alpha: 0.88),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(color: tokens.surfaceLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(color: tokens.surfaceLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusMd),
          borderSide: BorderSide(color: tokens.accent),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.theme,
    required this.isLoading,
    required this.onRetry,
  });

  final ThemeData theme;
  final bool isLoading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
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
    );
  }
}

class _AudienceOptionTile extends StatelessWidget {
  const _AudienceOptionTile({
    required this.circle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final FamilyCircle circle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final accent = _accentFor(circle, tokens);
    final subtitle = _subtitleFor(circle);

    return Material(
      color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(tokens.radiusSm),
                ),
                child: Icon(_iconFor(circle), size: 20, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayName(circle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: tokens.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.inkSecondary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: selected ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? accent : tokens.surfaceLine,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 15, color: tokens.accentInk)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Inside the auto-generated branch / ancestor sections every name
  /// starts with "Ветка: " or "Предки: " — that prefix is now redundant
  /// (the section header already says it), so trim it for tile labels.
  String _displayName(FamilyCircle circle) {
    final name = circle.name;
    for (final prefix in const ['Ветка: ', 'Ветвь: ', 'Предки: ']) {
      if (name.startsWith(prefix)) {
        return name.substring(prefix.length);
      }
    }
    return name;
  }

  IconData _iconFor(FamilyCircle circle) {
    switch (circle.kind) {
      case FamilyCircleKind.allTree:
        return Icons.account_tree_outlined;
      case FamilyCircleKind.favorites:
        return Icons.favorite_border;
      case FamilyCircleKind.descendantsOf:
      case FamilyCircleKind.ancestorsOf:
        return Icons.alt_route_outlined;
      case FamilyCircleKind.pair:
        return Icons.people_outline;
      case FamilyCircleKind.custom:
        return Icons.group_work_outlined;
    }
  }

  Color _accentFor(FamilyCircle circle, RodnyaDesignTokens tokens) {
    switch (circle.kind) {
      case FamilyCircleKind.favorites:
        return tokens.warm;
      case FamilyCircleKind.descendantsOf:
      case FamilyCircleKind.ancestorsOf:
      case FamilyCircleKind.pair:
        return tokens.accentStrong;
      case FamilyCircleKind.allTree:
      case FamilyCircleKind.custom:
        return tokens.accent;
    }
  }

  String _subtitleFor(FamilyCircle circle) {
    final parts = <String>[
      _memberLabel(circle.memberCount),
      if ((circle.description ?? '').trim().isNotEmpty)
        circle.description!.trim()
      else if (circle.isAllTree)
        'все участники дерева'
      else if (circle.isFavorites)
        'самые близкие'
      else if (circle.isAuto)
        // Section header already conveys "ветви / предки" — keep tile
        // subtitle short.
        ''
      else if (circle.isSystem)
        'системный круг',
    ];
    return parts.where((s) => s.isNotEmpty).join(' · ');
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

class _FallbackAudienceTile extends StatelessWidget {
  const _FallbackAudienceTile({
    required this.isFriendsTree,
    required this.selected,
  });

  final bool isFriendsTree;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Icon(
              isFriendsTree
                  ? Icons.diversity_3_outlined
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
                  isFriendsTree ? 'Весь круг' : 'Всё дерево',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: tokens.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Круги пока недоступны, публикация останется внутри выбранного контекста.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.inkSecondary,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 10),
            Icon(Icons.check_circle, color: tokens.accent),
          ],
        ],
      ),
    );
  }
}
