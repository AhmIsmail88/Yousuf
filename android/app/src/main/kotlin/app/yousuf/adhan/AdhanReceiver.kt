package app.yousuf.adhan

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.runBlocking

/**
 * يستقبل المنبّه ويقرّر ما يحدث (SPEC §6):
 *
 * - تنبيه ما قبل الصلاة / الإقامة: إشعار بصوت الهاتف الافتراضي، بلا أذان.
 * - الأذان: خدمة التشغيل فقط إن كان الوضع «كامل/تكبير» والهاتف ليس في مكالمة
 *   (وليس صامتاً إن طلب المستخدم احترام الصمت)؛ وإلا إشعار بلا صوت.
 * - الصلاة المطفأة: لا شيء (ولا تُجدول أصلاً).
 *
 * القرار هنا لا في الخدمة: لا تُشغَّل خدمة مقدمة إلا إن كانت ستعمل فعلاً،
 * لأن خدمة مقدمة لا تستدعي startForeground تُسقط التطبيق على أندرويد 8+.
 * بعد كل منبّه (عدا التجربة) يعاد بناء الجدول.
 */
class AdhanReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val kind = intent.getStringExtra("kind") ?: AdhanScheduler.KIND_ADHAN
        val prayer = intent.getStringExtra("prayer") ?: "fajr"
        val app = context.applicationContext

        val pending = goAsync()
        Thread {
            try {
                val config = runBlocking { AdhanPrefs.load(app) }
                handle(app, kind, prayer, config)
                if (kind != AdhanScheduler.KIND_TEST && config != null) {
                    AdhanScheduler.scheduleNext(app, config)
                }
            } catch (error: Exception) {
                // شبكة الأمان الدورية ستصلح أي منبّه ضائع.
                Log.e(TAG, "فشل معالجة منبّه $kind/$prayer", error)
            } finally {
                pending.finish()
            }
        }.start()
    }

    private fun handle(context: Context, kind: String, prayer: String, config: AdhanConfig?) {
        when (kind) {
            AdhanScheduler.KIND_PRE -> {
                if (config?.modeFor(prayer) == "off") return
                AdhanNotifications.notifyPrePrayer(
                    context, prayer, config?.prePrayerAlertMinutes ?: 15,
                )
            }

            AdhanScheduler.KIND_IQAMA -> {
                if (config?.modeFor(prayer) == "off") return
                AdhanNotifications.notifyIqama(context, prayer)
            }

            AdhanScheduler.KIND_TEST -> {
                if (AdhanNotifications.isInCall(context)) {
                    AdhanNotifications.notifyAdhanSilently(context, prayer, "أثناء مكالمة — بلا صوت")
                    return
                }
                startPlayback(context, prayer, kind, "full", config?.soundFor("fajr") ?: "makkah")
            }

            else -> {
                val mode = config?.modeFor(prayer) ?: "full"
                when {
                    mode == "off" -> Unit
                    mode == "notification" -> AdhanNotifications.notifyAdhanSilently(context, prayer)
                    AdhanNotifications.isInCall(context) ->
                        AdhanNotifications.notifyAdhanSilently(context, prayer, "أثناء مكالمة — بلا صوت")
                    config?.respectSilentMode == true && AdhanNotifications.isSilentMode(context) ->
                        AdhanNotifications.notifyAdhanSilently(context, prayer, "الهاتف صامت")
                    else -> startPlayback(context, prayer, kind, mode, config?.soundFor(prayer) ?: "makkah")
                }
            }
        }
    }

    private fun startPlayback(
        context: Context,
        prayer: String,
        kind: String,
        mode: String,
        sound: String,
    ) {
        val service = Intent(context, AdhanService::class.java).apply {
            action = AdhanService.ACTION_PLAY
            putExtra("prayer", prayer)
            putExtra("kind", kind)
            putExtra("mode", mode)
            putExtra("sound", sound)
        }
        try {
            ContextCompat.startForegroundService(context, service)
        } catch (error: Exception) {
            // Android 12+ قد يرفض بدء خدمة مقدمة من الخلفية — إشعار بديل.
            Log.e(TAG, "تعذر بدء خدمة الأذان", error)
            AdhanNotifications.notifyAdhanSilently(context, prayer)
        }
    }

    private companion object {
        const val TAG = "YousufAdhan"
    }
}
