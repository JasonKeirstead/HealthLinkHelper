import 'dart:convert';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../api/booking_repository.dart';
import '../auth/auth_controller.dart';
import '../config.dart';
import '../models/enums.dart';
import '../models/models.dart';
import '../notifications/notifier.dart';
import 'last_found.dart';
import 'scanner.dart';

const String _kReqKey = 'monitor_request_v1';

/// Entry point for the background isolate that runs the foreground-service task.
@pragma('vm:entry-point')
void monitorTaskCallback() {
  // This isolate has its own plugin registry. Without this, plugin channels
  // (secure storage, local notifications) throw MissingPluginException here.
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_MonitorTaskHandler());
}

/// Runs in a separate isolate as a foreground service. Rebuilds the API stack
/// from secure storage and re-runs the scan on each interval; on a hit it fires
/// a high-priority notification and stops the service.
class _MonitorTaskHandler extends TaskHandler {
  AvailabilityScanner? _scanner;
  ScanRequest? _request;
  bool _alarm = false;
  bool _busy = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final auth = AuthController();
    if (!await auth.restore()) return; // no persisted session
    _scanner = AvailabilityScanner(
      BookingRepository(EbbApi(DirectGraphQLTransport(), auth)),
    );
    final raw = await FlutterForegroundTask.getData<String>(key: _kReqKey);
    if (raw != null) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _request = _decode(m);
      _alarm = (m['alarm'] as bool?) ?? false;
    }
    try {
      await Notifier.instance.init();
    } catch (_) {}
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _tick();
  }

  Future<void> _tick() async {
    final scanner = _scanner;
    final req = _request;
    if (scanner == null || req == null || _busy) return;
    _busy = true;
    try {
      final results = await scanner.scan(req);
      final found = results.where((r) => r.hasAvailability).toList()
        ..sort((a, b) => a.earliest!.compareTo(b.earliest!));
      if (found.isNotEmpty) {
        final best = found.first;
        final label = DateFormat.MMMEd().format(best.earliest!);
        final bookingUrl = EbbConfig.bookingUrl(req.patient.accountId).toString();

        // Record what was found first, so the app screen can show it even if the
        // notification itself is suppressed (e.g. by Do Not Disturb).
        try {
          await LastFoundStore().save(LastFound(
            locationName: best.location.displayName,
            city: best.location.city,
            earliest: best.earliest!,
            foundAt: DateTime.now(),
            bookingUrl: bookingUrl,
          ));
        } catch (_) {}

        // The alert is its own notification on a high-priority channel — the
        // ongoing service notification below is LOW/silent by design.
        var alerted = true;
        try {
          await Notifier.instance
              .showSlotFound(best, label, alarm: _alarm, bookingUrl: bookingUrl);
        } catch (_) {
          alerted = false;
        }
        FlutterForegroundTask.updateService(
          notificationTitle: 'Appointment available!',
          notificationText: alerted
              ? '${best.location.displayName} — $label'
              : '${best.location.displayName} — $label (alert failed — tap to open)',
        );
        await FlutterForegroundTask.stopService();
      } else {
        FlutterForegroundTask.updateService(
          notificationTitle: 'Watching for openings',
          notificationText:
              'No openings yet · last checked ${DateFormat.jm().format(DateTime.now())}',
        );
      }
    } catch (_) {
      // transient (e.g. token refresh / network) — keep watching
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  ScanRequest _decode(Map<String, dynamic> m) {
    return ScanRequest(
      patient: Patient(
        accountId: m['a'] as String,
        chartId: m['c'] as String,
        fullName: m['n'] as String,
      ),
      issueName: m['i'] as String,
      modality: Modality.values[m['m'] as int],
      monthsAhead: m['mo'] as int,
      includeLocationIds: (m['l'] as List?)?.map((e) => e as String).toSet(),
    );
  }
}

/// UI-facing control for the background monitor (a foreground service).
class AppointmentMonitor {
  AppointmentMonitor._();

  static void _init(Duration interval) {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'appointment_watch',
        channelName: 'Appointment watch',
        channelDescription: 'Ongoing notification while checking for openings.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(interval.inMilliseconds),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  static Future<void> start(ScanRequest req, Duration interval, {bool alarm = false}) async {
    // Notifications for the ongoing + "found" alerts; battery exemption helps
    // aggressive OEMs (e.g. Samsung) keep the service alive.
    await FlutterForegroundTask.requestNotificationPermission();
    try {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (_) {}

    _init(interval);
    await FlutterForegroundTask.saveData(key: _kReqKey, value: _encode(req, alarm));
    await FlutterForegroundTask.startService(
      notificationTitle: 'Watching for openings',
      notificationText: 'Checking every ${interval.inMinutes} min…',
      callback: monitorTaskCallback,
    );
  }

  static Future<void> stop() => FlutterForegroundTask.stopService();

  static String _encode(ScanRequest r, bool alarm) => jsonEncode({
        'a': r.patient.accountId,
        'c': r.patient.chartId,
        'n': r.patient.fullName,
        'i': r.issueName,
        'm': r.modality.index,
        'mo': r.monthsAhead,
        'l': r.includeLocationIds?.toList(),
        'alarm': alarm,
      });
}
