import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsData {
  static const int defaultMealNotificationHour = 7;
  static const int defaultMealNotificationMinute = 30;

  final bool mealNotificationsEnabled;
  final int mealNotificationHour;
  final int mealNotificationMinute;
  final bool examReminderDefaultEnabled;
  final bool performanceReminderDefaultEnabled;

  const AppSettingsData({
    required this.mealNotificationsEnabled,
    required this.mealNotificationHour,
    required this.mealNotificationMinute,
    required this.examReminderDefaultEnabled,
    required this.performanceReminderDefaultEnabled,
  });

  factory AppSettingsData.defaults() {
    return const AppSettingsData(
      mealNotificationsEnabled: false,
      mealNotificationHour: defaultMealNotificationHour,
      mealNotificationMinute: defaultMealNotificationMinute,
      examReminderDefaultEnabled: true,
      performanceReminderDefaultEnabled: true,
    );
  }

  factory AppSettingsData.fromPreferences(SharedPreferences prefs) {
    final defaults = AppSettingsData.defaults();
    return AppSettingsData(
      mealNotificationsEnabled:
          prefs.getBool(SettingsPreferences.mealNotificationsEnabledKey) ??
          defaults.mealNotificationsEnabled,
      mealNotificationHour:
          prefs.getInt(SettingsPreferences.mealNotificationHourKey) ??
          defaults.mealNotificationHour,
      mealNotificationMinute:
          prefs.getInt(SettingsPreferences.mealNotificationMinuteKey) ??
          defaults.mealNotificationMinute,
      examReminderDefaultEnabled:
          prefs.getBool(SettingsPreferences.examReminderDefaultEnabledKey) ??
          defaults.examReminderDefaultEnabled,
      performanceReminderDefaultEnabled:
          prefs.getBool(
            SettingsPreferences.performanceReminderDefaultEnabledKey,
          ) ??
          defaults.performanceReminderDefaultEnabled,
    );
  }

  AppSettingsData copyWith({
    bool? mealNotificationsEnabled,
    int? mealNotificationHour,
    int? mealNotificationMinute,
    bool? examReminderDefaultEnabled,
    bool? performanceReminderDefaultEnabled,
  }) {
    return AppSettingsData(
      mealNotificationsEnabled:
          mealNotificationsEnabled ?? this.mealNotificationsEnabled,
      mealNotificationHour: mealNotificationHour ?? this.mealNotificationHour,
      mealNotificationMinute:
          mealNotificationMinute ?? this.mealNotificationMinute,
      examReminderDefaultEnabled:
          examReminderDefaultEnabled ?? this.examReminderDefaultEnabled,
      performanceReminderDefaultEnabled:
          performanceReminderDefaultEnabled ??
          this.performanceReminderDefaultEnabled,
    );
  }

  bool get hasAnyEnabledNotificationSetting =>
      mealNotificationsEnabled ||
      examReminderDefaultEnabled ||
      performanceReminderDefaultEnabled;
}

class SettingsPreferences {
  static const String mealNotificationsEnabledKey =
      'settings.meal_notifications_enabled';
  static const String mealNotificationHourKey =
      'settings.meal_notification_hour';
  static const String mealNotificationMinuteKey =
      'settings.meal_notification_minute';
  static const String examReminderDefaultEnabledKey =
      'settings.exam_reminder_default_enabled';
  static const String performanceReminderDefaultEnabledKey =
      'settings.performance_reminder_default_enabled';

  Future<AppSettingsData> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettingsData.fromPreferences(prefs);
  }

  Future<void> save(AppSettingsData settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      mealNotificationsEnabledKey,
      settings.mealNotificationsEnabled,
    );
    await prefs.setInt(mealNotificationHourKey, settings.mealNotificationHour);
    await prefs.setInt(
      mealNotificationMinuteKey,
      settings.mealNotificationMinute,
    );
    await prefs.setBool(
      examReminderDefaultEnabledKey,
      settings.examReminderDefaultEnabled,
    );
    await prefs.setBool(
      performanceReminderDefaultEnabledKey,
      settings.performanceReminderDefaultEnabled,
    );
  }
}
