import 'package:flutter_test/flutter_test.dart';
import 'package:sunrintodo/core/services/neis_service.dart';
import 'package:sunrintodo/core/services/timetable_merge_service.dart';
import 'package:sunrintodo/core/services/timetable_override_service.dart';

void main() {
  group('mergeTimetableEntries', () {
    test('keeps NEIS entries as the row source', () {
      final entries = [
        TimetableEntry(period: 1, subject: '국어', date: '20260501'),
      ];
      const overrideDay = TimetableOverrideDay(
        dateKey: '20260501',
        periods: {2: TimetablePeriodOverride(period: 2, subject: '수학')},
      );

      final merged = mergeTimetableEntries(
        neisEntries: entries,
        overrideDay: overrideDay,
      );

      expect(merged, hasLength(1));
      expect(merged.single.period, 1);
      expect(merged.single.subject, '국어');
      expect(merged.single.hasOverride, isFalse);
    });

    test('applies subject overrides after NEIS entries load', () {
      final entries = [
        TimetableEntry(period: 1, subject: '국어', date: '20260501'),
        TimetableEntry(period: 2, subject: '수학', date: '20260501'),
      ];
      const overrideDay = TimetableOverrideDay(
        dateKey: '20260501',
        periods: {
          2: TimetablePeriodOverride(
            period: 2,
            subject: '확률과 통계',
            originalSubject: '수학',
          ),
        },
      );

      final merged = mergeTimetableEntries(
        neisEntries: entries,
        overrideDay: overrideDay,
      );

      expect(merged[0].subject, '국어');
      expect(merged[0].hasOverride, isFalse);
      expect(merged[1].subject, '확률과 통계');
      expect(merged[1].originalSubject, '수학');
      expect(merged[1].hasOverride, isTrue);
    });

    test('treats an empty subject override as explicit', () {
      final entries = [
        TimetableEntry(period: 1, subject: '국어', date: '20260501'),
      ];
      const overrideDay = TimetableOverrideDay(
        dateKey: '20260501',
        periods: {1: TimetablePeriodOverride(period: 1, subject: '')},
      );

      final merged = mergeTimetableEntries(
        neisEntries: entries,
        overrideDay: overrideDay,
      );

      expect(merged.single.subject, '');
      expect(merged.single.hasOverride, isTrue);
      expect(merged.single.isExplicitBlankOverride, isTrue);
    });
  });

  group('mergeTimetableByDate', () {
    test('applies only overrides matching each timetable date key', () {
      final neisTimetable = {
        '20260501': [
          TimetableEntry(period: 1, subject: '국어', date: '20260501'),
          TimetableEntry(period: 2, subject: '수학', date: '20260501'),
        ],
        '20260502': [
          TimetableEntry(period: 1, subject: '영어', date: '20260502'),
        ],
      };
      const overridesByDate = {
        '20260501': TimetableOverrideDay(
          dateKey: '20260501',
          periods: {2: TimetablePeriodOverride(period: 2, subject: '확률과 통계')},
        ),
        '20260503': TimetableOverrideDay(
          dateKey: '20260503',
          periods: {1: TimetablePeriodOverride(period: 1, subject: '물리')},
        ),
      };

      final merged = mergeTimetableByDate(
        neisTimetable: neisTimetable,
        overridesByDate: overridesByDate,
      );

      expect(merged.keys, containsAll(['20260501', '20260502']));
      expect(merged['20260501']![0].subject, '국어');
      expect(merged['20260501']![0].hasOverride, isFalse);
      expect(merged['20260501']![1].subject, '확률과 통계');
      expect(merged['20260501']![1].hasOverride, isTrue);
      expect(merged['20260502']!.single.subject, '영어');
      expect(merged['20260502']!.single.hasOverride, isFalse);
    });
  });
}
