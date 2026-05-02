import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const int minTimetableOverridePeriod = 1;
const int maxTimetableOverridePeriod = 12;

class TimetablePeriodOverride {
  final int period;
  final String subject;
  final String? originalSubject;
  final DateTime? updatedAt;

  const TimetablePeriodOverride({
    required this.period,
    required this.subject,
    this.originalSubject,
    this.updatedAt,
  });

  factory TimetablePeriodOverride.fromFirestore(
    int period,
    Map<String, dynamic> data,
  ) {
    return TimetablePeriodOverride(
      period: period,
      subject: data['subject'] as String? ?? '',
      originalSubject: data['originalSubject'] as String?,
      updatedAt: _dateTimeFromTimestamp(data['updatedAt']),
    );
  }

  Map<String, Object?> toFirestore({Object? updatedAt}) {
    return {
      'subject': subject,
      if (originalSubject != null) 'originalSubject': originalSubject,
      'updatedAt': updatedAt ?? FieldValue.serverTimestamp(),
    };
  }
}

class TimetableOverrideDay {
  final String dateKey;
  final Map<int, TimetablePeriodOverride> periods;
  final DateTime? updatedAt;

  const TimetableOverrideDay({
    required this.dateKey,
    required this.periods,
    this.updatedAt,
  });

  factory TimetableOverrideDay.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawPeriods = data['periods'];
    final periods = <int, TimetablePeriodOverride>{};

    if (rawPeriods is Map<String, dynamic>) {
      for (final entry in rawPeriods.entries) {
        final period = int.tryParse(entry.key);
        final value = entry.value;
        if (period == null || value is! Map<String, dynamic>) continue;
        periods[period] = TimetablePeriodOverride.fromFirestore(period, value);
      }
    }

    return TimetableOverrideDay(
      dateKey: data['date'] as String? ?? doc.id,
      periods: periods,
      updatedAt: _dateTimeFromTimestamp(data['updatedAt']),
    );
  }

  bool get isEmpty => periods.isEmpty;

  Map<String, Object?> toFirestore({Object? updatedAt}) {
    final timestamp = updatedAt ?? FieldValue.serverTimestamp();
    final firestorePeriods = <String, Object?>{};
    for (final entry in periods.entries) {
      firestorePeriods[entry.key.toString()] = entry.value.toFirestore(
        updatedAt: timestamp,
      );
    }

    return {
      'date': dateKey,
      'periods': firestorePeriods,
      'updatedAt': timestamp,
    };
  }
}

class TimetableOverrideService {
  TimetableOverrideService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static String dateKey(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return '${normalized.year}'
        '${normalized.month.toString().padLeft(2, '0')}'
        '${normalized.day.toString().padLeft(2, '0')}';
  }

  Stream<TimetableOverrideDay?> watchDay(DateTime date) {
    return _dayRef(date).snapshots().map((doc) {
      if (!doc.exists) return null;
      return TimetableOverrideDay.fromFirestore(doc);
    });
  }

  Stream<Map<String, TimetableOverrideDay>> watchDateRange({
    required DateTime start,
    required DateTime end,
  }) {
    return _dateRangeQuery(start: start, end: end).snapshots().map((snapshot) {
      return {
        for (final doc in snapshot.docs)
          doc.id: TimetableOverrideDay.fromFirestore(doc),
      };
    });
  }

  Future<TimetableOverrideDay?> fetchDay(DateTime date) async {
    final doc = await _dayRef(date).get();
    if (!doc.exists) return null;
    return TimetableOverrideDay.fromFirestore(doc);
  }

  Future<Map<String, TimetableOverrideDay>> fetchDateRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final snapshot = await _dateRangeQuery(start: start, end: end).get();
    return {
      for (final doc in snapshot.docs)
        doc.id: TimetableOverrideDay.fromFirestore(doc),
    };
  }

  Future<void> setPeriodOverride({
    required DateTime date,
    required int period,
    required String subject,
    String? originalSubject,
  }) async {
    _validatePeriod(period);
    _validateSubject(subject, 'subject');
    if (originalSubject != null) {
      _validateSubject(originalSubject, 'originalSubject');
    }

    final periodKey = period.toString();
    final timestamp = FieldValue.serverTimestamp();
    final periodOverride = TimetablePeriodOverride(
      period: period,
      subject: subject,
      originalSubject: originalSubject,
    );
    final docRef = _dayRef(date);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final periods = <String, Object?>{};

      if (snapshot.exists) {
        final data = snapshot.data() ?? const <String, dynamic>{};
        final rawPeriods = data['periods'];
        if (rawPeriods is Map<String, dynamic>) {
          periods.addAll(rawPeriods);
        }
      }

      periods[periodKey] = periodOverride.toFirestore(updatedAt: timestamp);

      transaction.set(docRef, {
        'date': dateKey(date),
        'periods': periods,
        'updatedAt': timestamp,
      });
    });
  }

  Future<void> resetPeriod({
    required DateTime date,
    required int period,
  }) async {
    _validatePeriod(period);
    await _dayRef(date).update({
      'updatedAt': FieldValue.serverTimestamp(),
      'periods.$period': FieldValue.delete(),
    });
  }

  Future<void> resetDay(DateTime date) {
    return _dayRef(date).delete();
  }

  Query<Map<String, dynamic>> _dateRangeQuery({
    required DateTime start,
    required DateTime end,
  }) {
    final startKey = dateKey(start);
    final endKey = dateKey(end);
    if (startKey.compareTo(endKey) > 0) {
      throw ArgumentError.value(end, 'end', 'Must be on or after start.');
    }

    return _collection()
        .orderBy(FieldPath.documentId)
        .startAt([startKey])
        .endAt([endKey]);
  }

  DocumentReference<Map<String, dynamic>> _dayRef(DateTime date) {
    final key = dateKey(date);
    return _collection().doc(key);
  }

  CollectionReference<Map<String, dynamic>> _collection() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Timetable overrides require a signed-in user.');
    }

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('timetableOverrides');
  }

  void _validatePeriod(int period) {
    if (period < minTimetableOverridePeriod ||
        period > maxTimetableOverridePeriod) {
      throw RangeError.range(
        period,
        minTimetableOverridePeriod,
        maxTimetableOverridePeriod,
        'period',
      );
    }
  }

  void _validateSubject(String subject, String fieldName) {
    if (subject.length > 80) {
      throw ArgumentError.value(
        subject,
        fieldName,
        'Must be 80 characters or fewer.',
      );
    }
  }
}

DateTime? _dateTimeFromTimestamp(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
