import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_services.dart';
import 'sync/background_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundSync.initialize(); // registra el callbackDispatcher de WorkManager
  final services = await AppServices.create();
  runApp(OfflineFirstApp(services: services));
}
