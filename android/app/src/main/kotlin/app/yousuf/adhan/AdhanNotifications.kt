package app.yousuf.adhan

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.util.Log
import androidx.core.app.NotificationCompat
import app.yousuf.MainActivity
import app.yousuf.R

/**
 * قنوات وإشعارات الأذان (SPEC §9).
 *
 * - [CHANNEL_ADHAN]: إشعار خدمة الأذان (الصوت يأتي من الخدمة لا من القناة).
 * - [CHANNEL_PRE]: تنبيه قبل الصلاة — بصوت إشعار الهاتف الافتراضي.
 * - [CHANNEL_IQAMA]: تذكير الإقامة — بصوت إشعار الهاتف الافتراضي.
 */
object AdhanNotifications {
    const val CHANNEL_ADHAN = "adhan"
    const val CHANNEL_PRE = "pre_prayer"
    const val CHANNEL_IQAMA = "iqama"

    const val ID_SERVICE = 7001
    private const val ID_ADHAN_SILENT = 7002
    private const val ID_PRE = 7003
    private const val ID_IQAMA = 7004

    private const val TAG = "YousufAdhan"
    private const val BRAND_COLOR = 0xFF2F6F7A.toInt()

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val adhan = NotificationChannel(
            CHANNEL_ADHAN,
            "الأذان",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "تنبيه الصلاة — الصوت يُشغَّل من خدمة الأذان"
            setSound(null, null)
            enableVibration(true)
        }
        val pre = NotificationChannel(
            CHANNEL_PRE,
            "قبل الصلاة",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = "تنبيه قبل الصلاة بعدة دقائق (صوت الإشعار الافتراضي)" }
        val iqama = NotificationChannel(
            CHANNEL_IQAMA,
            "الإقامة",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = "تذكير بالإقامة بعد الأذان (صوت الإشعار الافتراضي)" }
        manager.createNotificationChannels(listOf(adhan, pre, iqama))
    }

    fun prayerLabel(prayer: String): String = when (prayer) {
        "fajr" -> "الفجر"
        "dhuhr" -> "الظهر"
        "asr" -> "العصر"
        "maghrib" -> "المغرب"
        "isha" -> "العشاء"
        else -> prayer
    }

    /** هل الهاتف في مكالمة الآن؟ — لا يُرفع الأذان فوق مكالمة. */
    fun isInCall(context: Context): Boolean {
        val audio = context.getSystemService(AudioManager::class.java) ?: return false
        return audio.mode == AudioManager.MODE_IN_CALL ||
            audio.mode == AudioManager.MODE_IN_COMMUNICATION ||
            audio.mode == AudioManager.MODE_RINGTONE
    }

    /**
     * هل الهاتف صامت فعلاً؟ الاهتزاز **ليس** صامتاً: من يضع هاتفه على الاهتزاز
     * لا يريد أن يفوته الأذان. «عدم الإزعاج» يُعدّ صامتاً.
     */
    fun isSilentMode(context: Context): Boolean {
        val audio = context.getSystemService(AudioManager::class.java) ?: return false
        if (audio.ringerMode == AudioManager.RINGER_MODE_SILENT) return true
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        return manager.currentInterruptionFilter > NotificationManager.INTERRUPTION_FILTER_ALL
    }

    private fun openAppIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun base(context: Context, channel: String, title: String, text: String) =
        NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_stat_yousuf)
            .setColor(BRAND_COLOR)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openAppIntent(context))
            .setCategory(NotificationCompat.CATEGORY_REMINDER)

    /** إشعار خدمة الأذان أثناء التشغيل — فيه زر إيقاف. */
    fun serviceNotification(context: Context, prayer: String, kind: String): Notification {
        val label = prayerLabel(prayer)
        val title = if (kind == AdhanScheduler.KIND_TEST) {
            "أذان تجريبي — صلاة $label"
        } else {
            "حان الآن موعد صلاة $label"
        }
        val stopIntent = PendingIntent.getService(
            context,
            1,
            Intent(context, AdhanService::class.java).setAction(AdhanService.ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return base(context, CHANNEL_ADHAN, title, "يوسف — رفيقك في الطاعة")
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .setContentText("للإيقاف: زر «إيقاف» أو زر التشغيل أو أحد زرّي الصوت")
            .addAction(R.drawable.ic_stat_yousuf, "إيقاف", stopIntent)
            .setDeleteIntent(stopIntent)
            .build()
    }

    /** إشعار الأذان بلا صوت (وضع «إشعار» أو صامت أو أثناء مكالمة). */
    fun notifyAdhanSilently(context: Context, prayer: String, reason: String? = null) {
        val text = reason ?: "يوسف — رفيقك في الطاعة"
        post(
            context,
            ID_ADHAN_SILENT,
            base(context, CHANNEL_ADHAN, "حان الآن موعد صلاة ${prayerLabel(prayer)}", text)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build(),
        )
    }

    /** تنبيه ما قبل الصلاة — صوت الإشعار الافتراضي فقط، بلا أذان. */
    fun notifyPrePrayer(context: Context, prayer: String, minutes: Int) {
        post(
            context,
            ID_PRE,
            base(
                context,
                CHANNEL_PRE,
                "بعد $minutes دقيقة: صلاة ${prayerLabel(prayer)}",
                "استعد للصلاة",
            ).setAutoCancel(true).build(),
        )
    }

    /** تذكير الإقامة بعد الأذان. */
    fun notifyIqama(context: Context, prayer: String) {
        post(
            context,
            ID_IQAMA,
            base(
                context,
                CHANNEL_IQAMA,
                "إقامة صلاة ${prayerLabel(prayer)}",
                "حان وقت إقامة الصلاة",
            ).setAutoCancel(true).build(),
        )
    }

    private fun post(context: Context, id: Int, notification: Notification) {
        try {
            context.getSystemService(NotificationManager::class.java)?.notify(id, notification)
        } catch (error: SecurityException) {
            // Android 13+: إذن الإشعارات مرفوض.
            Log.w(TAG, "تعذر إظهار الإشعار — الإذن مرفوض", error)
        }
    }
}
