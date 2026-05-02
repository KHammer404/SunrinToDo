import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:go_router/go_router.dart';
import 'package:sunrintodo/core/services/notification_sync_service.dart';
import 'package:sunrintodo/features/settings/settings_preferences.dart';

enum _SystemNotificationPermission {
  loading,
  authorized,
  provisional,
  denied,
  notDetermined,
  unavailable,
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final SettingsPreferences _preferences = SettingsPreferences();

  AppSettingsData? _settings;
  bool _loading = true;
  bool _saving = false;
  bool _requestingPermission = false;
  _SystemNotificationPermission _systemPermission =
      _SystemNotificationPermission.loading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSystemPermission();
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await NotificationSyncService.instance.removeCurrentTokenForCurrentUser();
    } catch (_) {}
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
    if (context.mounted) context.go('/auth');
  }

  Future<void> _loadSettings() async {
    final settings = await _preferences.load();
    final permission = await _getSystemPermission();
    final permissionKey = _permissionStatusKey(permission);

    try {
      await NotificationSyncService.instance.syncSettings(
        settings,
        permissionStatus: permissionKey,
      );
    } catch (_) {}

    if (!mounted) {
      return;
    }

    setState(() {
      _settings = settings;
      _systemPermission = permission;
      _loading = false;
    });
  }

  Future<void> _refreshSystemPermission() async {
    final permission = await _getSystemPermission();
    final permissionKey = _permissionStatusKey(permission);
    if (!mounted) {
      return;
    }
    setState(() {
      _systemPermission = permission;
    });
    final settings = _settings;
    if (settings == null) {
      return;
    }
    try {
      await NotificationSyncService.instance.syncSettings(
        settings,
        permissionStatus: permissionKey,
      );
    } catch (_) {}
  }

  Future<_SystemNotificationPermission> _getSystemPermission() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return _mapAuthorizationStatus(settings.authorizationStatus);
    } catch (_) {
      return _SystemNotificationPermission.unavailable;
    }
  }

  _SystemNotificationPermission _mapAuthorizationStatus(
    AuthorizationStatus status,
  ) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return _SystemNotificationPermission.authorized;
      case AuthorizationStatus.provisional:
        return _SystemNotificationPermission.provisional;
      case AuthorizationStatus.denied:
        return _SystemNotificationPermission.denied;
      case AuthorizationStatus.notDetermined:
        return _SystemNotificationPermission.notDetermined;
    }
  }

  String _permissionStatusKey(_SystemNotificationPermission permission) {
    switch (permission) {
      case _SystemNotificationPermission.authorized:
        return 'authorized';
      case _SystemNotificationPermission.provisional:
        return 'provisional';
      case _SystemNotificationPermission.denied:
        return 'denied';
      case _SystemNotificationPermission.notDetermined:
        return 'not_determined';
      case _SystemNotificationPermission.loading:
        return 'loading';
      case _SystemNotificationPermission.unavailable:
        return 'unavailable';
    }
  }

  bool get _isSystemPermissionAllowed =>
      _systemPermission == _SystemNotificationPermission.authorized ||
      _systemPermission == _SystemNotificationPermission.provisional;

  bool get _canRequestPermission =>
      _systemPermission == _SystemNotificationPermission.denied ||
      _systemPermission == _SystemNotificationPermission.notDetermined;

  Future<void> _updateSettings(AppSettingsData next) async {
    final previous = _settings;

    setState(() {
      _settings = next;
      _saving = true;
    });

    try {
      await _preferences.save(next);
      final permissionKey = _permissionStatusKey(_systemPermission);
      await NotificationSyncService.instance.syncSettings(
        next,
        permissionStatus: permissionKey,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = previous;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('설정을 저장하지 못했어요')));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _pickMealNotificationTime() async {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: settings.mealNotificationHour,
        minute: settings.mealNotificationMinute,
      ),
      helpText: '급식 알림 시간',
    );

    if (picked == null) {
      return;
    }

    await _updateSettings(
      settings.copyWith(
        mealNotificationHour: picked.hour,
        mealNotificationMinute: picked.minute,
      ),
    );
  }

  Future<void> _requestSystemPermission() async {
    setState(() {
      _requestingPermission = true;
    });

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      final permission = _mapAuthorizationStatus(settings.authorizationStatus);

      if (!mounted) {
        return;
      }

      setState(() {
        _systemPermission = permission;
      });
      final settingsData = _settings;
      if (settingsData != null) {
        final permissionKey = _permissionStatusKey(permission);
        try {
          await NotificationSyncService.instance.syncSettings(
            settingsData,
            permissionStatus: permissionKey,
          );
        } catch (_) {}
      }

      final granted =
          permission == _SystemNotificationPermission.authorized ||
          permission == _SystemNotificationPermission.provisional;

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted ? '알림 권한이 확인됐어요' : '시스템 알림 권한이 아직 꺼져 있어요'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('권한 상태를 확인하지 못했어요')));
    } finally {
      if (mounted) {
        setState(() {
          _requestingPermission = false;
        });
      }
    }
  }

  String _formatTime(BuildContext context, AppSettingsData settings) {
    final time = TimeOfDay(
      hour: settings.mealNotificationHour,
      minute: settings.mealNotificationMinute,
    );
    return time.format(context);
  }

  String _permissionLabel() {
    switch (_systemPermission) {
      case _SystemNotificationPermission.loading:
        return '확인 중';
      case _SystemNotificationPermission.authorized:
        return '허용됨';
      case _SystemNotificationPermission.provisional:
        return '임시 허용';
      case _SystemNotificationPermission.denied:
        return '거부됨';
      case _SystemNotificationPermission.notDetermined:
        return '미설정';
      case _SystemNotificationPermission.unavailable:
        return '확인 불가';
    }
  }

  String _permissionDescription() {
    switch (_systemPermission) {
      case _SystemNotificationPermission.loading:
        return '기기 알림 권한 상태를 불러오고 있어요.';
      case _SystemNotificationPermission.authorized:
        return '기기에서 알림 표시가 허용되어 있어요.';
      case _SystemNotificationPermission.provisional:
        return '조용한 알림 형태로 일부 허용되어 있어요.';
      case _SystemNotificationPermission.denied:
        return '앱 내 설정이 켜져 있어도 실제 알림은 오지 않아요.';
      case _SystemNotificationPermission.notDetermined:
        return '아직 시스템 알림 권한을 요청하지 않았어요.';
      case _SystemNotificationPermission.unavailable:
        return '이 기기에서는 시스템 알림 권한 상태를 바로 확인할 수 없어요.';
    }
  }

  Color _permissionColor(ColorScheme colorScheme) {
    switch (_systemPermission) {
      case _SystemNotificationPermission.authorized:
        return colorScheme.primary;
      case _SystemNotificationPermission.provisional:
        return colorScheme.secondary;
      case _SystemNotificationPermission.denied:
        return colorScheme.error;
      case _SystemNotificationPermission.notDetermined:
        return colorScheme.tertiary;
      case _SystemNotificationPermission.loading:
      case _SystemNotificationPermission.unavailable:
        return colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final settings = _settings!;
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '이메일 정보 없음';
    final displayName = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : email.split('@').first;
    final colorScheme = Theme.of(context).colorScheme;
    final shouldShowPermissionNotice =
        settings.hasAnyEnabledNotificationSetting &&
        !_isSystemPermissionAllowed &&
        _systemPermission != _SystemNotificationPermission.loading &&
        _systemPermission != _SystemNotificationPermission.unavailable;

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle('계정'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorScheme.primary.withValues(
                      alpha: 0.12,
                    ),
                    foregroundColor: colorScheme.primary,
                    child: const Icon(Icons.person_outline),
                  ),
                  title: Text(displayName),
                  subtitle: Text(email),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('학교 계정 도메인'),
                  subtitle: const Text('sunrint.hs.kr'),
                  trailing: Text(
                    email.contains('@') ? email.split('@').last : '-',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle('알림'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('시스템 알림 권한'),
                  subtitle: Text(_permissionDescription()),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _permissionColor(
                        colorScheme,
                      ).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _permissionLabel(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _permissionColor(colorScheme),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _refreshSystemPermission,
                        icon: const Icon(Icons.refresh),
                        label: const Text('새로고침'),
                      ),
                      const SizedBox(width: 8),
                      if (_canRequestPermission)
                        FilledButton.icon(
                          onPressed: _requestingPermission
                              ? null
                              : _requestSystemPermission,
                          icon: const Icon(Icons.notifications_outlined),
                          label: Text(_requestingPermission ? '요청 중' : '권한 요청'),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  value: settings.mealNotificationsEnabled,
                  onChanged: (value) {
                    _updateSettings(
                      settings.copyWith(mealNotificationsEnabled: value),
                    );
                  },
                  title: const Text('급식 알림'),
                  subtitle: Text(
                    settings.mealNotificationsEnabled
                        ? '현재 ${_formatTime(context, settings)}에 알림'
                        : '급식 안내 알림을 끕니다',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  enabled: settings.mealNotificationsEnabled,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('급식 알림 시간'),
                  subtitle: const Text('앱 내 기본 급식 알림 시간'),
                  trailing: Text(
                    _formatTime(context, settings),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: settings.mealNotificationsEnabled
                          ? colorScheme.onSurface
                          : colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  onTap: settings.mealNotificationsEnabled
                      ? _pickMealNotificationTime
                      : null,
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  value: settings.examReminderDefaultEnabled,
                  onChanged: (value) {
                    _updateSettings(
                      settings.copyWith(examReminderDefaultEnabled: value),
                    );
                  },
                  title: const Text('시험 일정 기본 알림'),
                  subtitle: const Text('시험 카테고리 일정 생성 시 기본값으로 사용'),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  value: settings.performanceReminderDefaultEnabled,
                  onChanged: (value) {
                    _updateSettings(
                      settings.copyWith(
                        performanceReminderDefaultEnabled: value,
                      ),
                    );
                  },
                  title: const Text('수행평가 일정 기본 알림'),
                  subtitle: const Text('수행평가 카테고리 일정 생성 시 기본값으로 사용'),
                ),
              ],
            ),
          ),
          if (shouldShowPermissionNotice) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '앱 내 알림 설정은 저장되지만, 시스템 권한이 꺼져 있으면 실제 알림은 표시되지 않아요.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.storage_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '현재 설정은 이 기기에 먼저 저장됩니다. 실제 푸시 발송은 이후 FCM/백엔드 작업과 연결될 예정입니다.',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle('내 학급'),
          Card(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('classes')
                  .where('memberIds', arrayContains: user?.uid ?? '')
                  .snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final names = docs
                    .map(
                      (doc) =>
                          ((doc.data() as Map<String, dynamic>)['name']
                              as String?) ??
                          '',
                    )
                    .where((name) => name.isNotEmpty)
                    .toList();
                final summary = names.isEmpty
                    ? '참여 중인 학급이 없어요'
                    : names.take(3).join(' · ');
                final trailingSummary = names.length > 3
                    ? ' 외 ${names.length - 3}개'
                    : '';

                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.group_outlined),
                      title: const Text('내 학급 관리'),
                      subtitle: Text(
                        snapshot.connectionState == ConnectionState.waiting
                            ? '참여 중인 학급을 불러오고 있어요'
                            : '$summary$trailingSummary',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/class'),
                    ),
                    if (names.isNotEmpty) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: names
                              .take(4)
                              .map(
                                (name) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('로그아웃', style: TextStyle(color: Colors.red)),
              leading: const Icon(Icons.logout, color: Colors.red),
              onTap: () => _signOut(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;

  const _SectionTitle(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}
