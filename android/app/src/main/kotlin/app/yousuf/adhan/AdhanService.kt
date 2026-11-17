package app.yousuf.adhan

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import java.io.File

/**
 * خدمة الأذان: تشغيل في المقدمة (mediaPlayback) بصوت USAGE_ALARM مع إشعار
 * فيه زر إيقاف (SPEC §6، §9).
 *
 * كل ما تحتاجه يصلها في الـ Intent (الصلاة، النوع، الوضع، الصوت) — لا قراءة
 * إعدادات على الخيط الرئيسي. أول ما تفعله `startForeground` دائماً، ثم:
 * - تطلب أولوية الصوت (AudioFocus)، فإن رُفضت (مكالمة/منبّه آخر) تكتفي بإشعار.
 * - «تكبير فقط» يوقف الصوت بعد [TAKBIR_MS] بتلاشٍ هادئ.
 * - تفقد الصوت عند بدء مكالمة فتتوقف فوراً.
 * - إيقاف سهل: زر «إيقاف» في الإشعار، أو زر التشغيل (انطفاء الشاشة)، أو أحد
 *   زرّي الصوت — كما في تطبيقات المنبّه.
 *
 * الأصوات: `adhan/<soundId>.mp3` ثم `.ogg`، وإن لم يوجد `adhan/placeholder.ogg`.
 */
class AdhanService : Service() {

    companion object {
        const val ACTION_PLAY = "app.yousuf.adhan.PLAY"
        const val ACTION_STOP = "app.yousuf.adhan.STOP"
        private const val TAG = "YousufAdhan"
        private const val MAX_PLAYBACK_MS = 5 * 60 * 1000L
        private const val TAKBIR_MS = 20_000L
        private const val FADE_MS = 2_000L

        /** هل الأذان يُشغَّل الآن؟ */
        @Volatile
        var isPlaying: Boolean = false
            private set

        private val listeners = mutableSetOf<(Boolean) -> Unit>()
        private val main = Handler(Looper.getMainLooper())

        /** يسجّل مستمعاً لتغيّر حالة التشغيل (لقناة الأحداث إلى Dart). */
        fun addListener(listener: (Boolean) -> Unit) {
            main.post { listeners += listener }
        }

        fun removeListener(listener: (Boolean) -> Unit) {
            main.post { listeners -= listener }
        }

        private fun setPlaying(value: Boolean) {
            if (isPlaying == value) return
            isPlaying = value
            main.post { listeners.toList().forEach { it(value) } }
        }

        /** مجلد الأصوات المحمَّلة من التطبيق (`<files>/adhan/<id>.mp3`). */
        fun downloadedDir(context: Context): File = File(context.filesDir, "adhan")

        /** الأصوات المتوفرة فعلاً: داخل الحزمة + ما حمّله المستخدم (بدون البديل المؤقت). */
        fun availableSounds(context: Context): List<String> {
            val bundled = runCatching { context.assets.list("adhan")?.toList() }
                .getOrNull().orEmpty()
            val downloaded = downloadedDir(context).listFiles()
                ?.filter { it.isFile && it.length() > MIN_DOWNLOADED_BYTES }
                ?.map { it.name }
                .orEmpty()
            return (bundled + downloaded)
                .filter { it.endsWith(".mp3") || it.endsWith(".ogg") }
                .map { it.substringBeforeLast('.') }
                .filter { it != "placeholder" }
                .distinct()
        }

        /** أصغر حجم مقبول لملف محمَّل — ما دونه تحميل ناقص. */
        private const val MIN_DOWNLOADED_BYTES = 100_000L

        /** القنوات (توافق قديم: تُستدعى من Application). */
        fun createChannels(context: Context) = AdhanNotifications.createChannels(context)
    }

    private var player: MediaPlayer? = null
    private val handler = Handler(Looper.getMainLooper())
    private var focusRequest: AudioFocusRequest? = null
    private var stopKeysRegistered = false
    private var playStartedAt = 0L

