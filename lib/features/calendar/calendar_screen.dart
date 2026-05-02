import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:sunrintodo/core/services/neis_service.dart';
import 'package:sunrintodo/core/services/timetable_merge_service.dart';
import 'package:sunrintodo/core/services/timetable_override_service.dart';
import 'package:sunrintodo/features/calendar/calendar_data_service.dart';
import 'package:sunrintodo/features/calendar/calendar_models.dart';
import 'package:sunrintodo/features/class/class_colors.dart';

const _pinnedClassIdsPrefsKey = 'pinnedClassIds';

Color _colorForId(String id) {
  return classColorFromId(id);
}

// ─── 메인 화면 ─────────────────────────────────────────────────────────────────
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _calendarDataService = CalendarDataService();
  final _overrideService = TimetableOverrideService();
  final Map<String, Stream<TimetableOverrideDay?>> _overrideStreams = {};

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  List<CalendarSpace> _spaces = [];
  final Set<String> _checkedIds = {'personal'};
  final Set<String> _knownSpaceIds = {}; // 한 번 본 스페이스 추적 (필터 초기화용)
  Set<String> _pinnedClassIds = {};

  List<TimetableEntry> _timetable = [];
  MealInfo? _meal;
  bool _loadingDay = false;

  SubjectMemoMap _memos = {};
  int? _grade;
  int? _classNum;

  String get _userName {
    final user = FirebaseAuth.instance.currentUser;
    return user?.displayName ?? user?.email ?? _uid;
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _grade = prefs.getInt('grade');
      _classNum = prefs.getInt('classNum');
      _pinnedClassIds =
          prefs.getStringList(_pinnedClassIdsPrefsKey)?.toSet() ?? {};
    });
    final memoJson = prefs.getString('subjectMemos');
    if (memoJson != null && mounted) {
      try {
        final raw = jsonDecode(memoJson) as Map<String, dynamic>;
        setState(() {
          _memos = raw.map(
            (k, v) => MapEntry(
              k,
              (v as List)
                  .map((item) => Map<String, String>.from(item as Map))
                  .toList(),
            ),
          );
        });
      } catch (_) {
        await prefs.remove('subjectMemos');
      }
    }
  }

  Future<void> _togglePinnedSpace(CalendarSpace space) async {
    if (space.id == 'personal') return;

    setState(() {
      if (_pinnedClassIds.contains(space.id)) {
        _pinnedClassIds.remove(space.id);
      } else {
        _pinnedClassIds.add(space.id);
      }
    });

    final prefs = await SharedPreferences.getInstance();
    final values = _pinnedClassIds.toList()..sort();
    await prefs.setStringList(_pinnedClassIdsPrefsKey, values);
  }

  Stream<List<CalendarSpace>> get _spacesStream =>
      _calendarDataService.watchSpaces(
        uid: _uid,
        userName: _userName,
        pinnedSpaceIds: _pinnedClassIds,
      );

  Stream<List<CalendarEvent>> get _eventsStream =>
      _calendarDataService.watchUserEvents(uid: _uid);

  Stream<TimetableOverrideDay?> _overrideStreamFor(DateTime date) {
    if (_uid.isEmpty) return Stream.value(null);

    final key = TimetableOverrideService.dateKey(date);
    return _overrideStreams.putIfAbsent(
      key,
      () => _overrideService.watchDay(date),
    );
  }

  List<CalendarEvent> _eventsForDay(List<CalendarEvent> all, DateTime day) =>
      calendarEventsForDay(all, day, visibleSpaceIds: _checkedIds);

  int _weeksInMonth(DateTime month) => weeksInCalendarMonth(month);

  List<MemoType> _memosForDay(DateTime day) => memoTypesForDay(_memos, day);

  Future<void> _loadDayData(DateTime day) async {
    setState(() {
      _loadingDay = true;
      _timetable = [];
      _meal = null;
    });

    final dateStr = calendarDateKey(day);

    if (_grade != null && _classNum != null) {
      try {
        final monday = day.subtract(Duration(days: day.weekday - 1));
        final week = await NeisService.getWeekTimetable(
          grade: _grade!,
          classNum: _classNum!,
          weekStart: monday,
        );
        if (mounted) setState(() => _timetable = week[dateStr] ?? []);
      } catch (_) {}
    }

    try {
      final meals = await NeisService.getMeals(day);
      if (mounted) {
        setState(
          () => _meal = meals.where((m) => m.mealName == '중식').firstOrNull,
        );
      }
    } catch (_) {}

    if (mounted) setState(() => _loadingDay = false);
  }

  String _memoKey(DateTime day, int period) => calendarMemoKey(day, period);

  String _subjectLabel(TimetableDisplayEntry entry) {
    if (entry.subject.isNotEmpty) return entry.subject;
    return entry.isExplicitBlankOverride ? '빈칸 (수정됨)' : '빈칸';
  }

  Future<void> _saveMemos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subjectMemos', jsonEncode(_memos));
  }

  String get _selectedDateLabel {
    if (_selectedDay == null) return '';
    return formatSelectedCalendarDate(_selectedDay!);
  }

  CalendarSpace _spaceForEvent(CalendarEvent event) => _spaces.firstWhere(
    (space) => space.id == event.classId,
    orElse: () => CalendarSpace(
      id: event.classId,
      name: event.classId == 'personal' ? '개인' : '학급',
      color: _colorForId(event.classId),
    ),
  );

  String _actorLabel(String uid, {String? classId}) {
    if (uid.isEmpty) return '알 수 없음';
    if (uid == _uid) return '나';

    if (classId != null) {
      for (final space in _spaces) {
        if (space.id != classId) continue;
        final memberName = space.memberNames[uid];
        if (memberName != null && memberName.isNotEmpty) return memberName;
      }
    }

    return uid;
  }

  bool _canModifyEvent(CalendarEvent event) {
    if (event.classId == 'personal') return event.createdBy == _uid;
    return _spaces.any((space) => space.id == event.classId);
  }

  String _permissionLabel(CalendarEvent event) {
    if (event.classId == 'personal') {
      return '개인 일정 · 작성자만 수정/삭제 가능';
    }
    return '학급 일정 · 학급 멤버는 수정/삭제 가능';
  }

  // ─── 일정 추가/수정 다이얼로그 ────────────────────────────────────────────────
  void _showAddEvent() => _showEventEditor();

  void _showEventEditor({CalendarEvent? event}) {
    final editingEvent = event;
    final isEditing = editingEvent != null;
    final titleCtrl = TextEditingController();
    titleCtrl.text = editingEvent?.title ?? '';
    DateTime startDate =
        editingEvent?.startDate ?? _selectedDay ?? DateTime.now();
    DateTime endDate = editingEvent?.endDate ?? _selectedDay ?? DateTime.now();
    EventCategory category = editingEvent?.category ?? EventCategory.other;
    String spaceId =
        editingEvent?.classId ??
        (_spaces.isNotEmpty ? _spaces.first.id : 'personal');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(isEditing ? '일정 수정' : '일정 추가'),
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
                if (_spaces.length > 1 && !isEditing)
                  DropdownButtonFormField<String>(
                    initialValue: spaceId,
                    decoration: const InputDecoration(
                      labelText: '캘린더',
                      border: OutlineInputBorder(),
                    ),
                    items: _spaces
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: s.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(s.name),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDialog(() => spaceId = v!),
                  ),
                if (isEditing)
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
                            color: _spaceForEvent(editingEvent).color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_spaceForEvent(editingEvent).name),
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
                          selectedColor: cat.color.withAlpha(77),
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
                          final p = await showDatePicker(
                            context: ctx,
                            initialDate: startDate,
                            firstDate: DateTime(2026),
                            lastDate: DateTime(2028),
                          );
                          if (p != null) {
                            setDialog(() {
                              startDate = p;
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
                          final p = await showDatePicker(
                            context: ctx,
                            initialDate: endDate,
                            firstDate: startDate,
                            lastDate: DateTime(2028),
                          );
                          if (p != null) setDialog(() => endDate = p);
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
                  if (isEditing) {
                    await FirebaseFirestore.instance
                        .collection('events')
                        .doc(editingEvent.id)
                        .update({
                          'title': titleCtrl.text.trim(),
                          'category': category.name,
                          'startDate': Timestamp.fromDate(startDate),
                          'endDate': Timestamp.fromDate(endDate),
                          'lastEditedBy': _uid,
                          'lastEditedAt': FieldValue.serverTimestamp(),
                        });
                  } else {
                    List<String> memberIds = [_uid];
                    if (spaceId != 'personal') {
                      final classDoc = await FirebaseFirestore.instance
                          .collection('classes')
                          .doc(spaceId)
                          .get();
                      memberIds = List<String>.from(
                        classDoc.data()?['memberIds'] ?? [_uid],
                      );
                    }

                    await FirebaseFirestore.instance.collection('events').add({
                      'title': titleCtrl.text.trim(),
                      'category': category.name,
                      'startDate': Timestamp.fromDate(startDate),
                      'endDate': Timestamp.fromDate(endDate),
                      'classId': spaceId,
                      'createdBy': _uid,
                      'memberIds': memberIds,
                      'lastEditedBy': _uid,
                      'lastEditedAt': FieldValue.serverTimestamp(),
                    });
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(
                      ctx,
                    ).showSnackBar(SnackBar(content: Text('일정 저장 실패: $e')));
                  }
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(isEditing ? '저장' : '추가'),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('일정 삭제 실패: $e')));
      }
    }
  }

  void _showEventDetails(CalendarEvent event) {
    final space = _spaceForEvent(event);
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
                      color: space.color,
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
                  _EventInfoChip(
                    icon: Icons.calendar_today_outlined,
                    label: space.name,
                    color: space.color,
                  ),
                  _EventInfoChip(
                    icon: Icons.label_outline,
                    label: event.category.label,
                    color: event.category.color,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _EventInfoRow(
                icon: Icons.date_range_outlined,
                label: '기간',
                value: formatCalendarEventRange(event),
              ),
              _EventInfoRow(
                icon: Icons.lock_outline,
                label: '권한',
                value: _permissionLabel(event),
              ),
              _EventInfoRow(
                icon: Icons.person_outline,
                label: '생성',
                value: _actorLabel(event.createdBy, classId: event.classId),
              ),
              _EventInfoRow(
                icon: Icons.edit_outlined,
                label: '마지막 수정',
                value:
                    '${_actorLabel(event.lastEditedBy, classId: event.classId)} · ${formatCalendarDateTime(event.lastEditedAt)}',
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
                        _showEventEditor(event: event);
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

  // ─── 과목 메모 바텀시트 ───────────────────────────────────────────────────────
  void _showSubjectMemo(TimetableDisplayEntry entry) {
    final key = _memoKey(_selectedDay!, entry.period);
    final memoList = List<Map<String, String>>.from(
      (_memos[key] ?? []).map((m) => Map<String, String>.from(m)),
    );
    MemoType selectedType = MemoType.homework;
    final ctrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entry.period}교시 · ${_subjectLabel(entry)}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (memoList.isNotEmpty) ...[
                ...memoList.asMap().entries.map((e) {
                  final idx = e.key;
                  final memo = e.value;
                  final t = memoTypeFromName(memo['type']);
                  final c = t.color;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: c.withAlpha(31),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: c.withAlpha(102)),
                          ),
                          child: Text(
                            t.label,
                            style: TextStyle(
                              fontSize: 12,
                              color: c,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            memo['content'] ?? '',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          color: Colors.grey[400],
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              setSheet(() => memoList.removeAt(idx)),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(height: 24),
              ],
              Text(
                '항목 추가',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 10),
              SegmentedButton<MemoType>(
                segments: MemoType.values
                    .map(
                      (t) => ButtonSegment<MemoType>(
                        value: t,
                        icon: Icon(t.icon, size: 14),
                        label: Text(
                          t.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    )
                    .toList(),
                selected: {selectedType},
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    setSheet(() => selectedType = s.first),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      autofocus: memoList.isEmpty,
                      decoration: InputDecoration(
                        hintText: '내용을 입력하세요',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) {
                          setSheet(() {
                            memoList.add({
                              'type': selectedType.name,
                              'content': v.trim(),
                            });
                            ctrl.clear();
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (ctrl.text.trim().isNotEmpty) {
                        setSheet(() {
                          memoList.add({
                            'type': selectedType.name,
                            'content': ctrl.text.trim(),
                          });
                          ctrl.clear();
                        });
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('추가'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (_memos.containsKey(key))
                    TextButton(
                      onPressed: () {
                        setState(() => _memos.remove(key));
                        _saveMemos();
                        Navigator.pop(ctx);
                      },
                      child: const Text(
                        '전체 삭제',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        if (memoList.isEmpty) {
                          _memos.remove(key);
                        } else {
                          _memos[key] = memoList;
                        }
                      });
                      _saveMemos();
                      Navigator.pop(ctx);
                    },
                    child: const Text('저장'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 드로어 ────────────────────────────────────────────────────────────────
  Widget _buildDrawer(List<CalendarSpace> spaces) {
    final user = FirebaseAuth.instance.currentUser;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 유저 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          user?.email ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                '캘린더',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ...spaces.map(
                    (space) => ListTile(
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: space.color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          space.id == 'personal'
                              ? Icons.lock_outline
                              : Icons.group_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      title: Text(space.name),
                      trailing: space.id == 'personal'
                          ? null
                          : IconButton(
                              tooltip: _pinnedClassIds.contains(space.id)
                                  ? '고정 해제'
                                  : '상단 고정',
                              icon: Icon(
                                _pinnedClassIds.contains(space.id)
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 18,
                              ),
                              onPressed: () => _togglePinnedSpace(space),
                            ),
                      onTap: () {
                        Navigator.pop(context);
                        context.push(
                          '/group',
                          extra: {
                            'classId': space.id,
                            'name': space.name,
                            'color': space.color,
                          },
                        );
                      },
                    ),
                  ),
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.add, color: Colors.grey[500], size: 18),
                    ),
                    title: const Text('새 캘린더'),
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/class');
                    },
                  ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('설정'),
              onTap: () {
                Navigator.pop(context);
                context.push('/settings');
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── 필터 칩 row ──────────────────────────────────────────────────────────
  Widget _buildChips(List<CalendarSpace> spaces) {
    if (spaces.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: spaces.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final space = spaces[i];
          final checked = _checkedIds.contains(space.id);
          return GestureDetector(
            onTap: () => setState(() {
              if (checked) {
                _checkedIds.remove(space.id);
              } else {
                _checkedIds.add(space.id);
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: checked
                    ? space.color.withAlpha(31)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: checked
                      ? space.color.withAlpha(153)
                      : Colors.grey.shade300,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: checked ? space.color : Colors.grey.shade400,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    space.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: checked ? space.color : Colors.grey.shade500,
                    ),
                  ),
                  if (checked) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check, size: 13, color: space.color),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── 날짜 패널 내용 ───────────────────────────────────────────────────────
  Widget _buildDayContent(List<CalendarEvent> allEvents) {
    final dayEvents = _eventsForDay(allEvents, _selectedDay!);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: [
        if (_timetable.isNotEmpty) ...[
          _SectionLabel('시간표'),
          StreamBuilder<TimetableOverrideDay?>(
            stream: _overrideStreamFor(_selectedDay!),
            builder: (context, overrideSnapshot) {
              final displayEntries = mergeTimetableEntries(
                neisEntries: _timetable,
                overrideDay: overrideSnapshot.data,
              );
              return Column(
                children: displayEntries.map((entry) {
                  final key = _memoKey(_selectedDay!, entry.period);
                  final memoList = _memos[key] ?? [];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text(
                      '${entry.period}교시',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    title: Text(_subjectLabel(entry)),
                    subtitle: memoList.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: memoList.map((m) {
                                final t = memoTypeFromName(m['type']);
                                final c = t.color;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.withAlpha(31),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: c.withAlpha(102)),
                                  ),
                                  child: Text(
                                    '${t.label} · ${m['content']}',
                                    style: TextStyle(fontSize: 11, color: c),
                                  ),
                                );
                              }).toList(),
                            ),
                          )
                        : null,
                    trailing: Icon(
                      Icons.edit_note,
                      size: 20,
                      color: Colors.grey[400],
                    ),
                    onTap: () => _showSubjectMemo(entry),
                  );
                }).toList(),
              );
            },
          ),
          const Divider(),
        ],
        _SectionLabel('급식'),
        if (_meal != null) ...[
          Text(
            _meal!.calories,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const SizedBox(height: 4),
          ..._meal!.dishes.map(
            (d) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(d),
            ),
          ),
        ] else
          Text('급식 정보 없음', style: TextStyle(color: Colors.grey[400])),
        const Divider(),
        _SectionLabel('일정'),
        if (dayEvents.isEmpty)
          Text('일정 없음', style: TextStyle(color: Colors.grey[400]))
        else
          ...dayEvents.map((e) {
            final space = _spaceForEvent(e);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: space.color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              title: Text(e.title),
              subtitle: Text(
                '${space.name} · ${e.category.label} · ${formatCalendarEventRange(e)}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => _showEventDetails(e),
            );
          }),
      ],
    );
  }

  // ─── 빌드 ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<CalendarSpace>>(
      stream: _spacesStream,
      builder: (context, spacesSnap) {
        final spaces =
            spacesSnap.data ??
            [
              const CalendarSpace(
                id: 'personal',
                name: '개인',
                color: Color(0xFF4285F4),
              ),
            ];

        // 처음 보는 스페이스만 자동 체크 (사용자가 끈 것은 유지)
        for (final s in spaces) {
          if (_knownSpaceIds.add(s.id)) {
            _checkedIds.add(s.id);
          }
        }
        _spaces = spaces;

        return StreamBuilder<List<CalendarEvent>>(
          stream: _eventsStream,
          builder: (context, eventsSnap) {
            final allEvents = eventsSnap.data ?? [];

            return Scaffold(
              appBar: AppBar(
                title: Text(
                  '${_focusedDay.year}년 ${_focusedDay.month}월',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                centerTitle: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() {
                      _focusedDay = DateTime(
                        _focusedDay.year,
                        _focusedDay.month - 1,
                      );
                      _selectedDay = null;
                    }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() {
                      _focusedDay = DateTime(
                        _focusedDay.year,
                        _focusedDay.month + 1,
                      );
                      _selectedDay = null;
                    }),
                  ),
                ],
              ),
              drawer: _buildDrawer(spaces),
              body: LayoutBuilder(
                builder: (context, constraints) {
                  final weeks = _weeksInMonth(_focusedDay);
                  final rowHeight = _selectedDay == null
                      ? ((constraints.maxHeight - 120) / weeks).clamp(
                          60.0,
                          120.0,
                        )
                      : 60.0;

                  return Column(
                    children: [
                      // 필터 칩
                      _buildChips(spaces),
                      // 캘린더
                      TableCalendar<CalendarEvent>(
                        firstDay: DateTime(2026, 1),
                        lastDay: DateTime(2028, 12),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (day) =>
                            isSameDay(_selectedDay, day),
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
                          if (!isSame) _loadDayData(selected);
                        },
                        onPageChanged: (focused) => setState(() {
                          _focusedDay = focused;
                          _selectedDay = null;
                        }),
                        calendarStyle: CalendarStyle(
                          outsideDaysVisible: false,
                          todayDecoration: BoxDecoration(
                            color: colorScheme.primary.withAlpha(38),
                            shape: BoxShape.circle,
                          ),
                          todayTextStyle: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                          selectedDecoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          markersMaxCount: 0,
                        ),
                        calendarBuilders: CalendarBuilders(
                          markerBuilder: (context, day, events) {
                            final memoTypes = _memosForDay(day);
                            if (events.isEmpty && memoTypes.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ...events.take(2).map((e) {
                                    final ev = e;
                                    final c = _spaceForEvent(ev).color;
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
                                        color: c.withAlpha(46),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        ev.title,
                                        style: TextStyle(
                                          fontSize: 8,
                                          color: c,
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
                                  if (memoTypes.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: memoTypes
                                            .map(
                                              (t) => Container(
                                                width: 5,
                                                height: 5,
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 1,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: t.color,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        headerStyle: const HeaderStyle(
                          formatButtonVisible: false,
                          leftChevronVisible: false,
                          rightChevronVisible: false,
                          titleCentered: false,
                          titleTextStyle: TextStyle(fontSize: 0),
                          headerPadding: EdgeInsets.zero,
                          headerMargin: EdgeInsets.zero,
                        ),
                      ),
                      // 날짜 패널
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
                                icon: const Icon(Icons.add),
                                onPressed: _showAddEvent,
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
                          child: _loadingDay
                              ? const Center(child: CircularProgressIndicator())
                              : _buildDayContent(allEvents),
                        ),
                      ],
                    ],
                  );
                },
              ),
              floatingActionButton: _selectedDay == null
                  ? FloatingActionButton(
                      onPressed: _showAddEvent,
                      child: const Icon(Icons.add),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

// ─── 섹션 라벨 ──────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
        ),
      ),
    );
  }
}

class _EventInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _EventInfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(31),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(89)),
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

class _EventInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _EventInfoRow({
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
