import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  int _locationToIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return switch (location) {
      '/timetable' => 0,
      '/meal' => 1,
      '/calendar' => 2,
      '/school-schedule' => 3,
      '/settings' => 4,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _locationToIndex(context),
        onDestinationSelected: (index) {
          switch (index) {
            case 0: context.go('/timetable');
            case 1: context.go('/meal');
            case 2: context.go('/calendar');
            case 3: context.go('/school-schedule');
            case 4: context.go('/settings');
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view), label: '시간표'),
          NavigationDestination(icon: Icon(Icons.restaurant), label: '급식'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: '캘린더'),
          NavigationDestination(icon: Icon(Icons.event_note), label: '학사일정'),
          NavigationDestination(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}
