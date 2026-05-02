import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:sunrintodo/core/router/app_router.dart';
import 'package:sunrintodo/features/settings/settings_preferences.dart';

class NotificationSyncService {
  NotificationSyncService._();

  static final NotificationSyncService instance = NotificationSyncService._();

  final SettingsPreferences _preferences = SettingsPreferences();

  bool _initialized = false;
  String? _cachedToken;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
    } catch (_) {}

    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        return;
      }
      unawaited(syncCurrentUserDocument());
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _cachedToken = token;
      unawaited(syncCurrentUserDocument(forceToken: token));
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handleInitialMessage());
    });

    _cachedToken = await _safeGetToken();
    await syncCurrentUserDocument(forceToken: _cachedToken);
  }

  Future<void> _handleInitialMessage() async {
    try {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) {
        _handleOpenedMessage(message);
      }
    } catch (_) {}
  }

  void _handleOpenedMessage(RemoteMessage message) {
    final destination = _destinationForMessageData(message.data);
    appRouter.go(destination);
  }

  String _destinationForMessageData(Map<String, dynamic> data) {
    final route = data['route']?.toString();
    if (route == 'meal') {
      return '/meal';
    }
    if (route == 'calendar') {
      return '/calendar';
    }

    final type = data['type']?.toString();
    if (type == 'meal') {
      return '/meal';
    }
    return '/calendar';
  }

  Future<String?> _safeGetToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  static String permissionStatusKey(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return 'authorized';
      case AuthorizationStatus.provisional:
        return 'provisional';
      case AuthorizationStatus.denied:
        return 'denied';
      case AuthorizationStatus.notDetermined:
        return 'not_determined';
    }
  }

  Future<String> getCurrentPermissionStatusKey() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return permissionStatusKey(settings.authorizationStatus);
    } catch (_) {
      return 'unavailable';
    }
  }

  Map<String, dynamic> _notificationSettingsMap(AppSettingsData settings) {
    return {
      'mealEnabled': settings.mealNotificationsEnabled,
      'mealHour': settings.mealNotificationHour,
      'mealMinute': settings.mealNotificationMinute,
      'examEnabled': settings.examReminderDefaultEnabled,
      'performanceEnabled': settings.performanceReminderDefaultEnabled,
    };
  }

  String? _schoolDomain(String? email) {
    if (email == null || !email.contains('@')) {
      return null;
    }
    return email.split('@').last;
  }

  Future<void> syncCurrentUserDocument({
    AppSettingsData? settings,
    String? permissionStatus,
    String? forceToken,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final resolvedSettings = settings ?? await _preferences.load();
    final resolvedPermission =
        permissionStatus ?? await getCurrentPermissionStatusKey();
    final token = forceToken ?? _cachedToken ?? await _safeGetToken();

    final data = <String, dynamic>{
      'displayName': user.displayName ?? '',
      'email': user.email ?? '',
      'schoolDomain': _schoolDomain(user.email),
      'notificationPermission': resolvedPermission,
      'notificationSettings': _notificationSettingsMap(resolvedSettings),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (token != null && token.isNotEmpty) {
      data['fcmTokens'] = FieldValue.arrayUnion([token]);
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set(data, SetOptions(merge: true));
  }

  Future<void> syncSettings(
    AppSettingsData settings, {
    String? permissionStatus,
  }) async {
    await syncCurrentUserDocument(
      settings: settings,
      permissionStatus: permissionStatus,
    );
  }

  Future<void> removeCurrentTokenForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final token = _cachedToken ?? await _safeGetToken();
    if (token == null || token.isEmpty) {
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'fcmTokens': FieldValue.arrayRemove([token]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
