import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/models.dart';

/// Local notifications for the "slot found" alert.
///
/// Alerts are posted as their own notification (id [_alertId]) on channels
/// separate from the ongoing foreground-service notification, so Android can
/// rank/prioritize them independently and the user can tune them per-channel.
class Notifier {
  Notifier._();
  static final Notifier instance = Notifier._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Distinct from the foreground service's notification id (1000).
  static const int _alertId = 8801;

  static const String _channelId = 'slot_alerts_v2';
  static const String _channelName = 'Appointment found';
  static const String _channelDesc =
      'High-priority alert when an appointment slot becomes available';

  static const String _alarmChannelId = 'slot_alarm_v2';
  static const String _alarmChannelName = 'Appointment found (alarm)';
  static const String _alarmChannelDesc =
      'Loud alarm that rings until dismissed when an appointment slot becomes available';

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

    // High-priority "found" channel (sound + heads-up).
    await android_?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    ));
    // Loud alarm channel — alarm audio stream (loud, cuts through vibrate/DND).
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
    try {
      await android?.requestFullScreenIntentPermission();
    } catch (_) {}
    final ios =
        _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final iosGranted = await ios?.requestPermissions(alert: true, badge: true, sound: true);
    return androidGranted ?? iosGranted ?? true;
  }

  Future<void> showSlotFound(LocationAvailability r, String dateLabel, {required bool alarm}) =>
      _showAlert(
        title: alarm ? 'Appointment available!' : 'Appointment available',
        body: '${r.location.shortLabel} — soonest $dateLabel. Open the app to book.',
        alarm: alarm,
      );

  /// Fire a sample alert so the user can verify sound/priority settings.
  Future<void> showTest({required bool alarm}) => _showAlert(
        title: alarm ? 'Test alarm' : 'Test alert',
        body: alarm
            ? 'This is how it will ring when a slot opens. Dismiss to stop.'
            : 'This is how you\'ll be notified when a slot opens.',
        alarm: alarm,
      );

  Future<void> _showAlert({
    required String title,
    required String body,
    required bool alarm,
  }) async {
    await init();
    await _plugin.show(
      _alertId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          alarm ? _alarmChannelId : _channelId,
          alarm ? _alarmChannelName : _channelName,
          channelDescription: alarm ? _alarmChannelDesc : _channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          category: alarm ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
          audioAttributesUsage:
              alarm ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
          fullScreenIntent: alarm,
          enableVibration: true,
          playSound: true,
          // FLAG_INSISTENT: repeat the sound until the notification is dismissed.
          additionalFlags: alarm ? Int32List.fromList(<int>[4]) : null,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel:
              alarm ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
        ),
      ),
    );
  }
}
