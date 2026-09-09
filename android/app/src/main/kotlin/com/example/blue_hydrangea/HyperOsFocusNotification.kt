package com.example.blue_hydrangea

import android.app.Notification
import android.content.Context
import android.graphics.drawable.Icon
import android.provider.Settings
import android.os.Bundle
import org.json.JSONArray
import org.json.JSONObject

/** Xiaomi HyperOS 2 focus-notification + HyperOS 3 Super Island payload. */
object HyperOsFocusNotification {
    private const val iconKey = "miui.focus.pic_focus_timer"
    private const val pauseActionKey = "miui.focus.action_pause"
    private const val endActionKey = "miui.focus.action_end"

    fun protocolVersion(context: Context): Int = runCatching {
        Settings.System.getInt(
            context.contentResolver,
            "notification_focus_protocol",
            0,
        )
    }.getOrDefault(0)

    private val islandSupported by lazy {
        runCatching {
        val systemProperties = Class.forName("android.os.SystemProperties")
        val getter = systemProperties.getDeclaredMethod(
            "getBoolean",
            String::class.java,
            Boolean::class.javaPrimitiveType,
        )
        getter.invoke(null, "persist.sys.feature.island", false) as? Boolean ?: false
        }.getOrDefault(false)
    }

    fun supportsIsland(): Boolean = islandSupported

    fun decorate(
        context: Context,
        notification: Notification,
        mode: String,
        phase: String,
        status: String,
        primaryTime: String,
        supportingText: String,
        timeoutSeconds: Int,
        pauseAction: Notification.Action?,
        endAction: Notification.Action?,
    ) {
        // Supplying the payload is safe on non-Xiaomi Android: it remains an
        // opaque notification extra and the regular notification is unchanged.
        val pictures = Bundle().apply {
            putParcelable(
                iconKey,
                Icon.createWithResource(context, R.drawable.ic_focus_timer),
            )
        }
        notification.extras.putBundle("miui.focus.pics", pictures)

        val actions = Bundle()
        pauseAction?.let { actions.putParcelable(pauseActionKey, it) }
        endAction?.let { actions.putParcelable(endActionKey, it) }
        if (!actions.isEmpty) notification.extras.putBundle("miui.focus.actions", actions)

        val modeLabel = when {
            mode == "pomodoro" && phase == "rest" -> "番茄休息"
            mode == "pomodoro" -> "番茄专注"
            mode == "stopwatch" -> "正计时"
            else -> "倒计时"
        }
        val statusLabel = when (status) {
            "paused" -> "暂停中"
            "overtime" -> "已到点"
            "finished" -> "完成啦"
            else -> "专注中"
        }
        val ticker = "$modeLabel $primaryTime"

        val param = JSONObject().apply {
            put("protocol", 1)
            // Xiaomi assigns/approves the final business value during scene review.
            put("business", "study_focus")
            put("enableFloat", true)
            put("islandFirstFloat", status == "overtime" || status == "finished")
            put("updatable", true)
            put("timeout", 720)
            put("ticker", ticker)
            put("tickerPic", iconKey)
            put("aodTitle", ticker)
            put("aodPic", iconKey)
            put(
                "param_island",
                JSONObject().apply {
                    put("islandProperty", 2)
                    put("islandOrder", status == "overtime")
                    put("islandTimeout", timeoutSeconds.coerceIn(60, 43_200))
                    put(
                        "bigIslandArea",
                        JSONObject().apply {
                            put(
                                "imageTextInfoLeft",
                                imageTextArea(modeLabel, primaryTime, statusLabel),
                            )
                            put("picInfo", pictureInfo())
                        },
                    )
                    put(
                        "smallIslandArea",
                        JSONObject().apply {
                            put(
                                "imageTextInfoLeft",
                                imageTextArea("", primaryTime, ""),
                            )
                            put("picInfo", pictureInfo())
                        },
                    )
                },
            )
            put(
                "baseInfo",
                JSONObject().apply {
                    put("title", "宝宝今天已经专注了")
                    put("content", supportingText)
                    put("colorTitle", "#6F91D5")
                    put("type", 2)
                },
            )
            val actionArray = JSONArray()
            pauseAction?.let { actionArray.put(JSONObject().put("action", pauseActionKey)) }
            endAction?.let { actionArray.put(JSONObject().put("action", endActionKey)) }
            if (actionArray.length() > 0) put("actions", actionArray)
        }
        notification.extras.putString(
            "miui.focus.param",
            JSONObject().put("param_v2", param).toString(),
        )
    }

    private fun imageTextArea(front: String, title: String, content: String) =
        JSONObject().apply {
            put("type", 1)
            put("picInfo", pictureInfo())
            put(
                "textInfo",
                JSONObject().apply {
                    put("frontTitle", front)
                    put("title", title)
                    put("content", content)
                    put("useHighLight", false)
                },
            )
        }

    private fun pictureInfo() = JSONObject().apply {
        put("type", 1)
        put("pic", iconKey)
    }
}
