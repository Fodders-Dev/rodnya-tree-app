// Profile Phase 2b-1 (2026-05-29): «Когда сделано фото?» picker.
//
// Q8 (locked): sort фото по dateTaken, не дате загрузки. EXIF auto-
// extract отложен (нет exif-пакета) — это ручной MVP: точная дата /
// год / десятилетие / «не знаю». Пишет dateTaken (ISO) + accuracy
// ('exact' | 'year' | 'decade' | null) в photo-блок.

import '../utils/genealogy_dates.dart';
import 'package:flutter/material.dart';

class PhotoDateResult {
  const PhotoDateResult({this.dateTaken, this.accuracy});

  /// ISO8601 (Jan 1 of year/decade for approximate), or null for «не знаю».
  final String? dateTaken;

  /// 'exact' | 'year' | 'decade' | null
  final String? accuracy;
}

/// Shows the photo-date picker. Returns null if dismissed without choice.
Future<PhotoDateResult?> showPhotoDatePickerSheet(
  BuildContext context, {
  required int currentYear,
}) {
  return showModalBottomSheet<PhotoDateResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return _PhotoDateSheet(currentYear: currentYear);
    },
  );
}

enum _Mode { root, year, decade }

class _PhotoDateSheet extends StatefulWidget {
  const _PhotoDateSheet({required this.currentYear});
  final int currentYear;

  @override
  State<_PhotoDateSheet> createState() => _PhotoDateSheetState();
}

class _PhotoDateSheetState extends State<_PhotoDateSheet> {
  _Mode _mode = _Mode.root;

  void _pop(PhotoDateResult result) => Navigator.of(context).pop(result);

  Future<void> _pickExact() async {
    final now = DateTime(widget.currentYear, 6, 15);
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: kGenealogyFirstDate,
      lastDate: DateTime(widget.currentYear, 12, 31),
      helpText: 'Когда сделано фото',
    );
    if (picked == null) return;
    _pop(PhotoDateResult(
      dateTaken: picked.toIso8601String(),
      accuracy: 'exact',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Когда сделано фото?',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (_mode == _Mode.root) ..._buildRoot(theme),
            if (_mode == _Mode.year) _buildYearList(theme),
            if (_mode == _Mode.decade) _buildDecadeChips(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRoot(ThemeData theme) {
    return [
      _option(
        key: 'photo-date-exact',
        icon: Icons.event_rounded,
        label: 'Точная дата',
        onTap: _pickExact,
      ),
      _option(
        key: 'photo-date-year',
        icon: Icons.calendar_today_rounded,
        label: 'Примерный год',
        onTap: () => setState(() => _mode = _Mode.year),
      ),
      _option(
        key: 'photo-date-decade',
        icon: Icons.history_rounded,
        label: 'Десятилетие',
        onTap: () => setState(() => _mode = _Mode.decade),
      ),
      _option(
        key: 'photo-date-unknown',
        icon: Icons.help_outline_rounded,
        label: 'Не знаю',
        onTap: () => _pop(const PhotoDateResult()),
      ),
    ];
  }

  Widget _option({
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      key: Key(key),
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }

  Widget _buildYearList(ThemeData theme) {
    return SizedBox(
      height: 280,
      child: ListView.builder(
        itemCount: widget.currentYear - 1900 + 1,
        itemBuilder: (_, i) {
          final year = widget.currentYear - i;
          return ListTile(
            key: Key('photo-year-$year'),
            dense: true,
            title: Text('$year'),
            onTap: () => _pop(PhotoDateResult(
              dateTaken: DateTime(year).toIso8601String(),
              accuracy: 'year',
            )),
          );
        },
      ),
    );
  }

  Widget _buildDecadeChips(ThemeData theme) {
    final decades = <int>[];
    for (var d = 1900; d <= widget.currentYear; d += 10) {
      decades.add(d);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in decades.reversed)
          ActionChip(
            key: Key('photo-decade-$d'),
            label: Text('$d-е'),
            onPressed: () => _pop(PhotoDateResult(
              dateTaken: DateTime(d).toIso8601String(),
              accuracy: 'decade',
            )),
          ),
      ],
    );
  }
}

/// Human label for a stored dateTaken + accuracy (for the photo block).
String? formatPhotoDate(String? dateTaken, String? accuracy) {
  if (dateTaken == null || dateTaken.isEmpty) return null;
  final dt = DateTime.tryParse(dateTaken);
  if (dt == null) return null;
  switch (accuracy) {
    case 'decade':
      return '${(dt.year ~/ 10) * 10}-е';
    case 'year':
      return '${dt.year}';
    case 'exact':
      return '${dt.day.toString().padLeft(2, '0')}.'
          '${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    default:
      return '${dt.year}';
  }
}
