import 'package:flutter/services.dart';

/// Thin bridge to app-specific Android code in `MainActivity.kt`.
///
/// Everything here is a no-op / permissive default off-Android so the rest of
/// the app stays platform-agnostic. Only callable from the UI isolate (the
/// background service isolate has no `MainActivity` engine registered).
class NativeBridge {
  NativeBridge._();
  static const MethodChannel _channel = MethodChannel('healthlink/native');

  /// Whether the OS has granted this app "Do Not Disturb access", which is the
  /// prerequisite for the alarm channel's [applyAlarmBypass] to take effect.
  static Future<bool> isDndAccessGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isDndAccessGranted') ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Opens the system screen where the user grants DND access. Returns once the
  /// settings screen has been launched (not when the user returns).
  static Future<void> openDndAccessSettings() async {
    try {
      await _channel.invokeMethod('openDndAccessSettings');
    } catch (_) {}
  }

  /// Rebuilds the alarm notification channel with `bypassDnd = true` so the
  /// alert rings even while Do Not Disturb is on. Only has effect once DND
  /// access is granted (channel DND-bypass is immutable after creation, so this
  /// deletes and recreates the channel). Returns whether bypass is now active.
  static Future<bool> applyAlarmBypass() async {
    try {
      return await _channel.invokeMethod<bool>('applyAlarmBypass') ?? false;
    } catch (_) {
      return false;
    }
  }
}
