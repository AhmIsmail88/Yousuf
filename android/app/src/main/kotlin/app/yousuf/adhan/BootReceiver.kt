package app.yousuf.adhan

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.runBlocking

/**
 * يعيد جدولة المنبّهات بعد: إعادة التشغيل (ومنها «التشغيل السريع» في أجهزة
 * HTC/شاومي/هواوي)، تغيير الوقت أو المنطقة الزمنية، وتحديث الحزمة
 * (SPEC §6: BootReceiver).
 */
class BootReceiver : BroadcastReceiver() {

    private val handledActions = setOf(
        Intent.ACTION_BOOT_COMPLETED,
        "android.intent.action.QUICKBOOT_POWERON",
        "com.htc.intent.action.QUICKBOOT_POWERON",
        Intent.ACTION_TIME_CHANGED,
        Intent.ACTION_TIMEZONE_CHANGED,
        Intent.ACTION_MY_PACKAGE_REPLACED,
    )

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in handledActions) return
        val app = context.applicationContext

        val pending = goAsync()
        Thread {
            try {
                val config = runBlocking { AdhanPrefs.load(app) }
                if (config != null) AdhanScheduler.scheduleNext(app, config)
                SafetyNetWorker.enqueue(app)
            } catch (error: Exception) {
                Log.e("YousufAdhan", "فشلت إعادة الجدولة بعد $action", error)
            } finally {
                pending.finish()
            }
        }.start()
    }
}
