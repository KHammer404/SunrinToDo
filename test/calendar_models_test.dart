import 'package:flutter_test/flutter_test.dart';
import 'package:sunrintodo/features/calendar/calendar_data_service.dart';
import 'package:sunrintodo/features/calendar/calendar_models.dart';

void main() {
  group('calendarEventsForDay', () {
    test('returns events spanning the selected date and applies filters', () {
      final events = [
        _event(
          id: 'later',
          title: '나중 일정',
          classId: 'class-a',
          startDate: DateTime(2026, 5, 3),
          endDate: DateTime(2026, 5, 3),
        ),
        _event(
          id: 'multi',
          title: '기간 일정',
          classId: 'class-a',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 2),
        ),
        _event(
          id: 'hidden',
          title: '숨김 일정',
          classId: 'class-b',
          startDate: DateTime(2026, 5, 2),
          endDate: DateTime(2026, 5, 2),
        ),
      ];

      final selected = calendarEventsForDay(
        events,
        DateTime(2026, 5, 2, 23, 59),
        visibleSpaceIds: {'class-a'},
      );

      expect(selected.map((event) => event.id), ['multi']);
    });

    test('sorts by start date, end date, category, then title', () {
      final selected = calendarEventsForDay([
        _event(
          id: 'assignment-b',
          title: 'B 과제',
          category: EventCategory.assignment,
        ),
        _event(id: 'exam', title: '시험', category: EventCategory.exam),
        _event(
          id: 'assignment-a',
          title: 'A 과제',
          category: EventCategory.assignment,
        ),
      ], DateTime(2026, 5, 1));

      expect(selected.map((event) => event.id), [
        'exam',
        'assignment-a',
        'assignment-b',
      ]);
    });
  });

  group('calendar memo helpers', () {
    test('builds stable date and period keys', () {
      final date = DateTime(2026, 5, 1, 8, 30);

      expect(calendarDateKey(date), '20260501');
      expect(calendarMemoKey(date, 3), '20260501-3');
    });

    test(
      'collects memo types for one day and ignores malformed type names',
      () {
        final memos = {
          '20260501-1': [
            {'type': 'homework', 'content': '문제 풀이'},
            {'type': 'bad-type', 'content': '기본값'},
          ],
          '20260501-2': [
            {'type': 'material', 'content': '노트'},
          ],
          '20260502-1': [
            {'type': 'performance', 'content': '발표'},
          ],
        };

        final types = memoTypesForDay(memos, DateTime(2026, 5, 1));

        expect(types, [MemoType.homework, MemoType.material]);
      },
    );
  });

  group('calendar layout helpers', () {
    test('counts visible month rows with Monday as the first day', () {
      expect(weeksInCalendarMonth(DateTime(2026, 2)), 5);
      expect(weeksInCalendarMonth(DateTime(2026, 3)), 6);
    });

    test('chunks class ids for Firestore whereIn limits', () {
      final chunks = chunkCalendarClassIds([
        'a',
        'b',
        'a',
        'c',
        'd',
        'e',
        'f',
        'g',
        'h',
        'i',
        'j',
        'k',
      ]);

      expect(chunks, [
        ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'],
        ['k'],
      ]);
    });
  });
}

CalendarEvent _event({
  required String id,
  required String title,
  String classId = 'personal',
  EventCategory category = EventCategory.other,
  DateTime? startDate,
  DateTime? endDate,
}) {
  final start = startDate ?? DateTime(2026, 5, 1);
  return CalendarEvent(
    id: id,
    title: title,
    category: category,
    startDate: start,
    endDate: endDate ?? start,
    classId: classId,
    createdBy: 'user-a',
    memberIds: const ['user-a'],
    lastEditedBy: 'user-a',
    lastEditedAt: null,
  );
}
