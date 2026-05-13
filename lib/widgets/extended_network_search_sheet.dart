import 'package:flutter/material.dart';

import '../backend/models/extended_network_slice.dart';

/// Phase 4 chunk 4b (PHASE-4-PROPOSAL.md §2.4 + DECISIONS.md
/// 2026-05-12 Q5.A): search sheet для extended-network view.
///
/// Client-side filter по `slice.graphPersons` (≤ 1000 cap гарантирует
/// no pagination concerns). На tap result — sheet closes + host
/// callback `onPersonSelected(graphPersonId)` решает routing
/// (foreign sheet либо own selection + canvas recenter).
///
/// Pattern parallel `extended_network_filter_sheet.dart` — same
/// DraggableScrollableSheet conventions, drag handle, ListView.
class ExtendedNetworkSearchSheet extends StatefulWidget {
  const ExtendedNetworkSearchSheet({
    required this.slice,
    required this.onPersonSelected,
    super.key,
  });

  /// Slice with `graphPersons` для client-side filter. Sparse
  /// `ownerMap` indicates foreign nodes (UI shows chip).
  final ExtendedNetworkSlice slice;

  /// Called с graphPerson.id (= identityId) when user taps a
  /// result. Sheet auto-closes via Navigator.pop before invoking.
  /// Host route'ит на foreign sheet либо own selection.
  final ValueChanged<String> onPersonSelected;

  @override
  State<ExtendedNetworkSearchSheet> createState() =>
      _ExtendedNetworkSearchSheetState();
}

class _ExtendedNetworkSearchSheetState
    extends State<ExtendedNetworkSearchSheet> {
  late final TextEditingController _controller;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() {
      setState(() {
        _query = _controller.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<ExtendedNetworkPerson> get _filtered {
    if (_query.isEmpty) return widget.slice.graphPersons;
    return widget.slice.graphPersons
        .where(
          (p) => (p.name ?? '').toLowerCase().contains(_query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return _SearchSheetBody(
          controller: _controller,
          filtered: _filtered,
          slice: widget.slice,
          scrollController: scrollController,
          onPersonSelected: widget.onPersonSelected,
        );
      },
    );
  }
}

class _SearchSheetBody extends StatelessWidget {
  const _SearchSheetBody({
    required this.controller,
    required this.filtered,
    required this.slice,
    required this.scrollController,
    required this.onPersonSelected,
  });

  final TextEditingController controller;
  final List<ExtendedNetworkPerson> filtered;
  final ExtendedNetworkSlice slice;
  final ScrollController scrollController;
  final ValueChanged<String> onPersonSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Поиск в расширенной сети',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Имя или фамилия',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Очистить',
                        onPressed: controller.clear,
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(query: controller.text)
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final person = filtered[index];
                      final isForeign = slice.isForeignNode(person.id);
                      return _ResultTile(
                        person: person,
                        isForeign: isForeign,
                        onTap: () {
                          Navigator.of(context).pop();
                          onPersonSelected(person.id);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.person,
    required this.isForeign,
    required this.onTap,
  });

  final ExtendedNetworkPerson person;
  final bool isForeign;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lifeDates = _lifeDates(person);
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: isForeign
            ? theme.colorScheme.surfaceContainerHigh
            : theme.colorScheme.primaryContainer,
        backgroundImage:
            person.photoUrl != null && person.photoUrl!.isNotEmpty
                ? NetworkImage(person.photoUrl!)
                : null,
        child: person.photoUrl == null || person.photoUrl!.isEmpty
            ? Text(
                _initialsOf(person.name ?? '?'),
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
      title: Text(
        person.name ?? 'Без имени',
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Row(
        children: [
          if (lifeDates != null)
            Text(
              lifeDates,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (isForeign) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'не моя',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String? _lifeDates(ExtendedNetworkPerson p) {
    final birth = p.birthDate?.substring(0, 4);
    final death = p.deathDate?.substring(0, 4);
    if (birth == null && death == null) return null;
    return '${birth ?? '?'} — ${death ?? (p.isAlive ? '' : '?')}'.trim();
  }

  static String _initialsOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasQuery = query.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off_rounded : Icons.search_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? 'Ничего не найдено'
                  : 'Начните вводить имя',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper для host — opens sheet через showModalBottomSheet.
Future<void> showExtendedNetworkSearchSheet(
  BuildContext context, {
  required ExtendedNetworkSlice slice,
  required ValueChanged<String> onPersonSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return ExtendedNetworkSearchSheet(
        slice: slice,
        onPersonSelected: onPersonSelected,
      );
    },
  );
}
