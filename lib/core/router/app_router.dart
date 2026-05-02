import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sunrintodo/features/auth/auth_screen.dart';
import 'package:sunrintodo/features/auth/domain_error_screen.dart';
import 'package:sunrintodo/core/router/redirect_utils.dart';
import 'package:sunrintodo/features/calendar/calendar_screen.dart';
import 'package:sunrintodo/features/calendar/group_events_screen.dart';
import 'package:sunrintodo/features/class/class_screen.dart';
import 'package:sunrintodo/features/meal/meal_screen.dart';
import 'package:sunrintodo/features/schedule/schedule_screen.dart';
import 'package:sunrintodo/features/settings/settings_screen.dart';
import 'package:sunrintodo/features/timetable/timetable_screen.dart';
import 'package:sunrintodo/shell/main_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/calendar',
  redirect: (context, state) {
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    final isAuthRoute =
        state.matchedLocation == '/auth' ||
        state.matchedLocation == '/domain-error';
    if (!loggedIn && !isAuthRoute) {
      return '/auth?from=${Uri.encodeComponent(state.uri.toString())}';
    }
    if (loggedIn && state.matchedLocation == '/auth') {
      return safeRedirectPath(state.uri.queryParameters['from']) ?? '/calendar';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
    GoRoute(
      path: '/domain-error',
      builder: (context, state) => const DomainErrorScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/timetable',
          builder: (context, state) => const TimetableScreen(),
        ),
        GoRoute(path: '/meal', builder: (context, state) => const MealScreen()),
        GoRoute(
          path: '/calendar',
          builder: (context, state) => const CalendarScreen(),
        ),
        GoRoute(
          path: '/school-schedule',
          builder: (context, state) => const ScheduleScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(path: '/class', builder: (context, state) => const ClassScreen()),
    GoRoute(
      path: '/class/join/:code',
      builder: (context, state) =>
          ClassScreen(initialInviteCode: state.pathParameters['code']),
    ),
    GoRoute(
      path: '/join/:code',
      builder: (context, state) =>
          ClassScreen(initialInviteCode: state.pathParameters['code']),
    ),
    GoRoute(
      path: '/group',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return GroupEventsScreen(
          classId: extra['classId'] as String,
          name: extra['name'] as String,
          color: extra['color'] as Color,
        );
      },
    ),
  ],
);
