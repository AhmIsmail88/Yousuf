package app.yousuf

import android.app.Application
import android.util.Log
import androidx.work.Configuration
import androidx.work.WorkManager
import app.yousuf.adhan.AdhanNotifications
import app.yousuf.adhan.SafetyNetWorker

/**
 * نقطة تهيئة التطبيق: قنوات الإشعار + شبكة أمان المنبّهات (SPEC §6، §9).
 *
 * التهيئة محمية: أي فشل في الإشعارات أو WorkManager لا يُسقط التطبيق عند
 * الإقلاع (كان R8 يكسر WorkManager ويسبب كراشاً فورياً في نسخة release).
 */
class YousufApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        runCatching { AdhanNotifications.createChannels(this) }
            .onFailure { Log.w(TAG, "تعذر إنشاء قنوات الإشعارات", it) }

        runCatching {
            // البادئ التلقائي مُعطَّل في المانيفست؛ نُهيّئ يدوياً هنا.
            if (!WorkManager.isInitialized()) {
                WorkManager.initialize(this, Configuration.Builder().build())
            }
            SafetyNetWorker.enqueue(this)
        }.onFailure { Log.w(TAG, "تعذر تهيئة شبكة أمان المنبّهات", it) }
    }

    private companion object {
        const val TAG = "Yousuf"
    }
}