    /** زر التشغيل أو زرّا الصوت يوقفان الأذان (بعد ثانية من بدئه). */
    private val stopKeys = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (player == null) return
            if (System.currentTimeMillis() - playStartedAt < 1_000L) return
            Log.i(TAG, "إيقاف الأذان بزر: ${intent.action}")
            stopPlayback()
        }
    }

    private fun registerStopKeys() {
        if (stopKeysRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            // يُبثّ عند ضغط زرّي الصوت (غير موثّق رسمياً لكنه مستقر منذ سنوات).
            addAction("android.media.VOLUME_CHANGED_ACTION")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stopKeys, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(stopKeys, filter)
        }
        stopKeysRegistered = true
    }

    private fun unregisterStopKeys() {
        if (!stopKeysRegistered) return
        runCatching { unregisterReceiver(stopKeys) }
        stopKeysRegistered = false
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS ||
            change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT
        ) {
            // مكالمة واردة أو تطبيق آخر أخذ الصوت — نتوقف ولا نعود.
            Log.i(TAG, "فُقدت أولوية الصوت ($change) — إيقاف الأذان")
            stopPlayback()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prayer = intent?.getStringExtra("prayer") ?: "fajr"
        val kind = intent?.getStringExtra("kind") ?: AdhanScheduler.KIND_ADHAN

        // الإيقاف يصل دائماً عبر startService (زر الإشعار أو التطبيق)، فلا
        // يحتاج startForeground.
        if (intent?.action == ACTION_STOP) {
            stopPlayback()
            return START_NOT_STICKY
        }

        // ثم دائماً أولاً: خدمة بُدئت بـ startForegroundService ولم تستدعِ
        // startForeground تُسقط التطبيق، حتى لو كانت ستتوقف فوراً.
        goForeground(prayer, kind)

        val mode = intent?.getStringExtra("mode") ?: "full"
        val sound = intent?.getStringExtra("sound") ?: "makkah"

        stopPlayer()
        if (!requestFocus()) {
            AdhanNotifications.notifyAdhanSilently(this, prayer, "أثناء مكالمة — بلا صوت")
            stopPlayback()
            return START_NOT_STICKY
        }
        if (!tryPlay(sound)) {
            AdhanNotifications.notifyAdhanSilently(this, prayer)
            stopPlayback()
            return START_NOT_STICKY
        }
        playStartedAt = System.currentTimeMillis()
        registerStopKeys()
        scheduleStop(if (mode == "takbir") TAKBIR_MS else MAX_PLAYBACK_MS)
        return START_NOT_STICKY
    }

    private fun goForeground(prayer: String, kind: String) {
        val notification = AdhanNotifications.serviceNotification(this, prayer, kind)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                AdhanNotifications.ID_SERVICE,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(AdhanNotifications.ID_SERVICE, notification)
        }
    }

    private val attributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    private fun requestFocus(): Boolean {
        val audio = getSystemService(AudioManager::class.java) ?: return true
        if (AdhanNotifications.isInCall(this)) return false
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener(focusListener, handler)
            .build()
        focusRequest = request
        return audio.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocus() {
        val request = focusRequest ?: return
        getSystemService(AudioManager::class.java)?.abandonAudioFocusRequest(request)
        focusRequest = null
    }

    /** يحاول تشغيل صوت المؤذن (المحمَّل أولاً)، ثم البديل العام. */
    private fun tryPlay(soundId: String): Boolean {
        val downloaded = File(downloadedDir(this), "$soundId.mp3")
        if (downloaded.isFile && downloaded.length() > MIN_DOWNLOADED_BYTES &&
            playFile(downloaded)
        ) {
            return true
        }
        val candidates = listOf(
            "adhan/$soundId.mp3",
            "adhan/$soundId.ogg",
            "adhan/placeholder.ogg",
        )
        for (path in candidates) {
            if (playAsset(path)) return true
        }
        Log.w(TAG, "لا يوجد ملف أذان صالح في assets — إشعار فقط")
        return false
    }

    private fun playFile(file: File): Boolean {
        val mp = MediaPlayer()
        return try {
            mp.setAudioAttributes(attributes)
            mp.setDataSource(file.path)
            mp.setVolume(1f, 1f)
            mp.setOnCompletionListener { stopPlayback() }
            mp.setOnErrorListener { _, what, extra ->
                Log.w(TAG, "خطأ MediaPlayer what=$what extra=$extra")
                stopPlayback()
                true
            }
            mp.prepare()
            mp.start()
            player = mp
            setPlaying(true)
            Log.i(TAG, "تشغيل الأذان المحمَّل ${file.name} (${mp.duration}ms)")
            true
        } catch (error: Exception) {
            Log.w(TAG, "تعذر تشغيل ${file.name}: ${error.message}")
            runCatching { mp.release() }
            false
        }
    }

    private fun playAsset(assetPath: String): Boolean {
        val mp = MediaPlayer()
        return try {
            mp.setAudioAttributes(attributes)
            try {
                assets.openFd(assetPath).use { afd ->
                    mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                }
            } catch (_: Exception) {
                // الأصل مضغوط في APK — ننسخه إلى الكاش مرة واحدة.
                val cached = File(cacheDir, assetPath.replace('/', '_'))
                if (!cached.exists() || cached.length() == 0L) {
                    assets.open(assetPath).use { input ->
                        cached.outputStream().use { output -> input.copyTo(output) }
                    }
                }
                mp.setDataSource(cached.path)
            }
            mp.setVolume(1f, 1f)
            mp.setOnCompletionListener { stopPlayback() }
            mp.setOnErrorListener { _, what, extra ->
                Log.w(TAG, "خطأ MediaPlayer what=$what extra=$extra")
                stopPlayback()
                true
            }
            mp.prepare()
            mp.start()
            player = mp
            setPlaying(true)
            Log.i(TAG, "تشغيل الأذان من $assetPath (${mp.duration}ms)")
            true
        } catch (error: Exception) {
            Log.w(TAG, "تعذر تشغيل $assetPath: ${error.message}")
            runCatching { mp.release() }
            false
        }
    }

    /** يوقف بعد [delayMs] مع تلاشٍ في آخر ثانيتين. */
    private fun scheduleStop(delayMs: Long) {
        handler.removeCallbacksAndMessages(null)
        val fadeStart = (delayMs - FADE_MS).coerceAtLeast(0L)
        handler.postDelayed({ fadeOut(steps = 10) }, fadeStart)
    }

    private fun fadeOut(steps: Int) {
        val mp = player ?: return stopPlayback()
        if (steps <= 0) {
            stopPlayback()
            return
        }
        val volume = steps / 10f
        runCatching { mp.setVolume(volume, volume) }
        handler.postDelayed({ fadeOut(steps - 1) }, FADE_MS / 10)
    }

    private fun stopPlayer() {
        handler.removeCallbacksAndMessages(null)
        player?.let { mp ->
            runCatching { mp.stop() }
            runCatching { mp.release() }
        }
        player = null
    }

    private fun stopPlayback() {
        unregisterStopKeys()
        stopPlayer()
        abandonFocus()
        setPlaying(false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        unregisterStopKeys()
        stopPlayer()
        abandonFocus()
        setPlaying(false)
        super.onDestroy()
    }
}
