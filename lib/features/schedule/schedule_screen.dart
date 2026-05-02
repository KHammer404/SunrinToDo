import 'package:flutter/material.dart';
import 'package:sunrintodo/core/data/school_events_2026.dart';
import 'package:sunrintodo/core/services/neis_service.dart';
import 'package:table_calendar/table_calendar.dart';

enum _ScheduleSource { school, neis }

class _ScheduleEvent {
  final String date;
  final String title;
  final String? detail;
  final String? badge;
  final _ScheduleSource source;

  const _ScheduleEvent({
    required this.date,
    required this.title,
    required this.source,
    this.detail,
    this.badge,
  });

  bool get isSchool => source == _ScheduleSource.school;
}

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _focusedDay = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  Map<String, List<_ScheduleEvent>> _events = {};
  bool _loading = true;
  String? _noticeMessage;

  @override
  void initState() {
    super.initState();
    _loadMonth(_focusedDay);
  }

  String _dateKey(DateTime date) =>
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

  String? _normalizedText(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _badgeLabel(SchoolSchedule event) {
    final dayType = _normalizedText(event.dayType);
    if (dayType == null || dayType == '수업일') {
      return null;
    }
    return dayType;
  }

  String _neisNoticeMessage(NeisException error) =>
      '학교 PDF 기준 학사일정은 계속 표시됩니다.\n${error.message}';

  void _addEvent(
    Map<String, List<_ScheduleEvent>> result,
    _ScheduleEvent event,
  ) {
    final entries = result.putIfAbsent(event.date, () => []);
    final exists = entries.any(
      (existing) =>
          existing.title == event.title &&
          existing.detail == event.detail &&
          existing.badge == event.badge &&
          existing.source == event.source,
    );

    if (!exists) {
      entries.add(event);
    }
  }

  bool _hasSchoolEventOnDate(
    Map<String, List<_ScheduleEvent>> result,
    String date,
  ) {
    return (result[date] ?? const <_ScheduleEvent>[]).any(
      (event) => event.isSchool,
    );
  }

  Map<String, List<_ScheduleEvent>> _schoolEventsForMonth(DateTime month) {
    final prefix = '${month.year}${month.month.toString().padLeft(2, '0')}';
    final result = <String, List<_ScheduleEvent>>{};

    for (final event in schoolEvents2026.where(
      (entry) => entry.date.startsWith(prefix),
    )) {
      _addEvent(
        result,
        _ScheduleEvent(
          date: event.date,
          title: event.title,
          source: _ScheduleSource.school,
        ),
      );
    }

    return result;
  }

  bool _shouldSkipNeisEvent(
    Map<String, List<_ScheduleEvent>> result,
    SchoolSchedule event,
  ) {
    if (_normalizedText(event.eventName) == null) {
      return true;
    }
    if (event.eventName.contains('토요휴업일')) {
      return true;
    }
    if (_hasSchoolEventOnDate(result, event.date)) {
      return true;
    }
    return false;
  }

  void _mergeNeisEvents(
    Map<String, List<_ScheduleEvent>> result,
    List<SchoolSchedule> schedules,
  ) {
    for (final event in schedules) {
      if (_shouldSkipNeisEvent(result, event)) {
        continue;
      }

      _addEvent(
        result,
        _ScheduleEvent(
          date: event.date,
          title: event.eventName,
          detail: _normalizedText(event.eventContent),
          badge: _badgeLabel(event),
          source: _ScheduleSource.neis,
        ),
      );
    }
  }

  Future<void> _loadMonth(DateTime month) async {
    setState(() => _loading = true);

    final events = _schoolEventsForMonth(month);
    String? noticeMessage;

    try {
      final schedules = await NeisService.getMonthSchedule(
        month.year,
        month.month,
      );
      _mergeNeisEvents(events, schedules);
    } on NeisException catch (error) {
      noticeMessage = _neisNoticeMessage(error);
    }

    if (mounted) {
      setState(() {
        _events = events;
        _noticeMessage = noticeMessage;
        _loading = false;
      });
    }
  }

  DateTime get _firstDay => DateTime(DateTime.now().year - 1, 1);

  DateTime get _lastDay => DateTime(DateTime.now().year + 2, 12, 31);

  List<_ScheduleEvent> _eventsForDay(DateTime day) =>
      _events[_dateKey(day)] ?? [];

  int _weeksInMonth(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final startOffset = (first.weekday - 1) % 7;
    return ((startOffset + last.day) / 7).ceil();
  }

  Color _eventColor(ColorScheme colorScheme, _ScheduleEvent event) {
    if (event.isSchool) {
      return colorScheme.primary;
    }
    return event.badge == null ? colorScheme.secondary : colorScheme.tertiary;
  }

  String? _trailingLabel(_ScheduleEvent event) {
    if (event.isSchool) {
      return null;
    }
    return event.badge ?? 'NEIS';
  }

  Widget _dayCell(
    BuildContext context,
    DateTime day,
    bool isToday,
    bool isSelected,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final events = _eventsForDay(day);
    final isWeekend = day.weekday == 6 || day.weekday == 7;

    final numColor = isSelected
        ? Colors.white
        : isToday
        ? colorScheme.primary
        : isWeekend
        ? Colors.red
        : colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Container(
          width: 30,
          height: 30,
          decoration: isSelected
              ? BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                )
              : isToday
              ? BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                )
              : null,
          child: Center(
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                color: numColor,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
        ...events.take(2).map((event) {
          final color = _eventColor(colorScheme, event);
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              event.title,
              style: TextStyle(
                fontSize: 8,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );
        }),
      ],
    );
  }

  String get _selectedDateLabel {
    if (_selectedDay == null) {
      return '';
    }
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${_selectedDay!.month}월 ${_selectedDay!.day}일 (${weekdays[_selectedDay!.weekday - 1]})';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('학사일정'), centerTitle: false),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final weeks = _weeksInMonth(_focusedDay);
          final noticeHeightReserve = _noticeMessage == null ? 0.0 : 96.0;
          const calendarChromeHeightReserve = 96.0;
          final rowHeight = _selectedDay == null
              ? ((constraints.maxHeight -
                            noticeHeightReserve -
                            calendarChromeHeightReserve) /
                        weeks)
                    .clamp(52.0, 120.0)
              : 60.0;

          return Column(
            children: [
              if (_noticeMessage != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _noticeMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              TableCalendar<_ScheduleEvent>(
                firstDay: _firstDay,
                lastDay: _lastDay,
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: 'Month'},
                startingDayOfWeek: StartingDayOfWeek.monday,
                rowHeight: rowHeight,
                eventLoader: _eventsForDay,
                onDaySelected: (selected, focused) {
                  setState(() {
                    _focusedDay = focused;
                    _selectedDay = isSameDay(_selectedDay, selected)
                        ? null
                        : selected;
                  });
                },
                onPageChanged: (focused) {
                  setState(() {
                    _focusedDay = focused;
                    _selectedDay = null;
                  });
                  _loadMonth(focused);
                },
                calendarStyle: const CalendarStyle(
                  outsideDaysVisible: false,
                  markersMaxCount: 0,
                ),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, _) =>
                      _dayCell(context, day, false, false),
                  todayBuilder: (context, day, _) =>
                      _dayCell(context, day, true, false),
                  selectedBuilder: (context, day, _) =>
                      _dayCell(context, day, false, true),
                ),
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                ),
              ),
              if (_selectedDay != null) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedDateLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _selectedDay = null),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          children: _eventsForDay(_selectedDay!).isEmpty
                              ? [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Text(
                                      '학사일정 없음',
                                      style: TextStyle(color: Colors.grey[400]),
                                    ),
                                  ),
                                ]
                              : _eventsForDay(_selectedDay!).map((event) {
                                  final color = _eventColor(colorScheme, event);
                                  final trailingLabel = _trailingLabel(event);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 3,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.7),
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                event.title,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                ),
                                              ),
                                              if (event.detail != null) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  event.detail!,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[500],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (trailingLabel != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: color.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              trailingLabel,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: color,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                        ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
