package com.example.blue_hydrangea

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/** User-supplied credential only. Never stores prompts, moods or responses. */
object DailyPhraseCredentials {
    private const val alias = "blue_hydrangea_deepseek_v1"

    private fun file(context: Context) =
        AtomicFile(File(context.noBackupFilesDir, "deepseek_credential_v1"))

    private fun key(create: Boolean): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        check(create) { "Credential unavailable" }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(
                KeyGenParameterSpec.Builder(
                    alias,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
            generateKey()
        }
    }

    @Synchronized
    fun hasKey(context: Context): Boolean = file(context).baseFile.exists()

    @Synchronized
    fun save(context: Context, value: String) {
        val clean = value.trim()
        require(clean.length in 8..512 && clean.all { it.code in 33..126 })
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(create = true))
        val bytes = clean.toByteArray(Charsets.UTF_8)
        val encrypted = try { cipher.doFinal(bytes) } finally { bytes.fill(0) }
        val json = JSONObject().apply {
            put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            put("value", Base64.encodeToString(encrypted, Base64.NO_WRAP))
        }.toString().toByteArray(Charsets.UTF_8)
        val target = file(context)
        val stream = target.startWrite()
        try {
            stream.write(json)
            target.finishWrite(stream)
        } catch (error: Exception) {
            target.failWrite(stream)
            throw error
        }
    }

    @Synchronized
    fun read(context: Context): String? {
        if (!hasKey(context)) return null
        val json = JSONObject(String(file(context).readFully(), Charsets.UTF_8))
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(create = false),
            GCMParameterSpec(128, Base64.decode(json.getString("iv"), Base64.NO_WRAP)),
        )
        val bytes = cipher.doFinal(Base64.decode(json.getString("value"), Base64.NO_WRAP))
        return try { String(bytes, Charsets.UTF_8) } finally { bytes.fill(0) }
    }

    @Synchronized
    fun remove(context: Context) {
        file(context).delete()
        check(!hasKey(context)) { "Credential removal failed" }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias(alias)) store.deleteEntry(alias)
    }
}
