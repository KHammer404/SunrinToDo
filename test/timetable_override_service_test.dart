import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunrintodo/core/services/timetable_override_service.dart';

void main() {
  group('TimetableOverrideService.dateKey', () {
    test('normalizes a date to yyyyMMdd and ignores the time of day', () {
      final date = DateTime(2026, 5, 1, 23, 59, 58);

      expect(TimetableOverrideService.dateKey(date), '20260501');
    });
  });

  group('TimetablePeriodOverride', () {
    test('serializes the period override storage fields', () {
      final updatedAt = DateTime(2026, 5, 1, 8, 30);
      const override = TimetablePeriodOverride(
        period: 2,
        subject: '확률과 통계',
        originalSubject: '수학',
      );

      final data = override.toFirestore(updatedAt: updatedAt);

      expect(data, {
        'subject': '확률과 통계',
        'originalSubject': '수학',
        'updatedAt': updatedAt,
      });
    });

    test('persists blank subjects as explicit override values', () {
      final updatedAt = DateTime(2026, 5, 1, 8, 30);
      const override = TimetablePeriodOverride(period: 1, subject: '');

      final data = override.toFirestore(updatedAt: updatedAt);

      expect(data['subject'], '');
      expect(data, isNot(contains('originalSubject')));
      expect(data['updatedAt'], updatedAt);
    });
  });

  group('TimetableOverrideDay', () {
    test('serializes one date document with string period keys', () {
      final updatedAt = DateTime(2026, 5, 1, 8, 30);
      const day = TimetableOverrideDay(
        dateKey: '20260501',
        periods: {
          1: TimetablePeriodOverride(
            period: 1,
            subject: '문학',
            originalSubject: '국어',
          ),
          2: TimetablePeriodOverride(period: 2, subject: ''),
        },
      );

      final data = day.toFirestore(updatedAt: updatedAt);

      expect(data['date'], '20260501');
      expect(data['updatedAt'], updatedAt);
      expect(data['periods'], {
        '1': {'subject': '문학', 'originalSubject': '국어', 'updatedAt': updatedAt},
        '2': {'subject': '', 'updatedAt': updatedAt},
      });
    });

    test('parses a stored override document back into period models', () {
      final periodUpdatedAt = Timestamp.fromDate(DateTime(2026, 5, 1, 8, 30));
      final dayUpdatedAt = Timestamp.fromDate(DateTime(2026, 5, 1, 8, 45));
      final doc = _FakeDocumentSnapshot(
        id: '20260501',
        data: {
          'date': '20260501',
          'updatedAt': dayUpdatedAt,
          'periods': {
            '1': {
              'subject': '문학',
              'originalSubject': '국어',
              'updatedAt': periodUpdatedAt,
            },
            '2': {'subject': '', 'updatedAt': periodUpdatedAt},
          },
        },
      );

      final day = TimetableOverrideDay.fromFirestore(doc);

      expect(day.dateKey, '20260501');
      expect(day.updatedAt, dayUpdatedAt.toDate());
      expect(day.periods.keys, unorderedEquals([1, 2]));
      expect(day.periods[1]!.subject, '문학');
      expect(day.periods[1]!.originalSubject, '국어');
      expect(day.periods[1]!.updatedAt, periodUpdatedAt.toDate());
      expect(day.periods[2]!.subject, '');
      expect(day.periods[2]!.originalSubject, isNull);
    });

    test(
      'falls back to the document id and skips malformed period entries',
      () {
        final doc = _FakeDocumentSnapshot(
          id: '20260502',
          data: {
            'periods': {
              '1': {'subject': '영어', 'updatedAt': DateTime(2026, 5, 2)},
              'bad': {'subject': '무시'},
              '2': 'not a map',
            },
          },
        );

        final day = TimetableOverrideDay.fromFirestore(doc);

        expect(day.dateKey, '20260502');
        expect(day.periods.keys, [1]);
        expect(day.periods[1]!.subject, '영어');
        expect(day.periods[1]!.updatedAt, DateTime(2026, 5, 2));
      },
    );
  });
}

// ignore: subtype_of_sealed_class
class _FakeDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDocumentSnapshot({required this.id, required Map<String, dynamic>? data})
    : _data = data;

  final Map<String, dynamic>? _data;

  @override
  final String id;

  @override
  bool get exists => true;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic get(Object field) => throw UnimplementedError();

  @override
  SnapshotMetadata get metadata => throw UnimplementedError();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnimplementedError();

  @override
  dynamic operator [](Object field) => throw UnimplementedError();
}
