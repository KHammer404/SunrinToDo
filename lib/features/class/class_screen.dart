import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sunrintodo/features/class/class_colors.dart';

class ClassScreen extends StatefulWidget {
  final String? initialInviteCode;

  const ClassScreen({super.key, this.initialInviteCode});

  @override
  State<ClassScreen> createState() => _ClassScreenState();
}

class _ClassScreenState extends State<ClassScreen> {
  static final _db = FirebaseFirestore.instance;

  bool _handledInitialInviteCode = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final initialCode = widget.initialInviteCode;
    if (!_handledInitialInviteCode &&
        initialCode != null &&
        initialCode.isNotEmpty) {
      _handledInitialInviteCode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _joinClass(context, initialCode: initialCode);
      });
    }
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  String _displayNameFor(User user) {
    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return user.email ?? user.uid;
  }

  String _inviteLink(String code) => 'sunrintodo://class/join/$code';

  Future<void> _createClass(BuildContext context) async {
    final uid = _uid;
    final user = FirebaseAuth.instance.currentUser;
    if (uid == null || user == null) return;

    final ctrl = TextEditingController();
    var selectedColorValue = classColorValueForId(uid);
    final draft = await showDialog<_ClassDraft>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('학급 만들기'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '예: 1학년 3반, 정보통신과 2반',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '학급 색상',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final colorValue in kClassColorValues)
                      _ColorSwatchButton(
                        color: Color(colorValue),
                        selected: selectedColorValue == colorValue,
                        onTap: () =>
                            setDialog(() => selectedColorValue = colorValue),
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
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  ctx,
                  _ClassDraft(name: name, colorValue: selectedColorValue),
                );
              },
              child: const Text('만들기'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();

    if (draft == null) return;

    try {
      await _createClassWithUniqueInvite(uid: uid, user: user, draft: draft);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${draft.name} 학급을 만들었어요')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('학급 생성 실패: $error')));
    }
  }

  Future<void> _createClassWithUniqueInvite({
    required String uid,
    required User user,
    required _ClassDraft draft,
  }) async {
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final code = _generateCode();
      final classRef = _db.collection('classes').doc();
      final inviteRef = _db.collection('classInvites').doc(code);
      final existingInvite = await inviteRef.get();
      if (existingInvite.exists) continue;

      final batch = _db.batch();
      batch.set(classRef, {
        'name': draft.name,
        'inviteCode': code,
        'createdBy': uid,
        'memberIds': [uid],
        'memberNames': {uid: _displayNameFor(user)},
        'colorValue': draft.colorValue,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(inviteRef, {
        'code': code,
        'classId': classRef.id,
        'className': draft.name,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      try {
        await batch.commit();
        return;
      } on FirebaseException catch (error) {
        if (attempt == 7) rethrow;
        if (error.code != 'permission-denied' &&
            error.code != 'already-exists' &&
            error.code != 'aborted') {
          rethrow;
        }
      }
    }

    throw StateError('사용 가능한 초대 코드를 만들지 못했어요');
  }

  Future<void> _joinClass(BuildContext context, {String? initialCode}) async {
    final uid = _uid;
    final user = FirebaseAuth.instance.currentUser;
    if (uid == null || user == null) return;

    final code =
        initialCode?.trim().toUpperCase() ?? await _askInviteCode(context);
    if (code == null || code.isEmpty) return;

    try {
      final inviteDoc = await _db.collection('classInvites').doc(code).get();
      if (!context.mounted) return;

      if (!inviteDoc.exists) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('존재하지 않는 초대 코드예요')));
        return;
      }

      final invite = inviteDoc.data() ?? const <String, dynamic>{};
      final classId = invite['classId'] as String? ?? '';
      final className = invite['className'] as String? ?? '학급';
      if (classId.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('초대 정보가 올바르지 않아요')));
        return;
      }

      await _db.collection('classes').doc(classId).update({
        'memberIds': FieldValue.arrayUnion([uid]),
        'memberNames.$uid': _displayNameFor(user),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$className 학급에 참여했어요')));
      }
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      final message = error.code == 'permission-denied'
          ? '이미 참여 중이거나 참여할 수 없는 학급이에요'
          : '학급 참여 실패: ${error.message ?? error.code}';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('학급 참여 실패: $error')));
    }
  }

  Future<String?> _askInviteCode(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('초대 코드로 참여'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: '초대 코드 6자리',
            border: OutlineInputBorder(),
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().toUpperCase()),
            child: const Text('참여'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  Future<void> _leaveOrDeleteClass(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final uid = _uid;
    if (uid == null) return;

    final data = doc.data() ?? const <String, dynamic>{};
    final name = data['name'] as String? ?? '학급';
    final createdBy = data['createdBy'] as String? ?? '';
    final inviteCode = data['inviteCode'] as String? ?? '';
    final memberIds = List<String>.from(data['memberIds'] as List? ?? const []);
    final isOwner = createdBy == uid;

    if (isOwner) {
      if (memberIds.length > 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('방장은 멤버가 남아 있으면 학급을 나갈 수 없어요')),
        );
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('학급 삭제'),
          content: Text('$name 학급을 삭제할까요? 초대 링크도 함께 비활성화됩니다.'),
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
        final batch = _db.batch();
        batch.delete(doc.reference);
        if (inviteCode.isNotEmpty) {
          batch.delete(_db.collection('classInvites').doc(inviteCode));
        }
        await batch.commit();
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name 학급을 삭제했어요')));
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('학급 삭제 실패: $error')));
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('학급 나가기'),
        content: Text('$name 학급에서 나가시겠어요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await doc.reference.update({
        'memberIds': FieldValue.arrayRemove([uid]),
        'memberNames.$uid': FieldValue.delete(),
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$name 학급에서 나갔어요')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('학급 나가기 실패: $error')));
    }
  }

  Future<void> _changeClassColor(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data() ?? const <String, dynamic>{};
    var selectedColorValue =
        data['colorValue'] as int? ?? classColorValueForId(doc.id);

    final colorValue = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('학급 색상'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in kClassColorValues)
                _ColorSwatchButton(
                  color: Color(value),
                  selected: selectedColorValue == value,
                  onTap: () => setDialog(() => selectedColorValue = value),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selectedColorValue),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );

    if (colorValue == null) return;

    try {
      await doc.reference.update({'colorValue': colorValue});
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('학급 색상을 저장했어요')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('색상 저장 실패: $error')));
    }
  }

  Future<void> _shareInvite(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data() ?? const <String, dynamic>{};
    final name = data['name'] as String? ?? '학급';
    final code = data['inviteCode'] as String? ?? '';
    if (code.isEmpty) return;

    final link = _inviteLink(code);
    await Share.share(
      '$name 학급 초대\n$link\n초대 코드: $code',
      subject: 'SunrinToDo 학급 초대',
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;

    return Scaffold(
      appBar: AppBar(title: const Text('내 학급'), centerTitle: false),
      body: uid == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('classes')
                  .where('memberIds', arrayContains: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (docs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            '참여 중인 학급이 없어요\n아래 버튼으로 만들거나 참여해보세요',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[500],
                              height: 1.6,
                            ),
                          ),
                        ),
                      )
                    else
                      ...docs.map(
                        (doc) => _ClassCard(
                          doc: doc,
                          uid: uid,
                          onLeaveOrDelete: () =>
                              _leaveOrDeleteClass(context, doc),
                          onChangeColor: () => _changeClassColor(context, doc),
                          onShareInvite: () => _shareInvite(doc),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _createClass(context),
                      icon: const Icon(Icons.add),
                      label: const Text('학급 만들기'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _joinClass(context),
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('초대 코드로 참여'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _ClassDraft {
  final String name;
  final int colorValue;

  const _ClassDraft({required this.name, required this.colorValue});
}

class _ClassCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final String uid;
  final VoidCallback onLeaveOrDelete;
  final VoidCallback onChangeColor;
  final VoidCallback onShareInvite;

  const _ClassCard({
    required this.doc,
    required this.uid,
    required this.onLeaveOrDelete,
    required this.onChangeColor,
    required this.onShareInvite,
  });

  String _memberName(Map<String, String> memberNames, String memberId) {
    final name = memberNames[memberId]?.trim();
    if (name != null && name.isNotEmpty) return name;
    return '이름 없음';
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() ?? const <String, dynamic>{};
    final name = data['name'] as String? ?? '이름 없는 학급';
    final code = data['inviteCode'] as String? ?? '';
    final memberIds = List<String>.from(data['memberIds'] as List? ?? const []);
    final memberNames =
        (data['memberNames'] as Map<String, dynamic>? ?? const {}).map(
          (key, value) => MapEntry(key, value.toString()),
        );
    final createdBy = data['createdBy'] as String? ?? '';
    final isOwner = createdBy == uid;
    final classColor = classColorFromValue(data['colorValue'], doc.id);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: classColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isOwner)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(31),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '방장',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Row(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${memberIds.length}명',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ],
                ),
                children: [
                  for (final memberId in memberIds)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: memberId == createdBy
                                ? colorScheme.primary.withAlpha(31)
                                : colorScheme.surfaceContainerHighest,
                            child: Icon(
                              memberId == createdBy
                                  ? Icons.verified_user_outlined
                                  : Icons.person_outline,
                              size: 14,
                              color: memberId == createdBy
                                  ? colorScheme.primary
                                  : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _memberName(memberNames, memberId),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (memberId == uid)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '나',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          if (memberId == createdBy)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '방장',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    '초대 코드  ',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '초대 코드 복사',
                    icon: const Icon(Icons.copy, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('초대 코드 복사됨')),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: '초대 링크 공유',
                    icon: const Icon(Icons.ios_share, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: onShareInvite,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                if (isOwner)
                  TextButton.icon(
                    onPressed: onChangeColor,
                    icon: const Icon(Icons.palette_outlined, size: 18),
                    label: const Text('색상'),
                  ),
                TextButton(
                  onPressed: onLeaveOrDelete,
                  child: Text(
                    isOwner && memberIds.length == 1 ? '삭제' : '나가기',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatchButton extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatchButton({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 18)
            : null,
      ),
    );
  }
}
