import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sunrintodo/core/theme/app_theme.dart';

enum EventCategory { performance, exam, assignment, notice, other }

extension EventCategoryExt on EventCategory {
  String get label => switch (this) {
    EventCategory.performance => '수행평가',
    EventCategory.exam => '시험',
    EventCategory.assignment => '과제',
    EventCategory.notice => '공지',
    EventCategory.other => '기타',
  };

  Color get color => switch (this) {
    EventCategory.performance => AppColors.performance,
    EventCategory.exam => AppColors.exam,
    EventCategory.assignment => AppColors.assignment,
    EventCategory.notice => AppColors.notice,
    EventCategory.other => AppColors.other,
  };
}

class CalendarEvent {
  final String id;
  final String title;
  final EventCategory category;
  final DateTime startDate;
  final DateTime endDate;
  final String classId;
  final String createdBy;
  final List<String> memberIds;
  final String lastEditedBy;
  final DateTime? lastEditedAt;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.category,
    required this.startDate,
    required this.endDate,
    required this.classId,
    required this.createdBy,
    required this.memberIds,
    required this.lastEditedBy,
    required this.lastEditedAt,
  });

  factory CalendarEvent.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    final createdBy = data['createdBy'] as String? ?? '';
    return CalendarEvent(
      id: doc.id,
      title: data['title'] as String,
      category: EventCategory.values.firstWhere(
        (eventCategory) => eventCategory.name == data['category'],
        orElse: () => EventCategory.other,
      ),
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      classId: data['classId'] as String? ?? 'personal',
      createdBy: createdBy,
      memberIds: List<String>.from(data['memberIds'] as List? ?? const []),
      lastEditedBy: data['lastEditedBy'] as String? ?? createdBy,
      lastEditedAt: (data['lastEditedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class CalendarSpace {
  final String id;
  final String name;
  final Color color;
  final Map<String, String> memberNames;

  const CalendarSpace({
    required this.id,
    required this.name,
    required this.color,
    this.memberNames = const {},
  });
}

enum MemoType { homework, performance, material }

extension MemoTypeExt on MemoType {
  String get label => switch (this) {
    MemoType.homework => '숙제',
    MemoType.performance => '수행평가',
    MemoType.material => '준비물',
  };

  Color get color => switch (this) {
    MemoType.homework => Colors.orange,
    MemoType.performance => AppColors.performance,
    MemoType.material => Colors.green,
  };

  IconData get icon => switch (this) {
    MemoType.homework => Icons.book_outlined,
    MemoType.performance => Icons.edit_outlined,
    MemoType.material => Icons.backpack_outlined,
  };
}

typedef SubjectMemoMap = Map<String, List<Map<String, String>>>;

int compareCalendarEvents(CalendarEvent a, CalendarEvent b) {
  final startCompare = a.startDate.compareTo(b.startDate);
  if (startCompare != 0) return startCompare;

  final endCompare = a.endDate.compareTo(b.endDate);
  if (endCompare != 0) return endCompare;

  final categoryCompare = a.category.index.compareTo(b.category.index);
  if (categoryCompare != 0) return categoryCompare;

  return a.title.compareTo(b.title);
}

int compareCalendarSpaces(
  CalendarSpace a,
  CalendarSpace b,
  Set<String> pinnedSpaceIds,
) {
  final aPinned = pinnedSpaceIds.contains(a.id);
  final bPinned = pinnedSpaceIds.contains(b.id);
  if (aPinned != bPinned) return aPinned ? -1 : 1;

  final nameCompare = a.name.compareTo(b.name);
  if (nameCompare != 0) return nameCompare;
  return a.id.compareTo(b.id);
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String calendarDateKey(DateTime date) =>
    '${date.year}${_twoDigits(date.month)}${_twoDigits(date.day)}';

String calendarMemoKey(DateTime day, int period) =>
    '${calendarDateKey(day)}-$period';

String formatCalendarDate(DateTime date) =>
    '${date.year}.${_twoDigits(date.month)}.${_twoDigits(date.day)}';

String formatCalendarDateTime(DateTime? dateTime) {
  if (dateTime == null) return '없음';
  return '${formatCalendarDate(dateTime)} ${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}';
}

String formatCalendarEventRange(CalendarEvent event) {
  final start = formatCalendarDate(event.startDate);
  final end = formatCalendarDate(event.endDate);
  return start == end ? start : '$start ~ $end';
}

String formatSelectedCalendarDate(DateTime date) {
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  return '${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';
}

int weeksInCalendarMonth(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final last = DateTime(month.year, month.month + 1, 0);
  final offset = (first.weekday - 1) % 7;
  return ((offset + last.day) / 7).ceil();
}

List<CalendarEvent> calendarEventsForDay(
  Iterable<CalendarEvent> allEvents,
  DateTime day, {
  Set<String>? visibleSpaceIds,
}) {
  final date = DateTime(day.year, day.month, day.day);
  final events = allEvents.where((event) {
    if (visibleSpaceIds != null && !visibleSpaceIds.contains(event.classId)) {
      return false;
    }

    final start = DateTime(
      event.startDate.year,
      event.startDate.month,
      event.startDate.day,
    );
    final end = DateTime(
      event.endDate.year,
      event.endDate.month,
      event.endDate.day,
    );
    return !date.isBefore(start) && !date.isAfter(end);
  }).toList();

  return events..sort(compareCalendarEvents);
}

MemoType memoTypeFromName(String? name) {
  return MemoType.values.firstWhere(
    (memoType) => memoType.name == name,
    orElse: () => MemoType.homework,
  );
}

List<MemoType> memoTypesForDay(SubjectMemoMap memos, DateTime day) {
  final dateKey = calendarDateKey(day);
  final types = <MemoType>{};

  for (final key in memos.keys) {
    if (!key.startsWith(dateKey)) continue;
    for (final item in memos[key]!) {
      types.add(memoTypeFromName(item['type']));
    }
  }

  return types.toList();
}
