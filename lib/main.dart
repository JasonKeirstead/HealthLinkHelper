import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:url_launcher/url_launcher.dart';

import 'src/app.dart';
import 'src/auth/auth_controller.dart';
import 'src/notifications/notifier.dart';

Future<void> _openBookingUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  // externalApplication lets the installed TH Connect app handle it via App
  // Links, falling back to the browser.
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  // Tapping a "slot found" alert opens the TH Connect booking page.
  Notifier.instance.onTap = _openBookingUrl;
  try {
    await Notifier.instance.init();
    // If a tap on the alert cold-started the app, act on it now.
    final payload = await Notifier.instance.launchPayload();
    if (payload != null) _openBookingUrl(payload);
  } catch (_) {
    // Notifications are non-critical; continue without them.
  }
  final auth = AuthController();
  await auth.restore();
  runApp(HealthLinkApp(auth: auth));
}
