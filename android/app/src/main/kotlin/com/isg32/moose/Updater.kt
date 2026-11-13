package com.isg32.moose

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.app.Notification
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Over-the-air updates (see lib/net/updater.dart): what is installed, whether a
 * downloaded APK can replace it, and installing it through PackageInstaller.
 */
object Updater {
    private const val CHANNEL = "moose/update"
    private const val STATUS_ACTION = "com.isg32.moose.UPDATE_STATUS"

    /** The open Flutter side, to hear how an install went. */
    private var channel: MethodChannel? = null

    fun register(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "info" -> result.success(info(app))
                    "check" -> result.success(check(app, call.argument<String>("path")!!))
                    "openInstallSettings" -> {
                        openInstallSettings(context)
                        result.success(null)
                    }
                    "install" -> {
                        install(app, call.argument<String>("path")!!)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("update", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun installed(context: Context): PackageInfo {
        val pm = context.packageManager
        return if (Build.VERSION.SDK_INT >= 33) {
            pm.getPackageInfo(
                context.packageName,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        }
    }

    private fun code(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode
        else @Suppress("DEPRECATION") info.versionCode.toLong()

    /** SHA-256 of each signing certificate (the current one, after rotation). */
    private fun signers(info: PackageInfo?): Set<String> {
        val sig = info?.signingInfo ?: return emptySet()
        val certs = if (sig.hasMultipleSigners()) sig.apkContentsSigners else sig.signingCertificateHistory
        val md = MessageDigest.getInstance("SHA-256")
        return certs.map { c -> md.digest(c.toByteArray()).joinToString("") { "%02x".format(it) } }.toSet()
    }

    private fun info(context: Context): Map<String, Any?> {
        val me = installed(context)
        val canInstall = if (Build.VERSION.SDK_INT >= 26) {
            context.packageManager.canRequestPackageInstalls()
        } else {
            true
        }
        return mapOf(
            "versionCode" to code(me),
            "versionName" to me.versionName,
            "abi" to Build.SUPPORTED_ABIS.firstOrNull(),
            "canInstall" to canInstall,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }

    /** What the APK at [path] is, and whether Android would let it update Moose. */
    private fun check(context: Context, path: String): Map<String, Any?> {
        val pm = context.packageManager
        val apk: PackageInfo? = if (Build.VERSION.SDK_INT >= 33) {
            pm.getPackageArchiveInfo(
                path,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageArchiveInfo(path, PackageManager.GET_SIGNING_CERTIFICATES)
        }
        if (apk == null) return mapOf("valid" to false)
        val me = installed(context)
        val mine = signers(me)
        // The new APK's signers (its rotation history included) must include
        // the installed app's current signer.
        val theirs = apk.signingInfo?.let { s ->
            val md = MessageDigest.getInstance("SHA-256")
            val certs = if (s.hasMultipleSigners()) s.apkContentsSigners else s.signingCertificateHistory
            certs.map { c -> md.digest(c.toByteArray()).joinToString("") { "%02x".format(it) } }.toSet()
        } ?: emptySet()
        return mapOf(
            "valid" to true,
            "package" to apk.packageName,
            "versionCode" to code(apk),
            "versionName" to apk.versionName,
            "sameSigner" to theirs.any { it in mine },
        )
    }

    private fun openInstallSettings(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    /** Streams [path] into a PackageInstaller session and commits it. */
    private fun install(context: Context, path: String) {
        val file = File(path)
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(context.packageName)
        params.setSize(file.length())
        if (Build.VERSION.SDK_INT >= 31) {
            // Once Moose installed itself, Android can skip the confirm step.
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        if (Build.VERSION.SDK_INT >= 26) {
            params.setInstallReason(PackageManager.INSTALL_REASON_USER)
        }
        val id = installer.createSession(params)
        val session = installer.openSession(id)
        try {
            file.inputStream().use { input ->
                session.openWrite("moose.apk", 0, file.length()).use { out ->
                    input.copyTo(out, 1 shl 16)
                    session.fsync(out)
                }
            }
            val intent = Intent(context, UpdateReceiver::class.java).setAction(STATUS_ACTION)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val pending = PendingIntent.getBroadcast(context, id, intent, flags)
            session.commit(pending.intentSender)
        } catch (e: Exception) {
            session.abandon()
            throw e
        } finally {
            session.close()
        }
    }

    /** Tells the Flutter side, if it is still open, how the install went. */
    fun report(code: Int, message: String?) {
        Handler(Looper.getMainLooper()).post {
            channel?.invokeMethod("status", mapOf("code" to code, "message" to message))
        }
    }

    const val UPDATES_CHANNEL = "updates"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = context.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(UPDATES_CHANNEL) != null) return
        nm.createNotificationChannel(
            NotificationChannel(UPDATES_CHANNEL, "Updates", NotificationManager.IMPORTANCE_LOW).apply {
                description = "When Moose has updated itself"
            },
        )
    }
}

/** Where PackageInstaller says how an install went. */
class UpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            // Android's "Update Moose?" screen.
            val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_INTENT)
            }
            confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (confirm != null) context.startActivity(confirm)
            Updater.report(-1, null)
            return
        }
        Updater.report(status, intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE))
    }
}

/** After Moose is replaced by a newer copy: a quiet note to open it again. */
class UpdatedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        Updater.ensureChannel(context)
        val name = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        } catch (_: Exception) {
            null
        }
        val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val tap = open?.let {
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, Updater.UPDATES_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val n = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(if (name != null) "Moose updated to $name" else "Moose updated")
            .setContentText("Tap to open")
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        try {
            context.getSystemService(NotificationManager::class.java).notify(4401, n)
        } catch (_: SecurityException) {
            // Notifications off: nothing to say.
        }
    }
}
