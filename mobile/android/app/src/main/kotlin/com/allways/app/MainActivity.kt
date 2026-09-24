package com.allways.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val updaterChannel = "com.allways.app/apk_installer"
    private val installAction = "com.allways.app.PACKAGE_INSTALL_STATUS"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "createNotificationChannel" -> {
                        createNotificationChannel()
                        result.success("created")
                    }
                    "showNotification" -> {
                        val title = call.argument<String>("title") ?: "ALLways"
                        val body = call.argument<String>("body") ?: "You have a new ALLways update."
                        showNotification(title, body)
                        result.success("shown")
                    }
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = NotificationChannel(
                "allways_updates",
                "ALLways Updates",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "ALLways order and account notifications"
                enableVibration(true)
                setShowBadge(true)
            }
            manager.createNotificationChannel(channel)
        }
    }

    private fun showNotification(title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission("android.permission.POST_NOTIFICATIONS") != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        createNotificationChannel()

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingFlags =
            PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(this, 1001, it, pendingFlags)
        }

        val notification = NotificationCompat.Builder(this, "allways_updates")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setDefaults(android.app.Notification.DEFAULT_ALL)
            .apply { if (pendingIntent != null) setContentIntent(pendingIntent) }
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), notification)
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("NO_APK", "APK path is missing", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()) {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName")
                    )
                )
                result.success("permission_required")
                return
            }
            val apk = File(path)
            if (!apk.exists() || !apk.isFile || !apk.canRead() || apk.length() <= 0L) {
                result.error("NO_APK", "Downloaded APK is missing or unreadable", null)
                return
            }

            val installer = packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL
            )
            params.setAppPackageName(packageName)
            params.setAppLabel("ALLways")

            val sessionId = installer.createSession(params)
            val session = installer.openSession(sessionId)
            try {
                session.openWrite("package", 0, apk.length()).use { output ->
                    FileInputStream(apk).use { input ->
                        input.copyTo(output, 1024 * 1024)
                    }
                    session.fsync(output)
                }

                val statusIntent = Intent(this, InstallStatusReceiver::class.java).apply {
                    action = installAction
                    putExtra("sessionId", sessionId)
                }

                val flags =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }

                session.commit(
                    PendingIntent.getBroadcast(
                        this,
                        sessionId,
                        statusIntent,
                        flags
                    ).intentSender
                )
                result.success("started")
            } catch (e: Exception) {
                try { session.abandon() } catch (_: Exception) {}
                throw e
            } finally {
                try { session.close() } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            result.error(
                "INSTALL_FAILED",
                e.message ?: "Package installation failed",
                null
            )
        }
    }

    class InstallStatusReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (
                intent.getIntExtra(
                    PackageInstaller.EXTRA_STATUS,
                    PackageInstaller.STATUS_FAILURE
                ) == PackageInstaller.STATUS_PENDING_USER_ACTION
            ) {
                val confirmIntent =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(
                            Intent.EXTRA_INTENT,
                            Intent::class.java
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(Intent.EXTRA_INTENT)
                    }

                if (confirmIntent != null) {
                    confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirmIntent)
                }
            }
        }
    }
}

