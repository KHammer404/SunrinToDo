import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunrintodo/core/services/neis_service.dart';
import 'package:sunrintodo/core/services/timetable_merge_service.dart';
import 'package:sunrintodo/core/services/timetable_override_service.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final _overrideService = TimetableOverrideService();
  final Map<String, Stream<TimetableOverrideDay?>> _overrideStreams = {};

  int? _grade;
  int? _classNum;
  bool _loadingPrefs = true;

  late DateTime _weekStart;
  late Future<Map<String, List<TimetableEntry>>> _timetableFuture;

  static const weekdays = ['월', '화', '수', '목', '금'];

  String _errorMessage(Object? error) {
    if (error == null) {
      return '불러올 수 없어요';
    }
    return neisErrorMessage(error);
  }

  @override
  void initState() {
    super.initState();
    _weekStart = _getMonday(DateTime.now());
    _loadPrefs();
  }

  DateTime _getMonday(DateTime date) =>
      date.subtract(Duration(days: date.weekday - 1));

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _grade = prefs.getInt('grade');
      _classNum = prefs.getInt('classNum');
      _loadingPrefs = false;
    });
    if (_grade != null && _classNum != null) _loadTimetable();
  }

  void _loadTimetable() {
    setState(() {
      _timetableFuture = NeisService.getWeekTimetable(
        grade: _grade!,
        classNum: _classNum!,
        weekStart: _weekStart,
      );
    });
  }

  Stream<TimetableOverrideDay?> _overrideStreamFor(DateTime date) {
    final key = TimetableOverrideService.dateKey(date);
    return _overrideStreams.putIfAbsent(
      key,
      () => _overrideService.watchDay(date),
    );
  }

  DateTime _dateForOffset(int dayOffset) {
    return _weekStart.add(Duration(days: dayOffset));
  }

  String _subjectLabel(TimetableDisplayEntry entry) {
    if (entry.subject.isNotEmpty) return entry.subject;
    return entry.isExplicitBlankOverride ? '빈칸 (수정됨)' : '빈칸';
  }

  Future<void> _showEditSubjectDialog({
    required DateTime date,
    required TimetableDisplayEntry entry,
  }) async {
    final controller = TextEditingController(text: entry.subject);
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> saveOverride(String subject) async {
              setDialogState(() => saving = true);
              try {
                await _overrideService.setPeriodOverride(
                  date: date,
                  period: entry.period,
                  subject: subject,
                  originalSubject: entry.originalSubject,
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _showSnackBar('시간표를 저장했어요');
              } catch (error) {
                if (!dialogContext.mounted) return;
                setDialogState(() => saving = false);
                _showSnackBar('시간표 저장 실패: $error');
              }
            }

            Future<void> resetOverride() async {
              setDialogState(() => saving = true);
              try {
                await _overrideService.resetPeriod(
                  date: date,
                  period: entry.period,
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _showSnackBar('원래 시간표로 되돌렸어요');
              } catch (error) {
                if (!dialogContext.mounted) return;
                setDialogState(() => saving = false);
                _showSnackBar('시간표 복원 실패: $error');
              }
            }

            return AlertDialog(
              title: Text('${entry.period}교시 수정'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '원래 과목: ${entry.originalSubject.isEmpty ? '빈칸' : entry.originalSubject}',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    enabled: !saving,
                    autofocus: true,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: '과목명',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                if (entry.hasOverride)
                  TextButton.icon(
                    onPressed: saving ? null : resetOverride,
                    icon: const Icon(Icons.restore),
                    label: const Text('원래대로'),
                  ),
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('취소'),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final subject = value.text.trim();
                    return FilledButton(
                      onPressed: saving ? null : () => saveOverride(subject),
                      child: Text(subject.isEmpty ? '빈칸 저장' : '저장'),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  Future<void> _resetPeriodOverride({
    required DateTime date,
    required TimetableDisplayEntry entry,
  }) async {
    try {
      await _overrideService.resetPeriod(date: date, period: entry.period);
      _showSnackBar('원래 시간표로 되돌렸어요');
    } catch (error) {
      _showSnackBar('시간표 복원 실패: $error');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showSetupDialog() async {
    int? tempGrade = _grade;
    int? tempClass = _classNum;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('학년/반 설정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: tempGrade,
                decoration: const InputDecoration(labelText: '학년'),
                items: [1, 2, 3]
                    .map((g) => DropdownMenuItem(value: g, child: Text('$g학년')))
                    .toList(),
                onChanged: (v) => setDialogState(() => tempGrade = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: tempClass,
                decoration: const InputDecoration(labelText: '반'),
                items: List.generate(10, (i) => i + 1)
                    .map((c) => DropdownMenuItem(value: c, child: Text('$c반')))
                    .toList(),
                onChanged: (v) => setDialogState(() => tempClass = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: tempGrade != null && tempClass != null
                  ? () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setInt('grade', tempGrade!);
                      await prefs.setInt('classNum', tempClass!);
                      setState(() {
                        _grade = tempGrade;
                        _classNum = tempClass;
                      });
                      _loadTimetable();
                      if (context.mounted) Navigator.pop(context);
                    }
                  : null,
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  String _dateKey(int dayOffset) {
    return TimetableOverrideService.dateKey(_dateForOffset(dayOffset));
  }

  int get _todayTabIndex {
    final weekday = DateTime.now().weekday;
    return weekday >= 1 && weekday <= 5 ? weekday - 1 : 0;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrefs) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: 5,
      initialIndex: _todayTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: _grade != null
              ? Text('$_grade학년 $_classNum반 시간표')
              : const Text('시간표'),
          actions: [
            IconButton(
              onPressed: _showSetupDialog,
              icon: const Icon(Icons.tune),
            ),
          ],
          bottom: TabBar(tabs: weekdays.map((d) => Tab(text: d)).toList()),
        ),
        body: _grade == null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('학년/반을 먼저 설정해주세요'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _showSetupDialog,
                      child: const Text('설정하기'),
                    ),
                  ],
                ),
              )
            : FutureBuilder<Map<String, List<TimetableEntry>>>(
                future: _timetableFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage(snapshot.error),
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          TextButton(
                            onPressed: _loadTimetable,
                            child: const Text('다시 시도'),
                          ),
                        ],
                      ),
                    );
                  }

                  final timetable = snapshot.data ?? {};
                  return TabBarView(
                    children: List.generate(5, (i) {
                      final date = _dateForOffset(i);
                      final entries = timetable[_dateKey(i)] ?? [];
                      if (entries.isEmpty) {
                        return Center(
                          child: Text(
                            '수업 없음',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        );
                      }
                      return StreamBuilder<TimetableOverrideDay?>(
                        stream: _overrideStreamFor(date),
                        builder: (context, overrideSnapshot) {
                          final displayEntries = mergeTimetableEntries(
                            neisEntries: entries,
                            overrideDay: overrideSnapshot.data,
                          );
                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            itemCount: displayEntries.length,
                            itemBuilder: (context, idx) {
                              final entry = displayEntries[idx];
                              final subjectLabel = _subjectLabel(entry);
                              final isOverridden = entry.hasOverride;
                              final colors = Theme.of(context).colorScheme;

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      child: Text(
                                        '${entry.period}교시',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Material(
                                        color: isOverridden
                                            ? colors.secondaryContainer
                                                  .withAlpha(178)
                                            : colors.primaryContainer.withAlpha(
                                                102,
                                              ),
                                        borderRadius: BorderRadius.circular(8),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          onTap: () => _showEditSubjectDialog(
                                            date: date,
                                            entry: entry,
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                              horizontal: 16,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    subjectLabel,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  Icons.edit,
                                                  size: 18,
                                                  color:
                                                      colors.onSurfaceVariant,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (isOverridden) ...[
                                      const SizedBox(width: 8),
                                      TextButton.icon(
                                        onPressed: () => _resetPeriodOverride(
                                          date: date,
                                          entry: entry,
                                        ),
                                        icon: const Icon(Icons.restore),
                                        label: const Text('원래대로'),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      );
                    }),
                  );
                },
              ),
      ),
    );
  }
}
