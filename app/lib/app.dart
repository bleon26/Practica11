import 'package:flutter/material.dart';

import 'core/app_services.dart';
import 'data/remote/api_client.dart';
import 'ui/login_page.dart';
import 'ui/tasks_page.dart';

class OfflineFirstApp extends StatelessWidget {
  const OfflineFirstApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0284C7);
    return MaterialApp(
      title: 'Offline-First Tasks',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: ValueListenableBuilder<AuthSession?>(
        valueListenable: services.auth.session,
        builder: (context, session, _) => session == null
            ? LoginPage(services: services)
            : TasksPage(services: services, session: session),
      ),
    );
  }
}
