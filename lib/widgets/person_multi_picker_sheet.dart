import 'package:flutter/material.dart';

import '../models/family_person.dart';
import '../theme/app_theme.dart';

/// Searchable, virtualized fullscreen picker for selecting an
/// arbitrary set of people from the tree. Replaces the flat
/// `FilterChip` Wrap that didn't scale past ~30 people (and would
/// drown the user once a tree hits 200+).
///
/// Push via [show] — returns the new `Set<String>` personIds the user
/// confirmed, or null if they cancelled. Backbone of the audience
/// picker's "Отдельные ветки" advanced flow; can be reused later
/// for the Phase-2 graphical tree-picker as the list-mode fallback.
class PersonMultiPickerSheet extends StatefulWidget {
  const PersonMultiPickerSheet({
    super.key,
    required this.people,
    required this.initialSelection,
    this.title = 'Выберите людей',
  });

  final List<FamilyPerson> people;
  final Set<String> initialSelection;
  final String title;

  static Future<Set<String>?> show(
    BuildContext context, {
    required List<FamilyPerson> people,
    required Set<String> initialSelection,
    String title = 'Выберите людей',
  }) {
    return Navigator.of(context, rootNavigator: true).push<Set<String>>(
      MaterialPageRoute<Set<String>>(
        fullscreenDialog: true,
        builder: (_) => PersonMultiPickerSheet(
          people: people,
          initialSelection: initialSelection,
          title: title,
        ),
      ),
    );
  }

  @override
  State<PersonMultiPickerSheet> createState() => _PersonMultiPickerSheetState();
}

class _PersonMultiPickerSheetState extends State<PersonMultiPickerSheet> {
  late Set<String> _selected;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelection);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Filtered + ordered list:
  /// - Selected items float to the top (so the user always sees who's
  ///   already in the audience without scrolling).
  /// - Search query narrows by name (case-insensitive substring match).
  List<FamilyPerson> _visiblePeople() {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.people
        : widget.people.where(
            (p) => p.displayName.toLowerCase().contains(q),
          ).toList();
    final selectedFirst = <FamilyPerson>[];
    final rest = <FamilyPerson>[];
    for (final p in filtered) {
      if (_selected.contains(p.id)) {
        selectedFirst.add(p);
      } else {
        rest.add(p);
      }
    }
    return <FamilyPerson>[...selectedFirst, ...rest];
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAllVisible() {
    setState(() {
      for (final p in _visiblePeople()) {
        _selected.add(p.id);
      }
    });
  }

  void _clearAll() {
    setState(() => _selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    final visible = _visiblePeople();

    return Scaffold(
      backgroundColor: tokens.bgBase,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text('Сбросить'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Поиск по имени',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить поиск',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: tokens.surfaceStrong,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusMd),
                  borderSide: BorderSide(color: tokens.surfaceLine),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.radiusMd),
                  borderSide: BorderSide(color: tokens.surfaceLine),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Показано ${visible.length} · выбрано ${_selected.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.inkSecondary,
                    ),
                  ),
                ),
                if (visible.isNotEmpty)
                  TextButton(
                    onPressed: _selectAllVisible,
                    child: const Text('Выбрать всех'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _query.isEmpty
                            ? 'В дереве пока нет людей.'
                            : 'Никого не нашли по запросу «$_query».',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.inkSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    // ListView.builder lazily builds rows — handles
                    // 200+ people without rendering them all upfront,
                    // which is the whole point of this rework.
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final p = visible[index];
                      final isSelected = _selected.contains(p.id);
                      return _PersonRow(
                        person: p,
                        isSelected: isSelected,
                        onTap: () => _toggle(p.id),
                        tokens: tokens,
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  child: Text(
                    _selected.isEmpty
                        ? 'Готово'
                        : 'Готово (${_selected.length})',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.isSelected,
    required this.onTap,
    required this.tokens,
  });

  final FamilyPerson person;
  final bool isSelected;
  final VoidCallback onTap;
  final RodnyaDesignTokens tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: isSelected ? tokens.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isSelected
                    ? tokens.accent.withValues(alpha: 0.32)
                    : tokens.surfaceStrong,
                child: Text(
                  person.initials,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isSelected ? tokens.accent : tokens.inkSecondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  person.displayName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: tokens.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? tokens.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected ? tokens.accent : tokens.surfaceLine,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check, size: 15, color: tokens.accentInk)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
