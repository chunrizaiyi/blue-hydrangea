package com.example.blue_hydrangea

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.UUID

/**
 * Small, synchronous persistence layer shared by Flutter and the foreground
 * service. Keeping one JSON snapshot also preserves fields introduced by the
 * Dart side in later app versions.
 */
object FocusTimerStateStore {
    private const val preferencesName = "focus_timer_native_state_v1"
    private const val snapshotKey = "snapshot"
    private const val openRequestKey = "open_focus_clock"

    @Synchronized
    fun save(
        context: Context,
        source: Map<*, *>,
        forceActive: Boolean? = null,
    ): JSONObject {
        val snapshot = mapToJson(source)
        normalize(snapshot, forceActive)
        write(context, snapshot)
        return snapshot
    }

    @Synchronized
    fun save(context: Context, snapshot: JSONObject): JSONObject {
        normalize(snapshot, null)
        write(context, snapshot)
        return snapshot
    }

    @Synchronized
    fun read(context: Context): JSONObject? {
        val raw = preferences(context).getString(snapshotKey, null) ?: return null
        return runCatching { JSONObject(raw) }.getOrNull()
    }

    @Synchronized
    fun update(
        context: Context,
        operation: (JSONObject) -> Unit,
    ): JSONObject? {
        val snapshot = read(context) ?: return null
        operation(snapshot)
        normalize(snapshot, null)
        write(context, snapshot)
        return snapshot
    }

    @Synchronized
    fun clear(context: Context) {
        preferences(context).edit().remove(snapshotKey).apply()
    }

    @Synchronized
    fun markOpenRequested(context: Context) {
        preferences(context).edit().putBoolean(openRequestKey, true).apply()
    }

    @Synchronized
    fun consumeOpenRequest(context: Context): Boolean {
        val preferences = preferences(context)
        val requested = preferences.getBoolean(openRequestKey, false)
        if (requested) preferences.edit().remove(openRequestKey).apply()
        return requested
    }

    fun toMap(snapshot: JSONObject?): Map<String, Any?> {
        if (snapshot == null) {
            return mapOf(
                "version" to 1,
                "active" to false,
                "mode" to "none",
                "phase" to "none",
                "status" to "idle",
            )
        }
        return jsonObjectToMap(snapshot)
    }

    fun long(snapshot: JSONObject, key: String, fallback: Long = 0L): Long {
        if (!snapshot.has(key) || snapshot.isNull(key)) return fallback
        return when (val value = snapshot.opt(key)) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull() ?: fallback
            else -> fallback
        }
    }

    fun bool(snapshot: JSONObject, key: String, fallback: Boolean = false): Boolean {
        if (!snapshot.has(key) || snapshot.isNull(key)) return fallback
        return when (val value = snapshot.opt(key)) {
            is Boolean -> value
            is Number -> value.toInt() != 0
            is String -> value.equals("true", ignoreCase = true) || value == "1"
            else -> fallback
        }
    }

    private fun normalize(snapshot: JSONObject, forceActive: Boolean?) {
        val now = System.currentTimeMillis()
        if (snapshot.optInt("version", 0) <= 0) snapshot.put("version", 1)
        if (snapshot.optString("sessionId").isBlank()) {
            snapshot.put("sessionId", UUID.randomUUID().toString())
        }
        if (snapshot.optString("mode").isBlank()) snapshot.put("mode", "countdown")
        if (snapshot.optString("phase").isBlank()) snapshot.put("phase", "none")

        var status = snapshot.optString("status")
        if (status.isBlank()) {
            status = when {
                bool(snapshot, "isAlarmActive") || bool(snapshot, "isSilentOvertime") -> "overtime"
                bool(snapshot, "isPaused") -> "paused"
                bool(snapshot, "isRunning", true) -> "running"
                else -> "paused"
            }
            snapshot.put("status", status)
        }

        val plannedDurationMs = long(snapshot, "plannedDurationMs").takeIf { it > 0 }
            ?: (long(snapshot, "totalDurationSeconds") * 1000L).coerceAtLeast(0L)
        snapshot.put("plannedDurationMs", plannedDurationMs)
        snapshot.put("totalDurationSeconds", plannedDurationMs / 1000L)

        // Dart owns the persisted study records and supplies today's completed
        // focus time as a base for the system notification chronometer. Native
        // timer state adds the active session on top without polling Flutter.
        snapshot.put(
            "todayAccumulatedMs",
            long(snapshot, "todayAccumulatedMs").coerceAtLeast(0L),
        )
        if (long(snapshot, "todayAccumulatedDayStartEpochMs") <= 0L) {
            snapshot.put("todayAccumulatedDayStartEpochMs", localDayStart(now))
        }

        val active = forceActive ?: when (status) {
            "idle", "stopped" -> false
            else -> bool(snapshot, "active", true)
        }
        snapshot.put("active", active)
        snapshot.put("isRunning", status == "running")
        snapshot.put("isPaused", status == "paused")
        snapshot.put("isAlarmActive", bool(snapshot, "isAlarmActive") && status != "stopped")
        snapshot.put("isSilentOvertime", bool(snapshot, "isSilentOvertime"))
        snapshot.put("updatedAtEpochMs", now)
    }

    private fun write(context: Context, snapshot: JSONObject) {
        preferences(context).edit().putString(snapshotKey, snapshot.toString()).commit()
    }

    private fun localDayStart(epochMs: Long): Long =
        Calendar.getInstance().apply {
            timeInMillis = epochMs
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

    private fun preferences(context: Context) =
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    private fun mapToJson(source: Map<*, *>): JSONObject {
        val result = JSONObject()
        source.forEach { (rawKey, value) ->
            val key = rawKey?.toString() ?: return@forEach
            result.put(key, valueToJson(value))
        }
        return result
    }

    private fun valueToJson(value: Any?): Any = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> mapToJson(value)
        is List<*> -> JSONArray().also { array -> value.forEach { array.put(valueToJson(it)) } }
        is Array<*> -> JSONArray().also { array -> value.forEach { array.put(valueToJson(it)) } }
        is Number, is Boolean, is String -> value
        else -> value.toString()
    }

    private fun jsonObjectToMap(source: JSONObject): Map<String, Any?> {
        val result = linkedMapOf<String, Any?>()
        source.keys().forEach { key -> result[key] = jsonToValue(source.opt(key)) }
        return result
    }

    private fun jsonToValue(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> jsonObjectToMap(value)
        is JSONArray -> List(value.length()) { index -> jsonToValue(value.opt(index)) }
        else -> value
    }
}
