package app.yousuf.speech

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * محرّك التعرّف الصوتي لوضع الحفظ: يسمع تلاوة المستخدم للتحقق من صحة الآية.
 *
 * يُفضّل التعرّف **على الجهاز** (بلا شبكة) — SPEC §1 (أوفلاين أولاً)،
 * وإن لم يتوفر نموذج عربي محلي يرجع إلى محرك النظام ويُبلغ الواجهة بذلك.
 */
class SpeechChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private val methodChannel =
        MethodChannel(messenger, METHOD).apply { setMethodCallHandler(this@SpeechChannel) }
    private val eventChannel =
        EventChannel(messenger, EVENTS).apply { setStreamHandler(this@SpeechChannel) }

    private var sink: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var pendingLocale: String? = null
    private var listening = false
    private var usedOnDevice = false

    companion object {
        private const val TAG = "YousufSpeech"
        private const val METHOD = "app.yousuf/speech"
        private const val EVENTS = "app.yousuf/speech_events"
        private const val PERMISSION_REQUEST = 4711

        private var instance: SpeechChannel? = null

        fun register(activity: Activity, messenger: BinaryMessenger): SpeechChannel {
            val channel = SpeechChannel(activity, messenger)
            instance = channel
            return channel
        }

        /** تُنادى من MainActivity بعد ردّ إذن RECORD_AUDIO. */
        fun onPermissionResult(granted: Boolean) {
            instance?.handlePermission(granted)
        }

        fun disposeInstance() {
            instance?.dispose()
            instance = null
        }
    }

    // ---------------- القناة ----------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "availability" -> checkArabicSupport { map -> result.success(map) }
            "downloadArabic" -> result.success(downloadArabic())
            "start" -> {
                startListening(arabicLocale ?: call.argument<String>("locale") ?: "ar-SA")
                result.success(true)
            }
            "stop" -> {
                stopListening()
                result.success(true)
            }
            "cancel" -> {
                cancel()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        cancel()
    }

    // ---------------- الحالة ----------------

    /**
     * التعرّف **على الجهاز فقط** (SPEC §10: لا يُرسل صوت المستخدم لأي خادم).
     *
     * لا يكفي وجود محرّك محلي: يلزم نموذج **عربي** مثبّت عليه. على أندرويد 13+
     * نسأل المحرّك عن اللغات المثبّتة والقابلة للتنزيل (checkRecognitionSupport)
     * ونختار وسماً عربياً مثبّتاً (ar-SA، ar-EG…)؛ وإن كان قابلاً للتنزيل فقط
     * تعرض الواجهة زر «تنزيل العربية» (triggerModelDownload).
     *
     * reason: ok | old_android | no_engine | needs_download | no_arabic
     */
    private var arabicLocale: String? = null
    private var downloadableLocale: String? = null

    private fun recognizerIntent(locale: String) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
        }

    private fun result(available: Boolean, reason: String): Map<String, Any?> = mapOf(
        "available" to available,
        "onDevice" to available,
        "reason" to reason,
        "locale" to (arabicLocale ?: ""),
        "downloadable" to (downloadableLocale != null),
        "permission" to hasPermission(),
        "sdk" to Build.VERSION.SDK_INT,
    )

    private fun checkArabicSupport(reply: (Map<String, Any?>) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            reply(result(false, "old_android"))
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            // أندرويد 12: لا واجهة فحص؛ نحاول عند البدء ونعرض الخطأ إن فشل.
            arabicLocale = "ar-SA"
            reply(result(true, "ok"))
            return
        }
        val engineAvailable = try {
            SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)
        } catch (_: Throwable) {
            false
        }
        if (!engineAvailable) {
            reply(result(false, "no_engine"))
            return
        }
        main.post {
            val checker = try {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
            } catch (error: Throwable) {
                Log.w(TAG, "تعذر إنشاء محرّك الفحص", error)
                null
            }
            if (checker == null) {
                reply(result(false, "no_engine"))
                return@post
            }
            var replied = false
            fun finish(map: Map<String, Any?>) {
                if (replied) return
                replied = true
                runCatching { checker.destroy() }
                reply(map)
            }
            try {
                checker.checkRecognitionSupport(
                    recognizerIntent("ar-SA"),
                    activity.mainExecutor,
                    object : android.speech.RecognitionSupportCallback {
                        override fun onSupportResult(support: android.speech.RecognitionSupport) {
                            val installed = support.installedOnDeviceLanguages
                            val supported = support.supportedOnDeviceLanguages +
                                support.pendingOnDeviceLanguages
                            Log.i(TAG, "installed=" + installed + " downloadable=" + supported)
                            arabicLocale = installed.firstOrNull { it.startsWith("ar") }
                            downloadableLocale = supported.firstOrNull { it.startsWith("ar") }
                            finish(
                                when {
                                    arabicLocale != null -> result(true, "ok")
                                    downloadableLocale != null -> result(false, "needs_download")
                                    else -> result(false, "no_arabic")
                                },
                            )
                        }

                        override fun onError(error: Int) {
                            Log.w(TAG, "checkRecognitionSupport error " + error)
                            // تعذر الفحص — نحاول بالعربية الافتراضية ونعرض الخطأ عند البدء.
                            arabicLocale = "ar-SA"
                            finish(result(true, "ok"))
                        }
                    },
                )
            } catch (error: Throwable) {
                Log.w(TAG, "checkRecognitionSupport غير مدعوم", error)
                arabicLocale = "ar-SA"
                finish(result(true, "ok"))
            }
            // حارس: بعض المحرّكات لا تردّ أبداً.
            main.postDelayed({
                if (!replied) {
                    arabicLocale = "ar-SA"
                    finish(result(true, "ok"))
                }
            }, 4000)
        }
    }

    /** يطلب من المحرّك تنزيل النموذج العربي للعمل دون إنترنت (أندرويد 13+). */
    private fun downloadArabic(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        val locale = downloadableLocale ?: "ar-SA"
        return try {
            main.post {
                runCatching {
                    val engine = SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
                    engine.triggerModelDownload(recognizerIntent(locale))
                    main.postDelayed({ runCatching { engine.destroy() } }, 3000)
                }.onFailure { Log.w(TAG, "تعذر طلب تنزيل النموذج", it) }
            }
            true
        } catch (error: Throwable) {
            Log.w(TAG, "تعذر طلب تنزيل النموذج", error)
            false
        }
    }

    private fun hasPermission(): Boolean = ContextCompat.checkSelfPermission(
        activity,
        Manifest.permission.RECORD_AUDIO,
    ) == PackageManager.PERMISSION_GRANTED

    private fun startListening(locale: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            emitError("unavailable")
            return
        }
        if (!hasPermission()) {
            pendingLocale = locale
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                PERMISSION_REQUEST,
            )
            return
        }
        launch(locale)
    }

    private fun handlePermission(granted: Boolean) {
        val locale = pendingLocale
        pendingLocale = null
        if (granted && locale != null) launch(locale) else emitError("permission")
    }

    private fun launch(locale: String) {
        main.post {
            try {
                val engine = ensureRecognizer()
                if (engine == null) {
                    emitError("unavailable")
                    return@post
                }
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                    )
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                    // تعليم صريح: نريد التعرّف المحلي قدر الإمكان (SPEC §1).
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                    putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, activity.packageName)
                }
                listening = true
                engine.startListening(intent)
                send(mapOf("type" to "started", "onDevice" to usedOnDevice))
            } catch (error: Throwable) {
                Log.w(TAG, "تعذر بدء الاستماع", error)
                emitError("start_failed")
            }
        }
    }

    private fun ensureRecognizer(): SpeechRecognizer? {
        recognizer?.let { return it }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val engine = try {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
        } catch (error: Throwable) {
            // لا محرّك محلي — لا نرجع لمحرّك سحابي (خصوصية المستخدم).
            Log.w(TAG, "لا يوجد محرّك تعرّف على الجهاز", error)
            null
        } ?: return null
        usedOnDevice = true
        engine.setRecognitionListener(listener)
        recognizer = engine
        return engine
    }

    private fun stopListening() {
        listening = false
        try {
            recognizer?.stopListening()
        } catch (error: Throwable) {
            Log.w(TAG, "تعذر الإيقاف", error)
        }
    }

    private fun cancel() {
        listening = false
        try {
            recognizer?.cancel()
            recognizer?.destroy()
        } catch (_: Throwable) {
            // تجاهل — المحرك قد يكون محرَّراً.
        }
        recognizer = null
    }

    fun dispose() {
        cancel()
        sink = null
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // ---------------- الأحداث ----------------

    private fun send(payload: Map<String, Any?>) {
        main.post { sink?.success(payload) }
    }

    private fun emitError(code: String) {
        listening = false
        send(mapOf("type" to "error", "code" to code))
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            send(mapOf("type" to "ready"))
        }

        override fun onBeginningOfSpeech() {
            send(mapOf("type" to "speech_start"))
        }

        override fun onRmsChanged(rmsdB: Float) {
            send(mapOf("type" to "level", "value" to rmsdB.toDouble()))
        }

        override fun onBufferReceived(buffer: ByteArray?) = Unit

        override fun onEndOfSpeech() {
            send(mapOf("type" to "speech_end"))
        }

        override fun onError(error: Int) {
            listening = false
            Log.w(TAG, "recognition error " + error + " (" + errorName(error) + ")")
            send(mapOf("type" to "error", "code" to errorName(error)))
        }

        override fun onResults(results: Bundle?) {
            val text = bestResult(results).orEmpty()
            send(mapOf("type" to "final", "text" to text, "onDevice" to usedOnDevice))
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text = bestResult(partialResults).orEmpty()
            if (text.isNotEmpty()) {
                send(mapOf("type" to "partial", "text" to text, "onDevice" to usedOnDevice))
            }
        }

        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    private fun bestResult(bundle: Bundle?): String? = bundle
        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        ?.firstOrNull()
        ?.trim()

    private fun errorName(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "audio"
        SpeechRecognizer.ERROR_CLIENT -> "client"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission"
        SpeechRecognizer.ERROR_NETWORK -> "network"
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "network_timeout"
        SpeechRecognizer.ERROR_NO_MATCH -> "no_match"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
        SpeechRecognizer.ERROR_SERVER -> "server"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "timeout"
        12 -> "language" // ERROR_LANGUAGE_NOT_SUPPORTED
        13 -> "language_download" // ERROR_LANGUAGE_UNAVAILABLE
        11 -> "busy" // ERROR_SERVER_DISCONNECTED
        else -> "unknown"
    }
}
