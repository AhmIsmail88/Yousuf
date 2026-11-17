package app.yousuf.adhan

import android.app.AlarmManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.runBlocking

/**
 * الجسر `yousuf/adhan` — مطابق لعقد CONTRACTS §1 (SPEC §6)، مع قناة أحداث
 * `yousuf/adhan_events` تبثّ حالة التشغيل (true/false) لحظة تغيّرها بدل
 * الاستعلام الدوري.
 *
 * أي خطأ يُسجَّل في logcat (الوسم YousufAdhan) ويُعاد لـ Dart كـ PlatformException.
 */
class AdhanChannel private constructor(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "yousuf/adhan"
        const val EVENTS_NAME = "yousuf/adhan_events"
        private const val TAG = "YousufAdhan"

        fun register(context: Context, messenger: BinaryMessenger) {
            val app = context.applicationContext
            MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler(AdhanChannel(app))
            EventChannel(messenger, EVENTS_NAME).setStreamHandler(PlayingStreamHandler())
        }

        /** شاشات «التشغيل التلقائي» لدى الشركات التي تقتل المنبّهات. */
        private val AUTOSTART_INTENTS = listOf(
            ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
            // أونر (MagicOS) انفصلت عن هواوي بحزمة مستقلة: «تشغيل التطبيقات».
            ComponentName("com.hihonor.systemmanager", "com.hihonor.systemmanager.appcontrol.activity.StartupAppControlActivity"),
            ComponentName("com.hihonor.systemmanager", "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
            ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
            ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
            ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
            ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"),
            ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"),
        )
    }

    /** يبثّ حالة تشغيل الأذان: القيمة الحالية فور الاشتراك ثم كل تغيّر. */
    private class PlayingStreamHandler : EventChannel.StreamHandler {
        private var listener: ((Boolean) -> Unit)? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            events.success(AdhanService.isPlaying)
            val l: (Boolean) -> Unit = { playing -> events.success(playing) }
            listener = l
            AdhanService.addListener(l)
        }

        override fun onCancel(arguments: Any?) {
            listener?.let { AdhanService.removeListener(it) }
            listener = null
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "applyConfig" -> inBackground(call.method, result) {
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                val config = AdhanConfig.fromMap(args)
                    ?: throw IllegalArgumentException("إعدادات غير صالحة: $args")
                runBlocking { AdhanPrefs.save(context, config) }
                val scheduled = AdhanScheduler.scheduleNext(context, config)
                mapOf("scheduled" to scheduled.scheduled, "next" to scheduled.nextEpochMs)
            }

            "getStatus" -> inBackground(call.method, result) { statusMap() }

            "requestExactAlarm" -> result.success(openExactAlarmSettings())

            "openBatterySettings" -> result.success(openBatterySettings())
            "openSoundSettings" -> result.success(openSoundSettings())

            "openAutostartSettings" -> result.success(openAutostartSettings())

            // الانحراف المغناطيسي (WMM المدمج في أندرويد) لتصحيح البوصلة إلى الشمال
            // الجغرافي في شاشة القبلة — بالدرجات، موجب = شرقاً.
            "magneticDeclination" -> {
                val lat = call.argument<Double>("latitude") ?: 0.0
                val lng = call.argument<Double>("longitude") ?: 0.0
                val field = android.hardware.GeomagneticField(
                    lat.toFloat(), lng.toFloat(), 0f, System.currentTimeMillis(),
                )
                result.success(field.declination.toDouble())
            }

            "previewSound" -> result.success(
                previewSound(call.argument<String>("soundId") ?: "makkah"),
            )

            "stopSound" -> {
                try {
                    if (AdhanService.isPlaying) {
                        context.startService(
                            Intent(context, AdhanService::class.java)
                                .setAction(AdhanService.ACTION_STOP),
                        )
                    }
                    result.success(true)
                } catch (error: Exception) {
                    Log.e(TAG, "تعذر إيقاف الأذان", error)
                    result.error("engine_error", error.message, null)
                }
            }

            "testAdhanIn" -> inBackground(call.method, result) {
                val seconds = call.argument<Int>("seconds") ?: 30
                val scheduled = AdhanScheduler.scheduleTest(context, seconds)
                mapOf("scheduled" to scheduled.scheduled, "next" to scheduled.nextEpochMs)
            }

            else -> result.notImplemented()
        }
    }

    /** ينفّذ العملية في خيط خلفي (DataStore) ويرد على الخيط الرئيسي. */
    private fun inBackground(method: String, result: MethodChannel.Result, block: () -> Any?) {
        Thread {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (error: Exception) {
                Log.e(TAG, "فشل $method", error)
                mainHandler.post {
                    result.error("engine_error", "$method: ${error.message}", null)
                }
            }
        }.start()
    }

    private fun statusMap(): Map<String, Any> {
        val notifications = NotificationManagerCompat.from(context)
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val powerManager = context.getSystemService(PowerManager::class.java)
        val config = runBlocking { AdhanPrefs.load(context) }

        val nextAlarms = if (config == null) {
            emptyList<Map<String, Any>>()
        } else {
            PrayerCalc.upcomingAdhans(config, 3, prayers = config.enabledPrayers()).map { item ->
                mapOf(
                    "prayer" to item.prayer.name.lowercase(),
                    "epochMs" to item.instant.toEpochMilliseconds(),
                    "kind" to "adhan",
                )
            }
        }

        return mapOf(
            "exactAlarmAllowed" to (
                Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                    alarmManager?.canScheduleExactAlarms() == true
                ),
            "notificationsAllowed" to notifications.areNotificationsEnabled(),
            "batteryOptimized" to !(
                powerManager?.isIgnoringBatteryOptimizations(context.packageName) ?: false
                ),
            "nextAlarms" to nextAlarms,
            "scheduledNextEpochMs" to AdhanScheduler.nextAdhanEpochMs(context),
            "playing" to AdhanService.isPlaying,
            "availableSounds" to AdhanService.availableSounds(context),
            "manufacturer" to Build.MANUFACTURER.lowercase(),
            "autostartSettingsAvailable" to (findAutostartIntent() != null),
            // الأذان يُشغَّل على صوت المنبّه — نُنبّه إن كان منخفضاً.
            "alarmVolumePercent" to alarmVolumePercent(),
        )
    }

    private fun alarmVolumePercent(): Int {
        val audio = context.getSystemService(android.media.AudioManager::class.java) ?: return 100
        val max = audio.getStreamMaxVolume(android.media.AudioManager.STREAM_ALARM)
        if (max <= 0) return 100
        return audio.getStreamVolume(android.media.AudioManager.STREAM_ALARM) * 100 / max
    }

    private fun openSoundSettings(): Boolean = try {
        context.startActivity(
            Intent(Settings.ACTION_SOUND_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (error: Exception) {
        Log.w(TAG, "تعذر فتح إعدادات الصوت", error)
        false
    }

    private fun openExactAlarmSettings(): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:${context.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
        true
    } catch (error: Exception) {
        Log.w(TAG, "تعذر فتح إعدادات المنبّه الدقيق", error)
        false
    }

    /**
     * يطلب استثناء يوسف من تحسين البطارية بنافذة النظام المباشرة («السماح
     * بالعمل في الخلفية دائماً؟»). على أونر/هواوي قائمة «تحسين البطارية»
     * العامة ومفاتيح «تشغيل التطبيقات» لا تضيف التطبيق دائماً لقائمة
     * الاستثناء التي يقرؤها النظام (deviceidle) — النافذة المباشرة تضيفه.
     * إن لم تتوفر النافذة: القائمة العامة، ثم تفاصيل التطبيق.
     */
    private fun openBatterySettings(): Boolean {
        val direct = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val list = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        for (intent in listOf(direct, list)) {
            try {
                context.startActivity(intent)
                return true
            } catch (error: Exception) {
                Log.w(TAG, "تعذر فتح إعدادات البطارية: ${intent.action}", error)
            }
        }
        return openAppDetails()
    }

    private fun findAutostartIntent(): Intent? {
        val pm = context.packageManager
        return AUTOSTART_INTENTS
            .map { Intent().setComponent(it).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
            .firstOrNull { intent -> intent.resolveActivity(pm) != null }
    }

    /** يفتح شاشة «التشغيل التلقائي» للشركة المصنّعة، وإلا تفاصيل التطبيق. */
    private fun openAutostartSettings(): Boolean = try {
        val intent = findAutostartIntent()
        if (intent != null) {
            context.startActivity(intent)
            true
        } else {
            openAppDetails()
        }
    } catch (error: Exception) {
        Log.w(TAG, "تعذر فتح إعدادات التشغيل التلقائي", error)
        openAppDetails()
    }

    private fun openAppDetails(): Boolean = try {
        context.startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (_: Exception) {
        false
    }

    /** يشغّل الصوت المختار نفسه (أو البديل المؤقت إن لم يتوفر). */
    private fun previewSound(soundId: String): Boolean = try {
        context.startForegroundService(
            Intent(context, AdhanService::class.java).apply {
                action = AdhanService.ACTION_PLAY
                putExtra("prayer", "fajr")
                putExtra("kind", AdhanScheduler.KIND_TEST)
                putExtra("mode", "takbir")
                putExtra("sound", soundId)
            },
        )
        true
    } catch (error: Exception) {
        Log.w(TAG, "تعذر معاينة الصوت $soundId", error)
        false
    }
}
