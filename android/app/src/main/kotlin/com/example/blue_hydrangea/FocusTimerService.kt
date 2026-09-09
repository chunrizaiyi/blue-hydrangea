package com.example.blue_hydrangea

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import org.json.JSONObject
import java.util.Calendar
import kotlin.math.roundToInt

/**
 * Native clock companion. The system notification and exact alarm remain alive
 * when Flutter is backgrounded or the display is off; Flutter stays responsible
 * for the full-screen presentation and local learning records.
 */
class FocusTimerService : Service() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var fallbackExpiration: Runnable? = null
    private val mediaAlert by lazy { GentleMediaAlert(this, mainHandler) }
    private var alertWakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val expectedSessionId = intent?.getStringExtra(extraSessionId)
        when (intent?.action ?: actionRender) {
            actionRender -> renderCurrentState()
            actionPause -> pauseCurrentTimer(expectedSessionId)
            actionResume -> resumeCurrentTimer(expectedSessionId)
            actionExpire -> expireTimer(expectedSessionId)
            actionSilence -> silenceOvertime(expectedSessionId)
            actionFinishOvertime -> finishOvertimeFromNotification(expectedSessionId)
            else -> renderCurrentState()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        cancelFallbackExpiration()
        stopAlert()
        super.onDestroy()
    }

    private fun renderCurrentState() {
        val snapshot = FocusTimerStateStore.read(this)
        if (snapshot == null || !FocusTimerStateStore.bool(snapshot, "active")) {
            stopServiceAndNotification(clearSnapshot = false)
            return
        }

        val status = snapshot.optString("status", "paused")
        val endAt = FocusTimerStateStore.long(snapshot, "endAtEpochMs")
        if (status == "running" && endAt > 0 && endAt <= System.currentTimeMillis()) {
            expireTimer(snapshot.optString("sessionId"))
            return
        }

        startOrUpdateForeground(snapshot)
        if (status == "running" && endAt > 0) {
            scheduleExpiration(snapshot)
        } else {
            cancelAlarm(snapshot)
            cancelFallbackExpiration()
        }
        if (FocusTimerStateStore.bool(snapshot, "isAlarmActive")) {
            startAlert(loop = snapshot.optString("mode") == "countdown")
        } else {
            stopAlert()
        }
    }

    private fun pauseCurrentTimer(expectedSessionId: String?) {
        val now = System.currentTimeMillis()
        val current = FocusTimerStateStore.read(this) ?: return
        if (expectedSessionId != null && expectedSessionId != current.optString("sessionId")) return
        if (!FocusTimerStateStore.bool(current, "active")) return
        if (current.optString("status") != "running") return
        val currentEndAt = FocusTimerStateStore.long(current, "endAtEpochMs")
        if (current.optString("mode") != "stopwatch" && currentEndAt <= now) {
            expireTimer(expectedSessionId ?: current.optString("sessionId"))
            return
        }
        val snapshot = FocusTimerStateStore.update(this) { state ->
            if (!FocusTimerStateStore.bool(state, "active")) return@update
            val status = state.optString("status")
            if (status != "running") return@update
            val mode = state.optString("mode")
            val endAt = FocusTimerStateStore.long(state, "endAtEpochMs")
            val startedAt = FocusTimerStateStore.long(state, "startedAtEpochMs", now)
            if (mode == "stopwatch") {
                state.put("elapsedMs", (now - startedAt).coerceAtLeast(0L))
            } else {
                state.put("remainingMs", (endAt - now).coerceAtLeast(0L))
            }
            state.put("endAtEpochMs", 0L)
            state.put("status", "paused")
            state.put("isRunning", false)
            state.put("isPaused", true)
            state.put("isAlarmActive", false)
        } ?: return
        cancelAlarm(snapshot)
        cancelFallbackExpiration()
        stopAlert()
        startOrUpdateForeground(snapshot)
    }

    private fun resumeCurrentTimer(expectedSessionId: String?) {
        val now = System.currentTimeMillis()
        val current = FocusTimerStateStore.read(this) ?: return
        if (expectedSessionId != null && expectedSessionId != current.optString("sessionId")) return
        if (!FocusTimerStateStore.bool(current, "active")) return
        if (current.optString("status") != "paused") return
        val snapshot = FocusTimerStateStore.update(this) { state ->
            if (!FocusTimerStateStore.bool(state, "active")) return@update
            if (state.optString("status") != "paused") return@update
            if (state.optString("mode") == "stopwatch") {
                val elapsed = FocusTimerStateStore.long(state, "elapsedMs")
                state.put("startedAtEpochMs", now - elapsed)
                state.put("endAtEpochMs", 0L)
            } else {
                val remaining = FocusTimerStateStore.long(state, "remainingMs")
                if (remaining <= 0) return@update
                state.put("endAtEpochMs", now + remaining)
            }
            state.put("status", "running")
            state.put("isRunning", true)
            state.put("isPaused", false)
            state.put("isAlarmActive", false)
            state.put("isSilentOvertime", false)
        } ?: return
        startOrUpdateForeground(snapshot)
        if (snapshot.optString("mode") != "stopwatch") scheduleExpiration(snapshot)
    }

    private fun expireTimer(expectedSessionId: String?) {
        val current = FocusTimerStateStore.read(this) ?: return
        if (!FocusTimerStateStore.bool(current, "active")) return
        if (expectedSessionId != null && expectedSessionId != current.optString("sessionId")) return
        if (current.optString("status") != "running") return

        val now = System.currentTimeMillis()
        val endAt = FocusTimerStateStore.long(current, "endAtEpochMs")
        if (endAt > now + 250L) {
            scheduleExpiration(current)
            return
        }

        val mode = current.optString("mode")
        holdAlertWakeLock(if (mode == "countdown") 65_000L else 12_000L)
        val snapshot = FocusTimerStateStore.update(this) { state ->
            state.put("remainingMs", 0L)
            state.put("elapsedMs", FocusTimerStateStore.long(state, "plannedDurationMs"))
            state.put("completedAtEpochMs", now)
            state.put("isRunning", false)
            state.put("isPaused", false)
            state.put("isAlarmActive", true)
            state.put("isSilentOvertime", false)
            if (mode == "countdown") {
                state.put("status", "overtime")
                state.put("overtimeMs", (now - endAt).coerceAtLeast(0L))
            } else {
                state.put("status", "finished")
                state.put("completedPhase", state.optString("phase", "none"))
            }
        } ?: return

        cancelAlarm(snapshot)
        cancelFallbackExpiration()
        startOrUpdateForeground(snapshot)
        startAlert(loop = mode == "countdown")
    }

    private fun silenceOvertime(expectedSessionId: String?) {
        val current = FocusTimerStateStore.read(this) ?: return
        if (expectedSessionId != null && expectedSessionId != current.optString("sessionId")) return
        if (!FocusTimerStateStore.bool(current, "active")) return
        if (current.optString("status") != "overtime") return
        val snapshot = FocusTimerStateStore.update(this) { state ->
            if (state.optString("status") != "overtime") return@update
            state.put("isAlarmActive", false)
            state.put("isSilentOvertime", true)
            val endAt = FocusTimerStateStore.long(state, "endAtEpochMs")
            state.put("overtimeMs", (System.currentTimeMillis() - endAt).coerceAtLeast(0L))
        } ?: return
        stopAlert()
        startOrUpdateForeground(snapshot)
    }

    private fun finishOvertimeFromNotification(expectedSessionId: String?) {
        val current = FocusTimerStateStore.read(this) ?: return
        if (expectedSessionId != null && expectedSessionId != current.optString("sessionId")) return
        if (!FocusTimerStateStore.bool(current, "active")) return
        if (current.optString("status") != "overtime") return
        val now = System.currentTimeMillis()
        FocusTimerStateStore.update(this) { state ->
            val endAt = FocusTimerStateStore.long(state, "endAtEpochMs")
            state.put("overtimeMs", (now - endAt).coerceAtLeast(0L))
            state.put("completedAtEpochMs", now)
            state.put("finishedBy", "notification")
            state.put("status", "finished")
            state.put("active", false)
            state.put("isAlarmActive", false)
            state.put("isSilentOvertime", false)
        }
        stopServiceAndNotification(clearSnapshot = false)
    }

    private fun stopServiceAndNotification(clearSnapshot: Boolean) {
        val snapshot = FocusTimerStateStore.read(this)
        if (snapshot != null) cancelAlarm(snapshot)
        cancelFallbackExpiration()
        stopAlert()
        if (clearSnapshot) FocusTimerStateStore.clear(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startOrUpdateForeground(snapshot: JSONObject) {
        val notification = buildNotification(snapshot)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                notificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(notificationId, notification)
        }
    }

    private fun buildNotification(snapshot: JSONObject): Notification {
        val mode = snapshot.optString("mode", "countdown")
        val phase = snapshot.optString("phase", "none")
        val status = snapshot.optString("status", "paused")
        val now = System.currentTimeMillis()
        val startedAt = FocusTimerStateStore.long(snapshot, "startedAtEpochMs", now)
        val endAt = FocusTimerStateStore.long(snapshot, "endAtEpochMs")
        val remaining = if (status == "running" && endAt > 0) {
            (endAt - now).coerceAtLeast(0L)
        } else {
            FocusTimerStateStore.long(snapshot, "remainingMs")
        }
        val elapsed = if (mode == "stopwatch" && status == "running") {
            (now - startedAt).coerceAtLeast(0L)
        } else {
            FocusTimerStateStore.long(snapshot, "elapsedMs")
        }
        val overtime = if (status == "overtime" && endAt > 0) {
            (now - endAt).coerceAtLeast(0L)
        } else {
            FocusTimerStateStore.long(snapshot, "overtimeMs")
        }
        val todayStart = localDayStart(now)
        val sessionFocused = focusedSessionDuration(
            snapshot = snapshot,
            mode = mode,
            phase = phase,
            status = status,
            now = now,
            startedAt = startedAt,
            remaining = remaining,
            elapsed = elapsed,
            overtime = overtime,
            todayStart = todayStart,
        )
        val accumulatedDayStart = FocusTimerStateStore.long(
            snapshot,
            "todayAccumulatedDayStartEpochMs",
            todayStart,
        )
        val persistedTodayFocused = if (accumulatedDayStart == todayStart) {
            FocusTimerStateStore.long(snapshot, "todayAccumulatedMs")
        } else {
            // A timer may stay alive across local midnight without Flutter.
            // Yesterday's database base must not leak into the new day.
            0L
        }
        val todayFocused = (
            persistedTodayFocused + sessionFocused
        ).coerceAtLeast(0L)
        val activelyAccumulating =
            (status == "running" && !(mode == "pomodoro" && phase == "rest")) ||
                status == "overtime"
        val todayChronometerBase = now - todayFocused.coerceAtMost(now)

        val title = "瀹濆疂浠婂ぉ宸茬粡涓撴敞浜?
        val content = when (status) {
            "running" -> when {
                mode == "stopwatch" -> "涓撴敞杩樺湪鎱㈡參绱Н 路 瀹濆疂鐪熸~"
                mode == "countdown" -> "鍊掕鏃跺畨闈欒繘琛屼腑 路 瀹濆疂鐪熸~"
                phase == "rest" ->
                    "鐣寗浼戞伅杩樺墿 ${formatDuration(remaining)} 路 姝囦竴浼氬効鍚"
                else -> "杩欎竴棰楃暘鑼勬鍦ㄦ參鎱㈡垚鐔?路 瀹濆疂鐪熸~"
            }
            "paused" ->
                "浠婂ぉ宸茬粡涓撴敞 ${formatDuration(todayFocused)} 路 闅忔椂鍙互缁х画"
            "overtime" -> if (FocusTimerStateStore.bool(snapshot, "isSilentOvertime")) {
                "瀹濆疂杩樺湪璁ょ湡鍧氭寔 路 鎼炲畬浜嗗氨鐐硅繖閲屽惂~"
            } else {
                "鍊掕鏃跺埌鍟?路 瀹濆疂杩樺湪璁ょ湡鍧氭寔"
            }
            "finished" ->
                "浠婂ぉ宸茬粡涓撴敞 ${formatDuration(todayFocused)} 路 瀹濆疂鐪熸~"
            else -> "涓撴敞鐨勫皬鑺辨鍦ㄥ畨闈欑洓寮€"
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_focus_timer)
            .setContentTitle(title)
            .setContentText(content)
            .setCategory(Notification.CATEGORY_STOPWATCH)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setColor(Color.rgb(94, 121, 179))
            .setContentIntent(openClockPendingIntent(snapshot, "open"))

        if (activelyAccumulating) {
            // The app's countdown continues to be driven by endAt and its exact
            // alarm. This separate system chronometer deliberately counts up so
            // the shade, Live Update chip, lock screen and AOD can show today's
            // total focus time without one-second notification updates.
            builder
                .setWhen(todayChronometerBase)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setChronometerCountDown(false)
        } else {
            builder.setShowWhen(false).setUsesChronometer(false)
        }

        if (Build.VERSION.SDK_INT >= 36) {
            val planned = FocusTimerStateStore.long(snapshot, "plannedDurationMs")
            if (planned > 0 && mode != "stopwatch") {
                val progress = when (status) {
                    "overtime", "finished" -> 1000
                    else -> (((planned - remaining).coerceAtLeast(0L).toDouble() / planned) * 1000.0)
                        .roundToInt()
                        .coerceIn(0, 1000)
                }
                val segment = Notification.ProgressStyle.Segment(1000)
                    .setColor(Color.rgb(112, 145, 213))
                val style = Notification.ProgressStyle()
                    .setProgressSegments(listOf(segment))
                    .setProgress(progress)
                    .setProgressTrackerIcon(
                        Icon.createWithResource(this, R.drawable.ic_focus_timer),
                    )
                    .setStyledByProgress(true)
                builder.setStyle(style)
            }
        }

        // Android 16 Live Updates. The literal extras key also works on the
        // base API-36 SDK where the convenience setter is supplied by a later
        // SDK extension.
        val promotable = status == "running" || status == "overtime"
        builder.extras.putBoolean("android.requestPromotedOngoing", promotable)

        var hyperPrimaryAction: Notification.Action? = null
        var hyperEndAction: Notification.Action? = null
        when (status) {
            "running" -> {
                hyperPrimaryAction = notificationAction(
                    "鏆傚仠",
                    servicePendingIntent(actionPause, snapshot, requestPause),
                ).also(builder::addAction)
                hyperEndAction = notificationAction(
                    "缁撴潫",
                    openClockPendingIntent(snapshot, "end"),
                ).also(builder::addAction)
            }
            "paused" -> {
                hyperPrimaryAction = notificationAction(
                    "缁х画",
                    servicePendingIntent(actionResume, snapshot, requestResume),
                ).also(builder::addAction)
                hyperEndAction = notificationAction(
                    "缁撴潫",
                    openClockPendingIntent(snapshot, "end"),
                ).also(builder::addAction)
            }
            "overtime" -> if (FocusTimerStateStore.bool(snapshot, "isSilentOvertime")) {
                hyperEndAction = notificationAction(
                    "瀹屾垚鍟?,
                    servicePendingIntent(actionFinishOvertime, snapshot, requestFinish),
                ).also(builder::addAction)
            } else {
                hyperPrimaryAction = notificationAction(
                    "鍋滃彮",
                    servicePendingIntent(actionFinishOvertime, snapshot, requestFinish),
                ).also(builder::addAction)
                hyperEndAction = notificationAction(
                    "闈欓煶缁х画",
                    servicePendingIntent(actionSilence, snapshot, requestSilence),
                ).also(builder::addAction)
            }
            "finished" -> hyperEndAction = notificationAction(
                "鍥炲幓鐪嬬湅",
                openClockPendingIntent(snapshot, "open"),
            ).also(builder::addAction)
        }

        builder.setPublicVersion(
            buildPublicNotification(
                status = status,
                todayFocused = todayFocused,
                todayChronometerBase = todayChronometerBase,
                activelyAccumulating = activelyAccumulating,
            ),
        )
        val notification = builder.build()
        val primaryTime = when {
            status == "overtime" -> "+${formatDuration(overtime)}"
            mode == "stopwatch" -> formatDuration(elapsed)
            else -> formatDuration(remaining)
        }
        val hyperTimeout = when {
            status == "running" && endAt > now -> ((endAt - now) / 1000L + 120L).toInt()
            else -> 3_600
        }
        HyperOsFocusNotification.decorate(
            context = this,
            notification = notification,
            mode = mode,
            phase = phase,
            status = status,
            primaryTime = primaryTime,
            supportingText = content,
            timeoutSeconds = hyperTimeout,
            pauseAction = hyperPrimaryAction,
            endAction = hyperEndAction,
        )
        return notification
    }

    private fun buildPublicNotification(
        status: String,
        todayFocused: Long,
        todayChronometerBase: Long,
        activelyAccumulating: Boolean,
    ): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, notificationChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(R.drawable.ic_focus_timer)
            .setContentTitle("瀹濆疂浠婂ぉ宸茬粡涓撴敞浜?)
            .setContentText(
                when (status) {
                    "running" -> "涓撴敞鏃堕棿姝ｅ湪鎱㈡參澧炲姞"
                    "paused" -> "宸蹭笓娉?${formatDuration(todayFocused)} 路 鏆傚仠涓?
                    "overtime" -> "瀹濆疂杩樺湪璁ょ湡鍧氭寔"
                    else -> "宸蹭笓娉?${formatDuration(todayFocused)} 路 瀹屾垚鍟?
                },
            )
            .setCategory(Notification.CATEGORY_STOPWATCH)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setOngoing(true)

        if (activelyAccumulating) {
            builder
                .setWhen(todayChronometerBase)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setChronometerCountDown(false)
        } else {
            builder.setShowWhen(false).setUsesChronometer(false)
        }
        return builder.build()
    }

    private fun focusedSessionDuration(
        snapshot: JSONObject,
        mode: String,
        phase: String,
        status: String,
        now: Long,
        startedAt: Long,
        remaining: Long,
        elapsed: Long,
        overtime: Long,
        todayStart: Long,
    ): Long {
        if (mode == "pomodoro" && phase == "rest") return 0L
        val planned = FocusTimerStateStore.long(snapshot, "plannedDurationMs")
        val totalSessionFocused = when (status) {
            "running" -> if (mode == "stopwatch") {
                (now - startedAt).coerceAtLeast(0L)
            } else {
                (planned - remaining).coerceAtLeast(0L)
            }
            "paused" -> if (mode == "stopwatch") {
                elapsed
            } else {
                (planned - remaining).coerceAtLeast(0L)
            }
            "overtime" -> (planned + overtime).coerceAtLeast(0L)
            else -> elapsed.coerceAtLeast(0L)
        }
        val measuredAt = if (status == "paused" || status == "finished") {
            FocusTimerStateStore.long(snapshot, "updatedAtEpochMs", now)
        } else {
            now
        }
        val recordStartedAt = FocusTimerStateStore.long(
            snapshot,
            "recordStartedAtEpochMs",
            startedAt,
        )
        val availableTodayWallTime = (
            measuredAt - maxOf(recordStartedAt, todayStart)
        ).coerceAtLeast(0L)
        return totalSessionFocused.coerceAtMost(availableTodayWallTime)
    }

    private fun localDayStart(epochMs: Long): Long =
        Calendar.getInstance().apply {
            timeInMillis = epochMs
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

    private fun scheduleExpiration(snapshot: JSONObject) {
        val endAt = FocusTimerStateStore.long(snapshot, "endAtEpochMs")
        if (endAt <= 0) return
        val pendingIntent = expirationPendingIntent(snapshot)
        val alarmManager = getSystemService(AlarmManager::class.java)
        val exactAllowed =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
        if (exactAllowed) {
            runCatching {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    endAt,
                    pendingIntent,
                )
            }.recoverCatching {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    endAt,
                    pendingIntent,
                )
            }
        } else {
            // The UI asks for exact-alarm access before starting. Keep this
            // fallback only for a user who explicitly declines the setting.
            runCatching {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    endAt,
                    pendingIntent,
                )
            }
        }

        // Keep an in-process fallback even when an OEM rejects both alarm APIs.
        // It is not a replacement for an exact alarm after process death, but it
        // prevents a vendor-specific SecurityException from disabling an active
        // foreground timer while the process is healthy.
        cancelFallbackExpiration()
        val delay = (endAt - System.currentTimeMillis()).coerceAtLeast(0L)
        fallbackExpiration = Runnable { expireTimer(snapshot.optString("sessionId")) }.also {
            mainHandler.postDelayed(it, delay)
        }
    }

    private fun cancelAlarm(snapshot: JSONObject) {
        runCatching {
            getSystemService(AlarmManager::class.java).cancel(
                expirationPendingIntent(snapshot),
            )
        }
    }

    private fun cancelFallbackExpiration() {
        fallbackExpiration?.let(mainHandler::removeCallbacks)
        fallbackExpiration = null
    }

    private fun startAlert(loop: Boolean) {
        if (mediaAlert.isPlaying) return
        // Keep the short wake lock acquired by expireTimer while replacing a
        // stale player instance; stopAlert() would release it too early.
        mediaAlert.stop()
        mediaAlert.start(loop = loop, maxDurationMs = 60_000L)

        val vibrator = getSystemService(Vibrator::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createWaveform(longArrayOf(0L, 110L, 180L, 110L), -1),
            )
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(longArrayOf(0L, 110L, 180L, 110L), -1)
        }
    }

    private fun stopAlert() {
        mediaAlert.stop()
        alertWakeLock?.let { lock -> if (lock.isHeld) runCatching { lock.release() } }
        alertWakeLock = null
    }

    private fun holdAlertWakeLock(timeoutMs: Long) {
        alertWakeLock?.let { lock -> if (lock.isHeld) runCatching { lock.release() } }
        alertWakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:focus_timer_alert")
            .apply { acquire(timeoutMs) }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            notificationChannelId,
            "涓撴敞璁℃椂涓庡€掕鏃?,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "鍦ㄥ悗鍙般€侀攣灞忓拰绯荤粺瀹炴椂鐘舵€佷腑鏄剧ず瀹濆疂鐨勮鏃惰繘搴?
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun servicePendingIntent(
        action: String,
        snapshot: JSONObject,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(this, FocusTimerService::class.java).apply {
            this.action = action
            putExtra(extraSessionId, snapshot.optString("sessionId"))
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(this, requestCode, intent, flags)
        } else {
            PendingIntent.getService(this, requestCode, intent, flags)
        }
    }

    private fun expirationPendingIntent(snapshot: JSONObject): PendingIntent {
        val intent = Intent(this, FocusTimerReceiver::class.java).apply {
            action = actionExpire
            putExtra(extraSessionId, snapshot.optString("sessionId"))
        }
        return PendingIntent.getBroadcast(
            this,
            requestExpire,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notificationAction(title: String, intent: PendingIntent): Notification.Action =
        Notification.Action.Builder(
            Icon.createWithResource(this, R.drawable.ic_focus_timer),
            title,
            intent,
        ).build()

    private fun openClockPendingIntent(snapshot: JSONObject, requestedAction: String): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = actionOpenClock
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(extraOpenClock, true)
            putExtra(extraMode, snapshot.optString("mode", "countdown"))
            putExtra(extraRequestedAction, requestedAction)
        }
        return PendingIntent.getActivity(
            this,
            if (requestedAction == "end") requestOpenEnd else requestOpen,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun formatDuration(milliseconds: Long): String {
        val totalSeconds = (milliseconds.coerceAtLeast(0L) / 1000L)
        val hours = totalSeconds / 3600L
        val minutes = (totalSeconds % 3600L) / 60L
        val seconds = totalSeconds % 60L
        return if (hours > 0) {
            "%d:%02d:%02d".format(hours, minutes, seconds)
        } else {
            "%02d:%02d".format(minutes, seconds)
        }
    }

    companion object {
        const val timerChannel = "blue_hydrangea/timer_service"
        const val callbackOpenFocusClock = "openFocusClock"
        const val extraOpenClock = "focus_timer_open_clock"
        const val extraMode = "focus_timer_mode"
        const val extraRequestedAction = "focus_timer_requested_action"

        private const val notificationChannelId = "focus_timer_live_v1"
        private const val notificationId = 4_207
        internal const val extraSessionId = "focus_timer_session_id"

        private const val actionRender = "com.example.blue_hydrangea.timer.RENDER"
        private const val actionPause = "com.example.blue_hydrangea.timer.PAUSE"
        private const val actionResume = "com.example.blue_hydrangea.timer.RESUME"
        internal const val actionExpire = "com.example.blue_hydrangea.timer.EXPIRE"
        private const val actionSilence = "com.example.blue_hydrangea.timer.SILENCE"
        private const val actionFinishOvertime = "com.example.blue_hydrangea.timer.FINISH_OVERTIME"
        private const val actionOpenClock = "com.example.blue_hydrangea.timer.OPEN_CLOCK"

        private const val requestExpire = 4_208
        private const val requestPause = 4_209
        private const val requestResume = 4_210
        private const val requestSilence = 4_211
        private const val requestFinish = 4_212
        private const val requestOpen = 4_213
        private const val requestOpenEnd = 4_214

        fun render(context: Context) {
            enqueue(context, actionRender)
        }

        fun stop(context: Context) {
            val snapshot = FocusTimerStateStore.read(context)
            if (snapshot != null) {
                val expirationIntent = Intent(context, FocusTimerReceiver::class.java).apply {
                    action = actionExpire
                    putExtra(extraSessionId, snapshot.optString("sessionId"))
                }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    requestExpire,
                    expirationIntent,
                    flags,
                )
                context.getSystemService(AlarmManager::class.java).cancel(pendingIntent)
                pendingIntent.cancel()
            }
            FocusTimerStateStore.clear(context)
            context.getSystemService(NotificationManager::class.java).cancel(notificationId)
            context.stopService(Intent(context, FocusTimerService::class.java))
        }

        private fun enqueue(context: Context, action: String) {
            val intent = Intent(context, FocusTimerService::class.java).apply {
                this.action = action
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        internal fun expireFromSystem(context: Context, sessionId: String?) {
            val intent = Intent(context, FocusTimerService::class.java).apply {
                action = actionExpire
                putExtra(extraSessionId, sessionId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        internal fun restoreAfterSystemEvent(context: Context) {
            val snapshot = FocusTimerStateStore.read(context) ?: return
            if (!FocusTimerStateStore.bool(snapshot, "active")) return
            runCatching { render(context) }
        }
    }
}

