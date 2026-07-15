import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'src/app.dart';
import 'src/auth/auth_controller.dart';
import 'src/notifications/notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  try {
    await Notifier.instance.init();
  } catch (_) {
    // Notifications are non-critical; continue without them.
  }
  final auth = AuthController();
  await auth.restore();
  runApp(HealthLinkApp(auth: auth));
}
