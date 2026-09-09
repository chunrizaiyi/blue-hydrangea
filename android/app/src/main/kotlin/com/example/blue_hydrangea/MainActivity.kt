package com.example.blue_hydrangea

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.Surface
import android.view.SurfaceView
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val displayChannel = "blue_hydrangea/display"
    private var timerMethodChannel: MethodChannel? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var pendingExactAlarmPermissionResult: MethodChannel.Result? = null
    private var clockDisplayEnabled = false
    private var clockDisplayLowPower = false

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        // Raise the refresh rate before Flutter receives the gesture. This makes
        // the first frame of every clock interaction smooth even when the idle
        // clock had requested the device's lowest refresh mode.
        if (
            event.actionMasked == MotionEvent.ACTION_DOWN &&
            clockDisplayEnabled &&
            clockDisplayLowPower
        ) {
            setClockDisplayMode(enabled = true, lowPower = false)
        }
        return super.dispatchTouchEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            displayChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setClockDisplayMode" -> {
                    val arguments = call.arguments
                    val enabled = when (arguments) {
                        is Boolean -> arguments
                        is Map<*, *> -> arguments["enabled"] as? Boolean ?: false
                        else -> false
                    }
                    val lowPower = when (arguments) {
                        is Map<*, *> -> arguments["lowPower"] as? Boolean ?: enabled
                        else -> enabled
                    }
                    setClockDisplayMode(enabled, lowPower)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        timerMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FocusTimerService.timerChannel,
        ).also { channel ->
            channel.setMethodCallHandler(::handleTimerMethod)
        }
        handleTimerIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleTimerIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        pendingExactAlarmPermissionResult?.let { pending ->
            pending.success(canScheduleExactAlarms())
            pendingExactAlarmPermissionResult = null
            if (canScheduleExactAlarms()) FocusTimerService.restoreAfterSystemEvent(this)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequestCode) return
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingNotificationPermissionResult?.success(granted)
        pendingNotificationPermissionResult = null
    }

    private fun handleTimerMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ensureNotificationPermission" -> ensureNotificationPermission(result)
            "ensureExactAlarmPermission" -> ensureExactAlarmPermission(result)
            "startTimer" -> {
                val snapshot = extractSnapshot(call.arguments)
                if (snapshot == null) {
                    result.error("invalid_snapshot", "startTimer requires a snapshot map", null)
                    return
                }
                val saved = FocusTimerStateStore.save(this, snapshot, forceActive = true)
                FocusTimerService.render(this)
                result.success(enrichedState(saved))
            }
            "setTimerSnapshot" -> {
                val snapshot = extractSnapshot(call.arguments)
                if (snapshot == null) {
                    result.error("invalid_snapshot", "setTimerSnapshot requires a snapshot map", null)
                    return
                }
                val saved = FocusTimerStateStore.save(this, snapshot)
                if (FocusTimerStateStore.bool(saved, "active")) {
                    FocusTimerService.render(this)
                } else {
                    FocusTimerService.stop(this)
                }
                result.success(enrichedState(saved))
            }
            "stopTimer" -> {
                val expectedSessionId = extractSessionId(call.arguments)
                val current = FocusTimerStateStore.read(this)
                if (
                    expectedSessionId != null &&
                    current != null &&
                    current.optString("sessionId") != expectedSessionId
                ) {
                    result.success(false)
                    return
                }
                FocusTimerService.stop(this)
                result.success(true)
            }
            "getState" -> result.success(enrichedState(FocusTimerStateStore.read(this)))
            "consumeOpenTimerRequest" -> {
                result.success(FocusTimerStateStore.consumeOpenRequest(this))
            }
            else -> result.notImplemented()
        }
    }

    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.error("permission_request_active", "Notification permission is already being requested", null)
            return
        }
        pendingNotificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    private fun ensureExactAlarmPermission(result: MethodChannel.Result) {
        if (canScheduleExactAlarms()) {
            result.success(true)
            return
        }
        if (pendingExactAlarmPermissionResult != null) {
            result.error(
                "permission_request_active",
                "Exact alarm permission is already being requested",
                null,
            )
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(true)
            return
        }
        val request = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = Uri.parse("package:$packageName")
        }
        if (request.resolveActivity(packageManager) == null) {
            result.success(false)
            return
        }
        pendingExactAlarmPermissionResult = result
        runCatching { startActivity(request) }.onFailure {
            pendingExactAlarmPermissionResult = null
            result.success(false)
        }
    }

    private fun canScheduleExactAlarms(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

    private fun extractSnapshot(arguments: Any?): Map<*, *>? {
        val outer = arguments as? Map<*, *> ?: return null
        return outer["snapshot"] as? Map<*, *> ?: outer
    }

    private fun extractSessionId(arguments: Any?): String? {
        val values = arguments as? Map<*, *> ?: return arguments as? String
        return values["sessionId"] as? String
    }

    private fun enrichedState(snapshot: JSONObject?): Map<String, Any?> {
        if (snapshot == null) return FocusTimerStateStore.toMap(null)
        val now = System.currentTimeMillis()
        val mode = snapshot.optString("mode")
        val status = snapshot.optString("status")
        val endAt = FocusTimerStateStore.long(snapshot, "endAtEpochMs")
        val startedAt = FocusTimerStateStore.long(snapshot, "startedAtEpochMs", now)
        if (status == "running") {
            if (mode == "stopwatch") {
                snapshot.put("elapsedMs", (now - startedAt).coerceAtLeast(0L))
            } else if (endAt > 0L) {
                snapshot.put("remainingMs", (endAt - now).coerceAtLeast(0L))
            }
        }
        if (status == "overtime" && endAt > 0L) {
            snapshot.put("overtimeMs", (now - endAt).coerceAtLeast(0L))
        }
        val state = FocusTimerStateStore.toMap(snapshot).toMutableMap()
        val notificationsGranted =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        state["notificationPermissionGranted"] = notificationsGranted
        state["promotedNotificationsAvailable"] =
            if (Build.VERSION.SDK_INT >= 36) {
                getSystemService(NotificationManager::class.java).canPostPromotedNotifications()
            } else {
                false
            }
        state["exactAlarmAvailable"] = canScheduleExactAlarms()
        state["hyperOsFocusProtocol"] = HyperOsFocusNotification.protocolVersion(this)
        state["hyperOsIslandSupported"] = HyperOsFocusNotification.supportsIsland()
        // Xiaomi documents the focus-permission provider call as potentially
        // expensive. Do not run it on Flutter's platform/UI thread every time
        // the timer state is restored; rendering the standard notification and
        // attaching the HyperOS payload do not depend on this diagnostic value.
        return state
    }

    private fun handleTimerIntent(incoming: Intent?) {
        if (incoming?.getBooleanExtra(FocusTimerService.extraOpenClock, false) != true) return
        FocusTimerStateStore.markOpenRequested(this)
        val payload = mapOf(
            "mode" to incoming.getStringExtra(FocusTimerService.extraMode),
            "requestedAction" to incoming.getStringExtra(FocusTimerService.extraRequestedAction),
        )
        timerMethodChannel?.invokeMethod(FocusTimerService.callbackOpenFocusClock, payload)
        incoming.removeExtra(FocusTimerService.extraOpenClock)
    }

    private fun setClockDisplayMode(enabled: Boolean, lowPower: Boolean) {
        clockDisplayEnabled = enabled
        clockDisplayLowPower = enabled && lowPower
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        runCatching {
            window.attributes = window.attributes.apply {
                preferredRefreshRate = if (enabled && lowPower) 1f else 0f
            }
        }

        window.decorView.post {
            val flutterSurface = findSurfaceView(window.decorView)
            val surface = flutterSurface?.holder?.surface
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && surface?.isValid == true) {
                val requestedRate = if (enabled && lowPower) 1f else 0f
                runCatching {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        surface.setFrameRate(
                            requestedRate,
                            Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                            Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS,
                        )
                    } else {
                        surface.setFrameRate(
                            requestedRate,
                            Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                        )
                    }
                }
            }
        }
    }

    private fun findSurfaceView(view: View): SurfaceView? {
        if (view is SurfaceView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findSurfaceView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }

    companion object {
        private const val notificationPermissionRequestCode = 4_206
    }
}
