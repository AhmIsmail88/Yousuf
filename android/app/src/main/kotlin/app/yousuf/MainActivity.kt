package app.yousuf

import app.yousuf.adhan.AdhanChannel
import app.yousuf.downloads.DownloadKeepAliveService
import app.yousuf.speech.SpeechChannel
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * النشاط الرئيسي — يرث AudioServiceActivity لتعمل تلاوة القرآن في الخلفية
 * (إشعار وشاشة قفل) عبر just_audio_background.
 */
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AdhanChannel.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        DownloadKeepAliveService.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        // وضع الحفظ: الاستماع للتلاوة والتحقق منها (يحتاج Activity لإذن الميكروفون).
        SpeechChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4711) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED
            SpeechChannel.onPermissionResult(granted)
        }
    }

    override fun onDestroy() {
        SpeechChannel.disposeInstance()
        super.onDestroy()
    }
}
