import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sunrintodo/core/router/app_router.dart';
import 'package:sunrintodo/core/services/notification_sync_service.dart';
import 'package:sunrintodo/core/theme/app_theme.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationSyncService.instance.initialize();
  runApp(const SunrinApp());
}

class SunrinApp extends StatelessWidget {
  const SunrinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SunrinToDo',
      theme: buildAppTheme(),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
