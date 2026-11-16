package app.yousuf.adhan

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import kotlinx.coroutines.runBlocking
import java.util.concurrent.TimeUnit

/**
 * شبكة أمان دورية (كل 6 ساعات): تتأكد أن أقرب أذان مجدول في المستقبل
 * وتعيد الجدولة إن لم يكن (SPEC §6: SafetyNetWorker).
 *
 * الفحص بوقت أقرب أذان المحفوظ، لا بوجود PendingIntent (يبقى بعد انطلاقه).
 * وإعادة الجدولة آمنة دائماً (تلغي وتضبط من جديد)، لذا نعيدها أيضاً إن
 * اقترب الموعد أكثر من ساعة بلا تحديث — لتغطية أجهزة تقتل المنبّهات
 * (شاومي/هواوي/أوبو).
 */
class SafetyNetWorker(
    context: Context,
    params: WorkerParameters,
) : Worker(context, params) {

    override fun doWork(): Result {
        return try {
            val config = runBlocking { AdhanPrefs.load(applicationContext) }
                ?: return Result.success()
            if (!AdhanScheduler.isScheduleHealthy(applicationContext)) {
                Log.w(TAG, "الجدولة غير سليمة — إعادة الجدولة")
            }
            AdhanScheduler.scheduleNext(applicationContext, config)
            Result.success()
        } catch (error: Exception) {
            Log.e(TAG, "فشلت شبكة الأمان", error)
            Result.retry()
        }
    }

    companion object {
        private const val TAG = "YousufAdhan"
        private const val UNIQUE_NAME = "adhan_safety_net"

        fun enqueue(context: Context) {
            val request = PeriodicWorkRequestBuilder<SafetyNetWorker>(6, TimeUnit.HOURS)
                .setBackoffCriteria(BackoffPolicy.LINEAR, 30, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                UNIQUE_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }
    }
}
