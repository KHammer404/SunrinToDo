import 'package:sunrintodo/core/services/neis_service.dart';
import 'package:sunrintodo/core/services/timetable_override_service.dart';

class TimetableDisplayEntry {
  final TimetableEntry originalEntry;
  final TimetablePeriodOverride? override;

  const TimetableDisplayEntry({
    required this.originalEntry,
    required this.override,
  });

  int get period => originalEntry.period;
  String get date => originalEntry.date;
  String? get teacher => originalEntry.teacher;
  String get originalSubject => originalEntry.subject;
  String get subject => override?.subject ?? originalEntry.subject;
  bool get hasOverride => override != null;
  bool get isExplicitBlankOverride => hasOverride && subject.isEmpty;
}

List<TimetableDisplayEntry> mergeTimetableEntries({
  required List<TimetableEntry> neisEntries,
  TimetableOverrideDay? overrideDay,
}) {
  final overrides =
      overrideDay?.periods ?? const <int, TimetablePeriodOverride>{};

  return [
    for (final entry in neisEntries)
      TimetableDisplayEntry(
        originalEntry: entry,
        override: overrides[entry.period],
      ),
  ];
}

Map<String, List<TimetableDisplayEntry>> mergeTimetableByDate({
  required Map<String, List<TimetableEntry>> neisTimetable,
  required Map<String, TimetableOverrideDay> overridesByDate,
}) {
  return {
    for (final entry in neisTimetable.entries)
      entry.key: mergeTimetableEntries(
        neisEntries: entry.value,
        overrideDay: overridesByDate[entry.key],
      ),
  };
}
