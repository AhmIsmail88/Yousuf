package app.yousuf.adhan

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import app.yousuf.MainActivity
import kotlinx.datetime.Clock

/**
 * جدولة الأذان بـ AlarmManager.setAlarmClock لأقرب 5 صلوات **مفعّلة**،
 * مع تنبيه ما قبل الصلاة وتذكير الإقامة لكل منها (SPEC §6).
 *
 * الصلوات المطفأة (`mode = off`) لا تُجدول أصلاً. تُلغى القديمة وتُضبط من
 * جديد في كل مرة، ويُحفظ وقت أقرب أذان لتتحقق منه شبكة الأمان.
 */
object AdhanScheduler {
    private const val TAG = "YousufAdhan"
    private const val REQUEST_ADHAN_BASE = 1000
    private const val REQUEST_PRE_BASE = 2000
    private const val REQUEST_IQAMA_BASE = 3000
    private const val REQUEST_TEST = 9000
    private const val MAX_ADHAN_ALARMS = 6
    private const val LOOKBACK_MS = 61 * 60_000L

    private const val META_PREFS = "adhan_meta"
    private const val KEY_NEXT = "next_adhan_ms"

    const val KIND_ADHAN = "adhan"
    const val KIND_PRE = "pre_prayer"
    const val KIND_IQAMA = "iqama"
    const val KIND_TEST = "test"

    data class ScheduleResult(val scheduled: Int, val nextEpochMs: Long)

    fun scheduleNext(context: Context, config: AdhanConfig): ScheduleResult {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
            ?: return ScheduleResult(0, 0L)
        cancelAll(context)
        val now = Clock.System.now().toEpochMilliseconds()
        val enabled = config.enabledPrayers()
        // نبدأ من قبل ساعة: أذان انطلق للتو قد يبقى له تذكير إقامة قادم،
        // وإعادة الجدولة بعد الأذان مباشرة يجب ألا تلغيه.
        val from = kotlinx.datetime.Instant.fromEpochMilliseconds(now - LOOKBACK_MS)
        val adhans = PrayerCalc.upcomingAdhans(
            config, MAX_ADHAN_ALARMS, from = from, prayers = enabled,
        )
        var scheduled = 0
        var next = 0L
        adhans.forEachIndexed { index, item ->
            val at = item.instant.toEpochMilliseconds()
            val prayer = item.prayer.name.lowercase()

            val iqamaMinutes = config.iqamaReminderMinutes
            if (iqamaMinutes in 1..60) {
                val iqamaAt = at + iqamaMinutes * 60_000L
                if (iqamaAt > now) {
                    setAlarm(context, alarmManager, REQUEST_IQAMA_BASE + index, iqamaAt, KIND_IQAMA, prayer)
                    scheduled++
                }
            }

            if (at <= now) return@forEachIndexed
            setAlarm(context, alarmManager, REQUEST_ADHAN_BASE + index, at, KIND_ADHAN, prayer)
            scheduled++
            if (next == 0L || at < next) next = at

            val lead = config.prePrayerAlertMinutes
            if (lead in 1..60) {
                val preAt = at - lead * 60_000L
                if (preAt > now) {
                    setAlarm(context, alarmManager, REQUEST_PRE_BASE + index, preAt, KIND_PRE, prayer)
                    scheduled++
                }
            }
        }
        saveNext(context, next)
        Log.i(TAG, "جُدول $scheduled منبّهاً — الأقرب عند $next")
        return ScheduleResult(scheduled, next)
    }

    /** منبّه تجريبي بعد [seconds] ثانية (زر «جرّب الأذان»). */
    fun scheduleTest(context: Context, seconds: Int): ScheduleResult {
        val am = context.getSystemService(AlarmManager::class.java)
            ?: return ScheduleResult(0, 0L)
        val at = Clock.System.now().toEpochMilliseconds() +
            seconds.coerceIn(5, 3600) * 1000L
        setAlarm(context, am, REQUEST_TEST, at, kind = KIND_TEST, prayer = "fajr")
        return ScheduleResult(1, at)
    }

    /**
     * هل الجدولة سليمة؟ — وقت أقرب أذان المحفوظ يجب أن يكون في المستقبل.
     *
     * لا نعتمد على وجود PendingIntent: يبقى موجوداً بعد انطلاق المنبّه
     * فيوهم بأن الجدولة سليمة وهي ليست كذلك.
     */
    fun isScheduleHealthy(context: Context): Boolean {
        val next = nextAdhanEpochMs(context)
        return next > Clock.System.now().toEpochMilliseconds()
    }

    /** وقت أقرب أذان مجدول فعلاً (0 = لا شيء). */
    fun nextAdhanEpochMs(context: Context): Long =
        context.getSharedPreferences(META_PREFS, Context.MODE_PRIVATE).getLong(KEY_NEXT, 0L)

    private fun saveNext(context: Context, epochMs: Long) {
        context.getSharedPreferences(META_PREFS, Context.MODE_PRIVATE)
            .edit().putLong(KEY_NEXT, epochMs).apply()
    }

    fun cancelAll(context: Context) {
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        for (i in 0 until MAX_ADHAN_ALARMS) {
            cancelRequest(context, am, REQUEST_ADHAN_BASE + i)
            cancelRequest(context, am, REQUEST_PRE_BASE + i)
            cancelRequest(context, am, REQUEST_IQAMA_BASE + i)
        }
        // لا نلغي منبّه التجربة (REQUEST_TEST): قد يكون المستخدم ينتظره الآن
        // بعد ضغط «جرّب الأذان»، وإلغاؤه هنا يجعل التجربة تنتهي صامتة.
    }

    private fun cancelRequest(context: Context, am: AlarmManager, requestCode: Int) {
        val pi = findPendingIntent(context, requestCode) ?: return
        am.cancel(pi)
        pi.cancel()
    }

    private fun setAlarm(
        context: Context,
        am: AlarmManager,
        requestCode: Int,
        atEpochMs: Long,
        kind: String,
        prayer: String,
    ) {
        val pi = broadcastIntent(
            context, requestCode, atEpochMs, kind, prayer,
            PendingIntent.FLAG_UPDATE_CURRENT,
        ) ?: return
        val showIntent = PendingIntent.getActivity(
            context,
            requestCode,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(atEpochMs, showIntent), pi)
        } catch (error: SecurityException) {
            // Android 14+: بدون إذن SCHEDULE_EXACT_ALARM يُمنع setAlarmClock.
            // نجدول منبّهاً تقريبياً بدل الفشل الصامت، وتنبّه خطوة الجاهزية
            // المستخدم لمنح الإذن (CONTRACTS §1: requestExactAlarm).
            Log.w(TAG, "لا إذن للمنبّه الدقيق — منبّه تقريبي بدلاً منه", error)
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atEpochMs, pi)
        }
    }

    private fun findPendingIntent(context: Context, requestCode: Int): PendingIntent? =
        broadcastIntent(context, requestCode, 0L, KIND_ADHAN, "", PendingIntent.FLAG_NO_CREATE)

    private fun broadcastIntent(
        context: Context,
        requestCode: Int,
        atEpochMs: Long,
        kind: String,
        prayer: String,
        flags: Int,
    ): PendingIntent? {
        val intent = Intent(context, AdhanReceiver::class.java).apply {
            putExtra("prayer", prayer)
            putExtra("kind", kind)
            putExtra("epochMs", atEpochMs)
        }
        return PendingIntent.getBroadcast(
            context, requestCode, intent, flags or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
