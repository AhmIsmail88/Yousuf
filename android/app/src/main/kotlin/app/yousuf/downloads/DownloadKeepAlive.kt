package app.yousuf.downloads

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import app.yousuf.MainActivity
import app.yousuf.R
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * يبقي التطبيق حيّاً أثناء تحميل التلاوات الطويل (المصحف ≈ ٢ ج.ب).
 *
 * التنزيل نفسه في Dart؛ هذه الخدمة في المقدمة (dataSync) تمنع النظام من
 * إيقاف العملية حين يخرج المستخدم من الشاشة أو يقفل الهاتف، وتعرض إشعاراً
 * بالتقدّم وزر «إيقاف» يُبلغ Dart بالإلغاء.
 *
 * القناة `yousuf/downloads`: start(title) · progress(title, done, total) · stop.
 */
class DownloadKeepAliveService : Service() {

    companion object {
        private const val TAG = "YousufDownloads"
        private const val CHANNEL_ID = "downloads"
        private const val NOTIFICATION_ID = 7101
        private const val ACTION_UPDATE = "app.yousuf.downloads.UPDATE"
        private const val ACTION_CANCEL = "app.yousuf.downloads.CANCEL"

        private var channel: MethodChannel? = null
        private val main = Handler(Looper.getMainLooper())

        fun register(context: Context, messenger: BinaryMessenger) {
            val app = context.applicationContext
            val methodChannel = MethodChannel(messenger, "yousuf/downloads")
            channel = methodChannel
            methodChannel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start", "progress" -> {
                            val intent = Intent(app, DownloadKeepAliveService::class.java)
                                .setAction(ACTION_UPDATE)
                                .putExtra("title", call.argument<String>("title") ?: "")
                                .putExtra("done", call.argument<Int>("done") ?: 0)
                                .putExtra("total", call.argument<Int>("total") ?: 0)
                            if (call.method == "start") {
                                ContextCompat.startForegroundService(app, intent)
                            } else {
                                app.startService(intent)
                            }
                            result.success(true)
                        }
                        "stop" -> {
                            app.stopService(Intent(app, DownloadKeepAliveService::class.java))
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    Log.e(TAG, "فشل ${call.method}", error)
                    result.error("downloads_error", error.message, null)
                }
            }
        }

        private fun notifyCancelled() {
            main.post { channel?.invokeMethod("cancelled", null) }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            notifyCancelled()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra("title") ?: ""
        val done = intent?.getIntExtra("done", 0) ?: 0
        val total = intent?.getIntExtra("total", 0) ?: 0
        val notification = build(title, done, total)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun build(title: String, done: Int, total: Int): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "تحميل التلاوات", NotificationManager.IMPORTANCE_LOW),
        )
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val cancel = PendingIntent.getService(
            this, 2,
            Intent(this, DownloadKeepAliveService::class.java).setAction(ACTION_CANCEL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_yousuf)
            .setColor(0xFF2F6F7A.toInt())
            .setContentTitle(title.ifEmpty { "تحميل التلاوات" })
            .setContentText(if (total > 0) "$done / $total" else "")
            .setProgress(total, done, total == 0)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(R.drawable.ic_stat_yousuf, "إيقاف", cancel)
            .build()
    }
}
