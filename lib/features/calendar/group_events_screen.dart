import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sunrintodo/features/calendar/calendar_data_service.dart';
import 'package:sunrintodo/features/calendar/calendar_models.dart';

class GroupEventsScreen extends StatefulWidget {
  final String classId;
  final String name;
  final Color color;

  const GroupEventsScreen({
    super.key,
    required this.classId,
    required this.name,
    required this.color,
  });

  @override
  State<GroupEventsScreen> createState() => _GroupEventsScreenState();
}

class _GroupEventsScreenState extends State<GroupEventsScreen> {
  final _calendarDataService = CalendarDataService();

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Stream<List<CalendarEvent>> get _eventsStream =>
      _calendarDataService.watchSpaceEvents(uid: _uid, spaceId: widget.classId);

  List<CalendarEvent> _eventsForDay(List<CalendarEvent> all, DateTime day) =>
      calendarEventsForDay(all, day);

  int _weeksInMonth(DateTime month) => weeksInCalendarMonth(month);

  String get _selectedDateLabel {
    if (_selectedDay == null) return '';
    return formatSelectedCalendarDate(_selectedDay!);
  }

  bool _canModifyEvent(CalendarEvent event) {
    if (event.classId == 'personal') return event.createdBy == _uid;
    return event.classId == widget.classId;
  }

  String _actorLabel(String uid) {
    if (uid.isEmpty) return '알 수 없음';
    return uid == _uid ? '나' : uid;
  }

  String _permissionLabel(CalendarEvent event) {
    if (event.classId == 'personal') {
      return '개인 일정 · 작성자만 수정/삭제 가능';
    }
    return '학급 일정 · 학급 멤버는 수정/삭제 가능';
  }

