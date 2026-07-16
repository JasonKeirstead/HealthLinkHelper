import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/models.dart';

/// Thin wrapper over local notifications for the "slot found" alert.
class Notifier {
  Notifier._();
  static final Notifier instance = Notifier._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'slot_alerts';
  static const String _channelName = 'Appointment alerts';
  static const String _channelDesc = 'High-priority alerts when an appointment slot opens up';

  static const String _alarmChannelId = 'slot_alarm';
  static const String _alarmChannelName = 'Appointment alarm';
  static const String _alarmChannelDesc =
      'Loud alarm that rings until dismissed when a slot opens up';

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));

    final android_ =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    // Standard alert channel.
    await android_?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
    ));
    // Loud alarm channel — plays on the alarm audio stream (loud, cuts through
    // vibrate/DND), vibrates, at max importance.
    await android_?.createNotificationChannel(const AndroidNotificationChannel(
      _alarmChannelId,
      _alarmChannelName,
      description: _alarmChannelDesc,
      importance: Importance.max,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      playSound: true,
      enableVibration: true,
    ));
    _initialized = true;
  }

  /// Ask for notification (and best-effort full-screen-intent) permission.
  Future<bool> requestPermission() async {
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final androidGranted = await android?.requestNotificationsPermission();
    // Needed on Android 14+ for the alarm alert to pop over the lock screen.
    try {
      await android?.requestFullScreenIntentPermission();
    } catch (_) {}
    final ios =
        _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return androidGranted ?? iosGranted ?? true;
  }

  /// A normal high-priority notification.
  Future<void> showSlotFound(LocationAvailability r, String dateLabel) async {
    await _plugin.show(
      1,
      'Appointment available',
      '${r.location.shortLabel} — soonest $dateLabel. Tap to open the app and book.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  /// A loud alarm that keeps ringing until the user dismisses the notification.
  Future<void> showSlotAlarm(LocationAvailability r, String dateLabel) async {
    await _plugin.show(
      1,
      'Appointment available!',
      '${r.location.shortLabel} — soonest $dateLabel. Open the app to book.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _alarmChannelId,
          _alarmChannelName,
          channelDescription: _alarmChannelDesc,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          fullScreenIntent: true,
          enableVibration: true,
          playSound: true,
          // FLAG_INSISTENT: repeat the sound until the notification is dismissed.
          additionalFlags: Int32List.fromList(<int>[4]),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
  }
}
