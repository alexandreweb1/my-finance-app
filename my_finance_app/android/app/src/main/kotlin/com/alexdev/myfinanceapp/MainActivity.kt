package com.alexdev.myfinanceapp

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        // Capture suggestion from intent if launched via notification tap
        consumeSuggestionFromIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // App was already running — notification tapped while in foreground/background
        consumeSuggestionFromIntent(intent)
    }

    /**
     * Extracts the suggestion JSON from the intent extras and stores it
     * so Flutter can retrieve it via MethodChannel.
     */
    private fun consumeSuggestionFromIntent(intent: Intent?) {
        val json = intent?.getStringExtra(NotificationMonitorService.EXTRA_SUGGESTION_JSON)
        if (json != null) {
            Log.d(TAG, "Consumed suggestion from intent: $json")
            pendingSuggestionJson = json
            // Clear from intent so it's not re-consumed on config change
            intent.removeExtra(NotificationMonitorService.EXTRA_SUGGESTION_JSON)
        }
    }

    companion object {
        private const val TAG = "MainActivity"

        /// Static sink: NotificationMonitorService posts events here directly.
        /// @Volatile ensures visibility across threads (service vs activity).
        @Volatile
        var notificationEventSink: EventChannel.EventSink? = null

        /// Suggestion JSON set when the user taps a native notification.
        /// Consumed once by Flutter via MethodChannel.
        @Volatile
        var pendingSuggestionJson: String? = null
    }

    private val permissionChannel = "com.alexdev.myfinanceapp/notification_permission"
    private val homeWidgetChannel = "com.alexdev.myfinanceapp/home_widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // EventChannel: Flutter subscribes here; service posts via static sink
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NotificationMonitorService.CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    notificationEventSink = events
                    Log.d(TAG, "EventSink connected")

                    // Flush any buffered events captured while the sink was null
                    val pending = NotificationMonitorService.consumePendingEvents(applicationContext)
                    if (pending.isNotEmpty()) {
                        Log.d(TAG, "Flushing ${pending.size} pending events")
                        for (event in pending) {
                            events?.success(event)
                        }
                    }
                }
                override fun onCancel(arguments: Any?) {
                    notificationEventSink = null
                    Log.d(TAG, "EventSink disconnected")
                }
            })

        // MethodChannel: permission helpers + intent suggestion consumption
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" -> result.success(isNotificationListenerEnabled())
                    "openPermissionSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "consumeIntentSuggestion" -> {
                        val json = pendingSuggestionJson
                        pendingSuggestionJson = null
                        Log.d(TAG, "consumeIntentSuggestion: ${json ?: "null"}")
                        result.success(json)
                    }
                    "updateAllowedPackages" -> {
                        val packages = (call.arguments as? List<*>)
                            ?.filterIsInstance<String>() ?: emptyList()
                        NotificationMonitorService.updateAllowedPackages(
                            applicationContext, packages)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Home Widget MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, homeWidgetChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidgets" -> {
                        val balance = call.argument<Double>("balance") ?: 0.0
                        val income = call.argument<Double>("monthIncome") ?: 0.0
                        val expense = call.argument<Double>("monthExpense") ?: 0.0
                        val month = call.argument<String>("monthLabel") ?: ""
                        val recentTxs = call.argument<List<Map<String, Any>>>("recentTransactions") ?: emptyList()
                        val upcomingRec = call.argument<List<Map<String, Any>>>("upcomingRecurring") ?: emptyList()

                        saveWidgetData(applicationContext, balance, income, expense, month, recentTxs, upcomingRec)
                        triggerWidgetUpdate(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveWidgetData(
        context: Context,
        balance: Double,
        income: Double,
        expense: Double,
        month: String,
        recentTxs: List<Map<String, Any>>,
        upcomingRec: List<Map<String, Any>>,
    ) {
        val prefs = context.getSharedPreferences(BalanceWidget.PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        editor.putFloat(BalanceWidget.KEY_BALANCE, balance.toFloat())
        editor.putFloat(BalanceWidget.KEY_INCOME, income.toFloat())
        editor.putFloat(BalanceWidget.KEY_EXPENSE, expense.toFloat())
        editor.putString(BalanceWidget.KEY_MONTH, month)

        val txArray = JSONArray()
        for (tx in recentTxs) {
            val obj = org.json.JSONObject()
            obj.put("title", tx["title"] ?: "")
            obj.put("amount", tx["amount"] ?: 0.0)
            obj.put("isIncome", tx["isIncome"] ?: false)
            obj.put("date", tx["date"] ?: "")
            txArray.put(obj)
        }
        editor.putString(TransactionsWidget.KEY_RECENT_TXS, txArray.toString())

        val recArray = JSONArray()
        for (rec in upcomingRec) {
            val obj = org.json.JSONObject()
            obj.put("title", rec["title"] ?: "")
            obj.put("amount", rec["amount"] ?: 0.0)
            obj.put("isIncome", rec["isIncome"] ?: false)
            obj.put("date", rec["date"] ?: "")
            recArray.put(obj)
        }
        editor.putString(RecurringWidget.KEY_UPCOMING_REC, recArray.toString())
        editor.apply()
        Log.d(TAG, "Widget data saved: balance=$balance income=$income expense=$expense")
    }

    private fun triggerWidgetUpdate(context: Context) {
        val awm = AppWidgetManager.getInstance(context)

        val balanceIds = awm.getAppWidgetIds(ComponentName(context, BalanceWidget::class.java))
        val txIds = awm.getAppWidgetIds(ComponentName(context, TransactionsWidget::class.java))
        val recIds = awm.getAppWidgetIds(ComponentName(context, RecurringWidget::class.java))

        if (balanceIds.isNotEmpty()) {
            val i = Intent(context, BalanceWidget::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, balanceIds)
            }
            context.sendBroadcast(i)
        }
        if (txIds.isNotEmpty()) {
            val i = Intent(context, TransactionsWidget::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, txIds)
            }
            context.sendBroadcast(i)
        }
        if (recIds.isNotEmpty()) {
            val i = Intent(context, RecurringWidget::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, recIds)
            }
            context.sendBroadcast(i)
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
