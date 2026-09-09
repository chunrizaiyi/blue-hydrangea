package com.example.blue_hydrangea

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import kotlin.math.PI
import kotlin.math.sin

/**
 * A short, gentle two-note reminder rendered on the media route. Unlike a
 * Ringtone with USAGE_ALARM, this follows wired/Bluetooth headset routing and
 * is controlled by the phone's media volume.
 */
class GentleMediaAlert(
    context: Context,
    private val handler: Handler,
) {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()
    private val focusListener = AudioManager.OnAudioFocusChangeListener { }
    private var focusRequest: AudioFocusRequest? = null
    private var track: AudioTrack? = null
    private var stopRunnable: Runnable? = null

    val isPlaying: Boolean
        get() = track?.playState == AudioTrack.PLAYSTATE_PLAYING

    fun start(loop: Boolean, maxDurationMs: Long = 60_000L): Boolean {
        if (isPlaying) return true
        stop()
        if (!requestAudioFocus()) {
            abandonAudioFocus()
            return false
        }

        val samples = createGentleChime()
        val next = runCatching {
            AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setBufferSizeInBytes(samples.size * Short.SIZE_BYTES)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()
        }.getOrNull() ?: run {
            abandonAudioFocus()
            return false
        }

        val started = runCatching {
            val written = next.write(samples, 0, samples.size, AudioTrack.WRITE_BLOCKING)
            if (written <= 0) return@runCatching false
            if (loop) next.setLoopPoints(0, samples.size, -1)
            next.play()
            true
        }.getOrDefault(false)
        if (!started) {
            runCatching { next.release() }
            abandonAudioFocus()
            return false
        }
        track = next

        val stopAfter = if (loop) maxDurationMs else oneShotDurationMs
        stopRunnable = Runnable { stop() }.also { handler.postDelayed(it, stopAfter) }
        return true
    }

    fun stop() {
        stopRunnable?.let(handler::removeCallbacks)
        stopRunnable = null
        track?.let { current ->
            runCatching { current.stop() }
            runCatching { current.flush() }
            runCatching { current.release() }
        }
        track = null
        abandonAudioFocus()
    }

    private fun requestAudioFocus(): Boolean {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val request = AudioFocusRequest.Builder(
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
                )
                    .setAudioAttributes(attributes)
                    .setOnAudioFocusChangeListener(focusListener, handler)
                    .build()
                focusRequest = request
                audioManager.requestAudioFocus(request) ==
                    AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(
                    focusListener,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
                ) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            }
        }.getOrDefault(false)
    }

    private fun abandonAudioFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { runCatching { audioManager.abandonAudioFocusRequest(it) } }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            runCatching { audioManager.abandonAudioFocus(focusListener) }
        }
    }

    private fun createGentleChime(): ShortArray {
        val frames = (sampleRate * chimeCycleSeconds).toInt()
        return ShortArray(frames) { index ->
            val time = index.toDouble() / sampleRate
            val note = when {
                time < .62 -> tone(time, 659.25, .62)
                time < 1.28 -> tone(time - .66, 783.99, .62)
                else -> 0.0
            }
            (note * Short.MAX_VALUE * .18).toInt().toShort()
        }
    }

    private fun tone(time: Double, frequency: Double, length: Double): Double {
        if (time < 0.0 || time >= length) return 0.0
        val fade = .08
        val envelope = when {
            time < fade -> time / fade
            time > length - fade -> (length - time) / fade
            else -> 1.0
        }.coerceIn(0.0, 1.0)
        return sin(2.0 * PI * frequency * time) * envelope
    }

    companion object {
        private const val sampleRate = 44_100
        private const val chimeCycleSeconds = 2.2
        private const val oneShotDurationMs = 2_300L
    }
}

