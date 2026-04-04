package com.alexdev.myfinanceapp

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    companion object {
        /// Static sink: NotificationMonitorService posts events here directly.
        var notificationEventSink: EventChannel.EventSink? = null
    }

    private val permissionChannel = "com.alexdev.myfinanceapp/notification_permission"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // EventChannel: Flutter subscribes here; service posts via static sink
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NotificationMonitorService.CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    notificationEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    notificationEventSink = null
                }
            })

        // MethodChannel: permission helpers + bank filter
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" -> result.success(isNotificationListenerEnabled())
                    "openPermissionSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "setAllowedPackages" -> {
                        val packages = call.argument<List<String>>("packages") ?: emptyList()
                        NotificationMonitorService.allowedPackages = packages.toSet()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        return enabledListeners.contains(packageName)
    }
}
