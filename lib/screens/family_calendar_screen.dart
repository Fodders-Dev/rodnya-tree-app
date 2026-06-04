// Calendar v1 (calendar/A): «Календарь» — a month grid of the family's
// dates + holidays. Pure client-side: every date comes from
// EventService.getEventsForMonth (no backend). table_calendar handles
// leap-years / weekday layout / month navigation; we feed it events via
// eventLoader and colour the day-markers by category. Tap a day → the
// list of that day's events (shared EventCard).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/app_event.dart';
import '../providers/tree_provider.dart';
import '../services/event_service.dart';
import '../theme/app_theme.dart';
import '../utils/moon_phase.dart';
import '../widgets/event_card.dart';

class FamilyCalendarScreen extends StatefulWidget {
  const FamilyCalendarScreen({
    super.key,
    this.serviceOverride,
    this.treeId,
    this.initialMonth,
  });

  /// Test seams — production builds an EventService and reads the tree
  /// from the TreeProvider.
  final EventService? serviceOverride;
  final String? treeId;
  final DateTime? initialMonth;

  @override
  State<FamilyCalendarScreen> createState() => _FamilyCalendarScreenState();
}

class _FamilyCalendarScreenState extends State<FamilyCalendarScreen> {
  late final EventService _service = widget.serviceOverride ?? EventService();
  String? _treeId;
  bool _loading = true;
  bool _loadFailed = false;
  late DateTime _focusedDay = widget.initialMonth ?? DateTime.now();
  late DateTime _selectedDay = widget.initialMonth ?? DateTime.now();
  Map<DateTime, List<AppEvent>> _eventsByDay = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _treeId = widget.treeId;
      if (_treeId == null && mounted) {
        try {
          _treeId = context.read<TreeProvider>().selectedTreeId;
        } catch (_) {
          _treeId = null;
        }
      }
      _loadMonth(_focusedDay);
    });
  }

  DateTime _dayKey(DateTime day) => DateTime(day.year, day.month, day.day);

  bool get _hasTree => _treeId != null && _treeId!.trim().isNotEmpty;

  Future<void> _loadMonth(DateTime month) async {
    final treeId = _treeId;
    if (treeId == null || treeId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final events =
          await _service.getEventsForMonth(treeId, month.year, month.month);
      if (!mounted) return;
      final grouped = <DateTime, List<AppEvent>>{};
      for (final e in events) {
        grouped.putIfAbsent(_dayKey(e.date), () => <AppEvent>[]).add(e);
      }
      setState(() {
        _eventsByDay = grouped;
        _loading = false;
      });
    } catch (_) {
      // Surface the failure instead of showing an empty month (CP-2).
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  List<AppEvent> _eventsFor(DateTime day) =>
      _eventsByDay[_dayKey(day)] ?? const <AppEvent>[];

  Color _markerColor(
    AppEventType type,
    ThemeData theme,
    RodnyaDesignTokens tokens,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    switch (type) {
      case AppEventType.russianHoliday:
        // Flag red, lifted for dark backgrounds.
        return isDark ? const Color(0xFFE57373) : const Color(0xFFD64545);
      case AppEventType.orthodoxHoliday:
        // Soft violet, lifted for dark backgrounds.
        return isDark ? const Color(0xFFB39DDB) : const Color(0xFF8E7CC3);
      default:
        return tokens.accent; // family — on-brand accent
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final selectedEvents = _eventsFor(_selectedDay);

    return Scaffold(
      appBar: AppBar(title: const Text('Календарь')),
      body: Column(
        children: [
          _buildCalendar(theme, tokens),
          _buildMoonLegend(theme, tokens),
          const Divider(height: 1),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!_hasTree)
            Expanded(child: _buildNoTree(theme, tokens))
          else if (_loadFailed)
            Expanded(child: _buildError(theme, tokens))
          else ...[
            _buildMoonTip(theme, tokens, _selectedDay),
            Expanded(
              child: selectedEvents.isEmpty
                  ? _buildDayEmpty(theme, tokens)
                  : _buildDayList(selectedEvents),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCalendar(ThemeData theme, RodnyaDesignTokens tokens) {
    return TableCalendar<AppEvent>(
      locale: 'ru_RU',
      firstDay: DateTime.utc(2000, 1, 1),
      lastDay: DateTime.utc(2100, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      eventLoader: _eventsFor,
      startingDayOfWeek: StartingDayOfWeek.monday,
      availableGestures: AvailableGestures.horizontalSwipe,
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        titleTextStyle: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'Lora',
              fontWeight: FontWeight.w700,
              color: tokens.ink,
            ) ??
            TextStyle(color: tokens.ink),
        leftChevronIcon: Icon(Icons.chevron_left, color: tokens.ink),
        rightChevronIcon: Icon(Icons.chevron_right, color: tokens.ink),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle:
            TextStyle(color: tokens.inkMuted, fontWeight: FontWeight.w600),
        weekendStyle:
            TextStyle(color: tokens.inkMuted, fontWeight: FontWeight.w600),
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        isTodayHighlighted: true,
        // Force on-brand, theme-aware day text — Material defaults didn't
        // track the warm palette and the number on the green selected
        // circle was low-contrast / unreadable in dark mode.
        defaultTextStyle: TextStyle(color: tokens.ink),
        weekendTextStyle: TextStyle(color: tokens.ink),
        todayTextStyle:
            TextStyle(color: tokens.ink, fontWeight: FontWeight.w700),
        selectedTextStyle:
            TextStyle(color: tokens.accentInk, fontWeight: FontWeight.w700),
        todayDecoration: BoxDecoration(
          color: tokens.accent.withValues(alpha: 0.28),
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: tokens.accent,
          shape: BoxShape.circle,
        ),
      ),
      calendarBuilders: CalendarBuilders<AppEvent>(
        // Moon glyph (C): only on the ~4 principal-phase days a month, so
        // the grid isn't flooded. Returning null on other days falls back
        // to table_calendar's default cell.
        defaultBuilder: (context, day, focusedDay) {
          if (!isPrincipalMoonDay(day)) return null;
          return Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${day.day}',
                style: theme.textTheme.bodyMedium?.copyWith(color: tokens.ink),
              ),
              Positioned(
                top: 1,
                right: 2,
                child: Text(
                  moonPhaseFor(day).glyph,
                  style: const TextStyle(fontSize: 9),
                ),
              ),
            ],
          );
        },
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in events.take(3))
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: _markerColor(e.type, theme, tokens),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
      },
      onPageChanged: (focusedDay) {
        _focusedDay = focusedDay;
        _loadMonth(focusedDay);
      },
    );
  }

  /// Light legend for the moon glyphs — the four principal phases.
  Widget _buildMoonLegend(ThemeData theme, RodnyaDesignTokens tokens) {
    const phases = <MoonPhase>[
      MoonPhase.newMoon,
      MoonPhase.firstQuarter,
      MoonPhase.fullMoon,
      MoonPhase.lastQuarter,
    ];
    final style = theme.textTheme.labelSmall?.copyWith(color: tokens.inkMuted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 2,
        alignment: WrapAlignment.center,
        children: [
          for (final p in phases) Text('${p.glyph} ${p.label}', style: style),
        ],
      ),
    );
  }

  /// Compact warm strip: the selected day's moon phase + a folk gardening
  /// tip (for the dacha crowd). One line — kept deliberately light.
  Widget _buildMoonTip(
    ThemeData theme,
    RodnyaDesignTokens tokens,
    DateTime day,
  ) {
    final phase = moonPhaseFor(day);
    return Container(
      key: const Key('moon-tip'),
      margin: EdgeInsets.fromLTRB(
        tokens.space12,
        tokens.space12,
        tokens.space12,
        tokens.space4,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space12,
        vertical: tokens.space8,
      ),
      decoration: BoxDecoration(
        color: tokens.warmSoft,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Row(
        children: [
          Text(phase.glyph, style: const TextStyle(fontSize: 18)),
          SizedBox(width: tokens.space8),
          Expanded(
            child: Text(
              gardeningTip(phase),
              style: theme.textTheme.bodySmall?.copyWith(
                color: tokens.ink,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayList(List<AppEvent> events) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
      itemCount: events.length,
      itemBuilder: (_, i) => Padding(
        key: Key('calendar-day-event-$i'),
        padding: const EdgeInsets.only(bottom: 8),
        child: EventCard(
          event: events[i],
          width: double.infinity,
          // Person-linked events ignore this and open the profile; a
          // holiday has no person, so the tap shows its info instead.
          onTap: () => _showHolidayInfo(events[i]),
        ),
      ),
    );
  }

  /// Bottom-sheet with a short, factual description of a holiday. Only
  /// shown for events that carry a description (holidays); family events
  /// never reach here (they open the profile instead).
  void _showHolidayInfo(AppEvent event) {
    final description = event.description;
    if (description == null || description.isEmpty) return;
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final dateLabel = DateFormat('d MMMM', 'ru').format(event.date);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          key: const Key('holiday-info-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(event.icon, color: tokens.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      event.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontFamily: 'Lora',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${event.categoryLabel} · $dateLabel',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tokens.inkMuted,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                description,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Center the placeholder, but scroll it if the remaining area below the
  // grid is short (small screens / landscape) so it never overflows.
  Widget _scrollSafeCenter(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildNoTree(ThemeData theme, RodnyaDesignTokens tokens) {
    return _scrollSafeCenter(
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined, size: 48, color: tokens.inkMuted),
            const SizedBox(height: 12),
            Text(
              'Выберите дерево',
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'Lora',
                fontWeight: FontWeight.w700,
                color: tokens.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Чтобы увидеть даты семьи, выберите семейное дерево на главной.',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: tokens.inkMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              key: const Key('calendar-no-tree-cta'),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('На главную'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme, RodnyaDesignTokens tokens) {
    return _scrollSafeCenter(
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: tokens.inkMuted),
            const SizedBox(height: 12),
            Text(
              'Не удалось загрузить',
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'Lora',
                fontWeight: FontWeight.w700,
                color: tokens.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Проверьте соединение и попробуйте ещё раз.',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: tokens.inkMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              key: const Key('calendar-retry'),
              onPressed: () => _loadMonth(_focusedDay),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayEmpty(ThemeData theme, RodnyaDesignTokens tokens) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'В этот день событий нет',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: tokens.inkMuted,
          ),
        ),
      ),
    );
  }
}
