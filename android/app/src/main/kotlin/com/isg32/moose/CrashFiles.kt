package com.isg32.moose

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Crash logging on the Android side (see lib/platform/crash_log.dart).
 *
 * - [installCrashHandler]: an uncaught Kotlin/Java exception kills the app
 *   before Flutter can show anything, so its stack trace is written to
 *   `<files>/crashes/native-<time>.txt`; the next launch shows it.
 * - `moose/files` → `saveToDownloads({name, text})`: writes a log to the
 *   public Downloads folder (MediaStore on Android 10+, no permission);
 *   `crashDir()`: where crash files live, for the Dart side.
 */
object CrashFiles {
    private const val CHANNEL = "moose/files"

    @Volatile
    private var installed = false

    fun installCrashHandler(context: Context) {
        if (installed) return
        installed = true
        val app = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val dir = File(app.filesDir, "crashes").apply { mkdirs() }
                val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
                val trace = StringWriter().also { error.printStackTrace(PrintWriter(it)) }
                File(dir, "native-$stamp.txt").writeText(
                    "Thread: ${thread.name}\n" +
                        "Device: ${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})\n\n" +
                        trace,
                )
            } catch (_: Throwable) {
                // Nothing more can be done while crashing.
            }
            previous?.uncaughtException(thread, error)
        }
    }

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "crashDir" -> result.success(File(app.filesDir, "crashes").apply { mkdirs() }.absolutePath)
                "saveToDownloads" -> try {
                    val name = call.argument<String>("name") ?: "moose-log.txt"
                    val text = call.argument<String>("text") ?: ""
                    result.success(saveToDownloads(app, name, text))
                } catch (e: Exception) {
                    result.error("save", e.message ?: e.javaClass.simpleName, null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(context: Context, name: String, text: String): String {
        val bytes = text.toByteArray()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: error("Downloads is not available")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: error("Could not write to Downloads")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } else {
            @Suppress("DEPRECATION")
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            dir.mkdirs()
            File(dir, name).writeBytes(bytes)
        }
        return "Downloads/$name"
    }
}
