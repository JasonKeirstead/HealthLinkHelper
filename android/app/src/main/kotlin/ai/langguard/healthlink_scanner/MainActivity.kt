package ai.langguard.healthlink_scanner

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        // Kept in sync with Notifier._alarmChannelId (Dart side).
        const val ALARM_CHANNEL_ID = "slot_alarm_v3"
        const val ALARM_CHANNEL_NAME = "Appointment found (alarm)"
        const val ALARM_CHANNEL_DESC =
            "Loud alarm that rings until dismissed when an appointment slot becomes available"
        const val CHANNEL = "healthlink/native"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Own the alarm channel natively so we can set DND-bypass, which
        // flutter_local_notifications cannot express.
        createAlarmChannel(bypassDnd = isDndAccessGranted())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "isDndAccessGranted" -> result.success(isDndAccessGranted())
                "openDndAccessSettings" -> {
                    openDndAccessSettings()
                    result.success(null)
                }
                "applyAlarmBypass" -> {
                    val granted = isDndAccessGranted()
                    if (granted) {
                        // DND-bypass is immutable after channel creation, so
                        // delete and recreate it with bypass enabled.
                        notificationManager().deleteNotificationChannel(ALARM_CHANNEL_ID)
                        createAlarmChannel(bypassDnd = true)
                    }
                    result.success(granted)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun isDndAccessGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return notificationManager().isNotificationPolicyAccessGranted
    }

    private fun openDndAccessSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun createAlarmChannel(bypassDnd: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            ALARM_CHANNEL_ID,
            ALARM_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        )
        channel.description = ALARM_CHANNEL_DESC
        channel.enableVibration(true)
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        channel.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), attrs)
        // Only honored by the OS when DND access is granted; harmless otherwise.
        if (bypassDnd) channel.setBypassDnd(true)
        notificationManager().createNotificationChannel(channel)
    }
}