  void _showEditEvent(CalendarEvent event) {
    final titleCtrl = TextEditingController(text: event.title);
    DateTime startDate = event.startDate;
    DateTime endDate = event.endDate;
    EventCategory category = event.category;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('일정 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '제목',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '캘린더',
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: widget.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(widget.name),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: EventCategory.values
                      .map(
                        (cat) => FilterChip(
                          label: Text(
                            cat.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: category == cat,
                          selectedColor: cat.color.withAlpha(75),
                          onSelected: (_) => setDialog(() => category = cat),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: startDate,
                            firstDate: DateTime(2026),
                            lastDate: DateTime(2028),
                          );
                          if (picked != null) {
                            setDialog(() {
                              startDate = picked;
                              if (endDate.isBefore(startDate)) {
                                endDate = startDate;
                              }
                            });
                          }
                        },
                        child: Text('${startDate.month}/${startDate.day}'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Text('~'),
                    ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: endDate,
                            firstDate: startDate,
                            lastDate: DateTime(2028),
                          );
                          if (picked != null) {
                            setDialog(() => endDate = picked);
                          }
                        },
                        child: Text('${endDate.month}/${endDate.day}'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                try {
                  await FirebaseFirestore.instance
                      .collection('events')
                      .doc(event.id)
                      .update({
                        'title': titleCtrl.text.trim(),
                        'category': category.name,
                        'startDate': Timestamp.fromDate(startDate),
                        'endDate': Timestamp.fromDate(endDate),
                        'lastEditedBy': _uid,
                        'lastEditedAt': FieldValue.serverTimestamp(),
                      });
                } catch (error) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(SnackBar(content: Text('일정 저장 실패: $error')));
                  }
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteEvent(CalendarEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('일정 삭제'),
        content: Text('${event.title} 일정을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(event.id)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('일정을 삭제했습니다.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('일정 삭제 실패: $error')));
      }
    }
  }

  void _showEventDetails(CalendarEvent event) {
    final canModify = _canModifyEvent(event);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _GroupEventInfoChip(
                    icon: Icons.calendar_today_outlined,
                    label: widget.name,
                    color: widget.color,
                  ),
                  _GroupEventInfoChip(
                    icon: Icons.label_outline,
                    label: event.category.label,
                    color: event.category.color,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _GroupEventInfoRow(
                icon: Icons.date_range_outlined,
                label: '기간',
                value: formatCalendarEventRange(event),
              ),
              _GroupEventInfoRow(
                icon: Icons.lock_outline,
                label: '권한',
                value: _permissionLabel(event),
              ),
              _GroupEventInfoRow(
                icon: Icons.person_outline,
                label: '생성',
                value: _actorLabel(event.createdBy),
              ),
              _GroupEventInfoRow(
                icon: Icons.edit_outlined,
                label: '마지막 수정',
                value:
                    '${_actorLabel(event.lastEditedBy)} · ${formatCalendarDateTime(event.lastEditedAt)}',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (canModify)
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _deleteEvent(event);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('삭제'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('닫기'),
                  ),
                  const SizedBox(width: 8),
                  if (canModify)
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showEditEvent(event);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('수정'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(widget.name),
          ],
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<List<CalendarEvent>>(
        stream: _eventsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allEvents = snapshot.data ?? [];

          return LayoutBuilder(
            builder: (context, constraints) {
              final weeks = _weeksInMonth(_focusedDay);
              final rowHeight = _selectedDay == null
                  ? ((constraints.maxHeight - 72) / weeks).clamp(60.0, 120.0)
                  : 60.0;

              return Column(
                children: [
                  TableCalendar<CalendarEvent>(
                    firstDay: DateTime(2026, 1),
                    lastDay: DateTime(2028, 12),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                    calendarFormat: CalendarFormat.month,
                    availableCalendarFormats: const {
                      CalendarFormat.month: 'Month',
                    },
                    eventLoader: (day) => _eventsForDay(allEvents, day),
                    startingDayOfWeek: StartingDayOfWeek.monday,
                    rowHeight: rowHeight,
                    onDaySelected: (selected, focused) {
                      final isSame = isSameDay(_selectedDay, selected);
                      setState(() {
                        _focusedDay = focused;
                        _selectedDay = isSame ? null : selected;
                      });
                    },
                    onPageChanged: (focused) => setState(() {
                      _focusedDay = focused;
                      _selectedDay = null;
                    }),
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      todayDecoration: BoxDecoration(
                        color: widget.color.withAlpha(40),
                        shape: BoxShape.circle,
                      ),
                      todayTextStyle: TextStyle(
                        color: widget.color,
                        fontWeight: FontWeight.bold,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                      ),
                      markersMaxCount: 0,
                    ),
                    calendarBuilders: CalendarBuilders(
                      markerBuilder: (context, day, events) {
                        if (events.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...events.take(2).map((e) {
                                final ev = e;
                                return Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 0.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: widget.color.withAlpha(45),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    ev.title,
                                    style: TextStyle(
                                      fontSize: 8,
                                      color: widget.color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                );
                              }),
                              if (events.length > 2)
                                Text(
                                  '+${events.length - 2}',
                                  style: TextStyle(
                                    fontSize: 7,
                                    color: Colors.grey[400],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                    ),
                  ),
                  // 날짜 선택 패널
                  if (_selectedDay != null) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedDateLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _selectedDay = null),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: () {
                        final dayEvents = _eventsForDay(
                          allEvents,
                          _selectedDay!,
                        );
                        if (dayEvents.isEmpty) {
                          return Center(
                            child: Text(
                              '일정 없음',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: dayEvents.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final e = dayEvents[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 4,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: e.category.color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              title: Text(
                                e.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                formatCalendarEventRange(e),
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: e.category.color.withAlpha(40),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      e.category.label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: e.category.color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.chevron_right, size: 18),
                                ],
                              ),
                              onTap: () => _showEventDetails(e),
                            );
                          },
                        );
                      }(),
                    ),
                  ] else if (allEvents.isEmpty) ...[
                    const Divider(height: 1),
                    Expanded(
                      child: Center(
                        child: Text(
                          '등록된 일정이 없어요',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _GroupEventInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _GroupEventInfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupEventInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _GroupEventInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
