package app.yousuf

import android.app.Application
import android.util.Log
import androidx.work.Configuration
import androidx.work.WorkManager
import app.yousuf.adhan.AdhanNotifications
import app.yousuf.adhan.AdhanPrefs
import app.yousuf.adhan.AdhanScheduler
import app.yousuf.adhan.SafetyNetWorker
import kotlinx.coroutines.runBlocking

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

        // إعادة جدولة الأذان مع كل تشغيل للعملية (فتح التطبيق، منبّه، إقلاع):
        // أنظمة مثل MagicOS (أونر) وEMUI تحذف منبّهات التطبيق حين يُقتل من
        // «التطبيقات الأخيرة»، ولا ترجع إلا بإعادة الجدولة — وكانت لا تُعاد
        // إلا عند حفظ الإعدادات أو كل ٦ ساعات. خيط خلفي: قراءة DataStore
        // لا تجوز على الخيط الرئيسي.
        Thread {
            runCatching {
                val config = runBlocking { AdhanPrefs.load(this@YousufApplication) }
                if (config != null) AdhanScheduler.scheduleNext(this@YousufApplication, config)
            }.onFailure { Log.w(TAG, "تعذرت إعادة جدولة الأذان عند الإقلاع", it) }
        }.start()
    }

    private companion object {
        const val TAG = "Yousuf"
    }
}
