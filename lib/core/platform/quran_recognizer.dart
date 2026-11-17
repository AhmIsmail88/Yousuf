import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'speech_channel.dart';

/// التعرّف على التلاوة **على الجهاز** بنموذج قرآني (وضع التسميع).
///
/// النموذج: tarteel-ai/whisper-base-ar-quran (Apache-2.0) — Whisper base مدرّب
/// على تلاوة القرآن، محوَّل إلى ggml بأداة `tools/asr/convert_to_ggml.py`،
/// ويعمل عبر whisper.cpp دون إنترنت. صوت المستخدم لا يغادر الهاتف (SPEC §10).
///
/// يُنزَّل النموذج مرة واحدة عند أول استخدام (≈٨٢ م.ب) ويُتحقق من بصمته.
///
/// الواجهة مطابقة لـ [SpeechChannel] (availability/start/stop/events) حتى
/// تستخدمه شاشتا المصحف والأطفال دون تغيير منطقهما.
class QuranRecognizer {
  QuranRecognizer();

  /// اسم ملف النموذج على الجهاز: نسخة q8_0 المضغوطة (٨٢ م.ب) — النص نفسه
  /// حرفياً على تلاوات الاختبار، وأسرع بنحو ٤٠٪ على الهاتف من نسخة f16.
  static const String modelFileName = 'ggml-tarteel-base-quran-q8.bin';

  /// نسخة f16 القديمة (١٤٨ م.ب) — تُحذف بعد تنزيل النسخة الجديدة.
  static const String legacyModelFileName = 'ggml-tarteel-base-quran.bin';

  /// رابط تنزيل النموذج — مستودع المشروع على Hugging Face (رخصة Apache-2.0).
  /// يمكن تغييره وقت البناء: `--dart-define=QURAN_ASR_MODEL_URL=...`.
  static const String modelUrl = String.fromEnvironment(
    'QURAN_ASR_MODEL_URL',
    defaultValue:
        'https://huggingface.co/Ahm20/yousuf-quran-asr/resolve/main/'
        'ggml-tarteel-base-quran-q8.bin',
  );

  /// بصمة SHA-256 للملف المعتمد — يُرفض أي ملف منزَّل لا يطابقها.
  static const String modelSha256 = String.fromEnvironment(
    'QURAN_ASR_MODEL_SHA256',
    defaultValue:
        '72194195f7d280adebec57acf2c6e01e209484322ec1cec21c275a3c0b1e3d77',
  );

  /// الحجم التقريبي للعرض.
  static const int approxMegabytes = 82;

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  AudioRecorder? _recorder;
  String? _audioPath;
  StreamSubscription<Amplitude>? _amplitudeSub;
  final StreamController<SpeechEvent> _events =
      StreamController<SpeechEvent>.broadcast();

  // ---- الاستماع المتواصل (التسميع كلمة بكلمة) ----
  StreamSubscription<Uint8List>? _pcmSub;
  Timer? _liveTimer;
  final List<Uint8List> _pcm = [];
  int _pcmBytes = 0;
  int _transcribedUpTo = 0;
  bool _busy = false;
  bool _live = false;
  bool _spoke = false;
  DateTime? _quietSince;
  DateTime? _liveBegan;

  /// صوت ١٦ كيلوهرتز أحادي ١٦ بت: ٣٢٠٠٠ بايت في الثانية.
  static const int _bytesPerSecond = 32000;

  /// طول المقطع الذي يُفرَّغ كل مرة في المصحف (آخر ثوانٍ من التلاوة).
  static const Duration liveWindow = Duration(seconds: 6);

  // إعدادات الجلسة الحية الحالية (تُضبط في [startLive]).
  Duration _window = liveWindow;
  Duration _silenceStop = const Duration(seconds: 8);
  Duration _step = const Duration(milliseconds: 800);
  Duration _noSpeechStop = const Duration(seconds: 15);

  /// مستوى ضجيج الغرفة (dBFS) — يتكيّف: الكلام ما يعلوه بوضوح.
  double? _noiseFloor;
  int _calibrationChunks = 0;

  /// هل حُمِّل النموذج في الذاكرة (أول تفريغ يحمّله ~١ ث)؟
  static bool _warm = false;
  String? _prompt;

  /// نص يسبق التفريغ (الكلمات المتلوّة قبل المقطع) — يساعد النموذج على
  /// متابعة التلاوة. **لا** يوضع فيه ما لم يُتلَ بعد حتى لا يُكمله النموذج.
  set prompt(String? value) => _prompt = value;

  /// أحداث التعرّف (نصوص جزئية ونهائية وأخطاء).
  Stream<SpeechEvent> get events => _events.stream;

  static Future<File> modelFile() async {
    final dir = await getApplicationSupportDirectory();
    final asr = Directory('${dir.path}/asr');
    if (!asr.existsSync()) asr.createSync(recursive: true);
    return File('${asr.path}/$modelFileName');
  }

  /// هل النموذج موجود على الجهاز؟
  static Future<bool> isModelReady() async {
    if (!isSupported) return false;
    final file = await modelFile();
    return file.existsSync() && file.lengthSync() > 40 * 1024 * 1024;
  }

  Future<SpeechAvailability> availability() async {
    if (!isSupported) return SpeechAvailability.none;
    final ready = await isModelReady();
    final mic = await AudioRecorder().hasPermission(request: false);
    return SpeechAvailability(
      available: ready,
      onDevice: true,
      permission: mic,
      reason: ready ? 'ok' : 'needs_model',
      downloadable: !ready && modelUrl.isNotEmpty,
      locale: 'ar',
    );
  }

  /// ينزّل النموذج مع التقدّم، ويتحقق من البصمة إن عُرفت.
  static Future<bool> downloadModel({
    void Function(double progress)? onProgress,
  }) async {
    if (modelUrl.isEmpty) return false;
    final file = await modelFile();
    final temp = File('${file.path}.part');
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(modelUrl)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final expected = response.contentLength;
      final total = expected ?? approxMegabytes * 1024 * 1024;
      final sink = temp.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 60),
        )) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      if (expected != null && received != expected) {
        throw const HttpException('تنزيل ناقص');
      }
      if (modelSha256.isNotEmpty) {
        // بصمة بالتدفق: لا نحمّل عشرات الميغابايت في الذاكرة دفعة واحدة.
        final digest = (await sha256.bind(temp.openRead()).first).toString();
        if (digest != modelSha256) throw StateError('بصمة النموذج غير مطابقة');
      }
      await temp.rename(file.path);
      // النسخة القديمة الأكبر لم تعد مستعملة.
      final legacy = File('${file.parent.path}/$legacyModelFileName');
      if (legacy.existsSync()) legacy.deleteSync();
      return true;
    } catch (error) {
      debugPrint('[YousufAsr] فشل تنزيل النموذج: $error');
      if (temp.existsSync()) temp.deleteSync();
      return false;
    } finally {
      client.close();
    }
  }

  /// يبدأ الاستماع: يسجّل التلاوة في ملف WAV (16kHz أحادي)، ويتوقف تلقائياً
  /// بعد سكوت قصير يلي الكلام، ثم يفرّغها النموذج دفعة واحدة على الجهاز.
  ///
  /// (الجلسة الحية في whisper_ggml تعلّق على بعض الأجهزة عند البدء، فاعتمدنا
  /// التفريغ لمرة واحدة — وهو المسار المستقر في المكتبة.)
  Future<bool> start() async {
    if (!isSupported) return false;
    await cancel();
    final recorder = AudioRecorder();
    // يطلب الإذن عند الحاجة (حزمة record).
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      _events.add(
        const SpeechEvent(type: SpeechEventKind.error, code: 'permission'),
      );
      return false;
    }
    final model = await modelFile();
    if (!model.existsSync()) {
      await recorder.dispose();
      _events.add(
        const SpeechEvent(type: SpeechEventKind.error, code: 'unavailable'),
      );
      return false;
    }
    try {
      final dir = await getTemporaryDirectory();
      // اسم فريد لكل تسجيل: تفريغ التسجيل السابق قد ينتهي ويحذف ملفه بينما
      // التسجيل الجديد ما زال جارياً (أوقف ثم اقرأ بسرعة).
      final path =
          '${dir.path}/recitation_${DateTime.now().microsecondsSinceEpoch}.wav';
      _recorder = recorder;
      _audioPath = path;
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          noiseSuppress: true,
        ),
        path: path,
      );
      debugPrint('[YousufAsr] بدأ التسجيل');
      _events.add(
        const SpeechEvent(type: SpeechEventKind.started, onDevice: true),
      );
      _watchSilence(recorder);
      return true;
    } catch (error) {
      debugPrint('[YousufAsr] تعذر بدء التسجيل: $error');
      await cancel();
      _events.add(
        const SpeechEvent(type: SpeechEventKind.error, code: 'audio'),
      );
      return false;
    }
  }

  /// استماع متواصل: يُفرَّغ آخر [window] من التلاوة كلما تجمّع [step] جديد،
  /// ويُرسل نصه حدثاً جزئياً، فيُكشف ما تُلي أولاً بأول دون انتظار النهاية.
  /// يتوقف بالضغط على «أوقف»، أو بعد سكوت [silenceStop] (فيُرسل النص
  /// النهائي)، أو بعد ٥ دقائق.
  ///
  /// المصحف: نافذة قصيرة (٦ ث) تتابع التلاوة. الأطفال: نافذة الآية كلها
  /// (حتى ٢٨ ث) وسكوت قصير، فتظهر الآية فور اكتمالها أو يُقال «خطأ» سريعاً.
  Future<bool> startLive({
    Duration window = liveWindow,
    Duration silenceStop = const Duration(seconds: 8),
    Duration step = const Duration(milliseconds: 800),
    Duration noSpeechStop = const Duration(seconds: 15),
    String? prompt,
  }) async {
    if (!isSupported) return false;
    await cancel();
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      _events.add(
        const SpeechEvent(type: SpeechEventKind.error, code: 'permission'),
      );
      return false;
    }
    final model = await modelFile();
    if (!model.existsSync()) {
      await recorder.dispose();
      _events.add(
        const SpeechEvent(type: SpeechEventKind.error, code: 'unavailable'),
      );
      return false;
    }
    try {
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          noiseSuppress: true,
          // صوت إشعار أو تشغيل آخر لا يوقف التسميع.
          audioInterruption: AudioInterruptionMode.none,
        ),
      );
      _recorder = recorder;
      _live = true;
      _window = window;
      _silenceStop = silenceStop;
      _step = step;
      _noSpeechStop = noSpeechStop;
      _prompt = prompt;
      _pcm.clear();
      _pcmBytes = 0;
      _transcribedUpTo = 0;
      _spoke = false;
      _quietSince = null;
      _noiseFloor = null;
      _calibrationChunks = 0;
      _liveBegan = DateTime.now();
      _pcmSub = stream.listen(_onPcm);
      _liveTimer = Timer.periodic(
        const Duration(milliseconds: 400),
        (_) => unawaited(_liveTick()),
      );
      debugPrint('[YousufAsr] بدأ الاستماع المتواصل');
      if (!_warm) unawaited(_warmUp());
      unawaited(_sweepStaleAudio());
      _events.add(
        const SpeechEvent(type: SpeechEventKind.started, onDevice: true),
      );
      return true;
    } catch (error) {
      debugPrint('[YousufAsr] تعذر بدء الاستماع: $error');
      await cancel();
      _events.add(
        const SpeechEvent(type: SpeechEventKind.error, code: 'audio'),
      );
      return false;
    }
  }

  void _onPcm(Uint8List chunk) {
    _pcm.add(chunk);
    _pcmBytes += chunk.length;
    // مستوى الصوت (dBFS) من العينات نفسها.
    final data = ByteData.sublistView(chunk);
    var sum = 0.0;
    final samples = chunk.length ~/ 2;
    for (var i = 0; i < samples; i++) {
      final v = data.getInt16(i * 2, Endian.little);
      sum += v * v;
    }
    final rms = samples == 0 ? 0.0 : math.sqrt(sum / samples);
    final db = rms <= 0 ? -100.0 : 20 * math.log(rms / 32768) / math.ln10;
    // أرضية الضجيج: تنزل فوراً مع الهدوء وتصعد ببطء — فضجيج الغرفة الثابت
    // (مروحة، مكيّف) لا يُعدّ كلاماً، والنموذج لا يُفرِّغ الضجيج فيتخيّل كلاماً.
    // أول نصف ثانية تقريباً تقيس ضجيج الغرفة (قبل أن يبدأ الطفل الكلام).
    final floor = _noiseFloor;
    if (floor == null || _calibrationChunks < 4) {
      _calibrationChunks++;
      _noiseFloor = floor == null ? db : math.min(floor, db);
      return;
    }
    final speaking = db > -50 && db > floor + 12;
    if (db < floor) {
      _noiseFloor = db;
    } else if (!speaking) {
      // يصعد مع الضجيج فقط، لا مع الكلام.
      _noiseFloor = floor + 0.05 * (db - floor);
    }
    if (speaking) {
      if (!_spoke) {
        _spoke = true;
        _events.add(
          const SpeechEvent(type: SpeechEventKind.speechStart, onDevice: true),
        );
      }
      _quietSince = null;
    } else if (_spoke) {
      _quietSince ??= DateTime.now();
    }
  }

  Future<void> _liveTick() async {
    if (!_live) return;
    final now = DateTime.now();
    final quiet =
        _quietSince != null && now.difference(_quietSince!) > _silenceStop;
    final tooLong =
        _liveBegan != null &&
        now.difference(_liveBegan!) > const Duration(minutes: 5);
    // لم يبدأ الكلام أصلاً: نتوقف ونُرسل نتيجة فارغة («لم أسمعك»).
    final silentStart =
        !_spoke &&
        _liveBegan != null &&
        now.difference(_liveBegan!) > _noSpeechStop;
    if (quiet || tooLong || silentStart) {
      await stop();
      return;
    }
    // نفرّغ حين يتجمّع [_step] جديد على الأقل بعد بدء الكلام.
    if (_busy || !_spoke) return;
    final stepBytes = _bytesPerSecond * _step.inMilliseconds ~/ 1000;
    if (_pcmBytes - _transcribedUpTo < stepBytes) return;
    await _transcribeTail(SpeechEventKind.partial);
  }

  /// يحمّل النموذج في الذاكرة بتفريغ ثانية صامتة، أثناء ما يستعد المستخدم
  /// للكلام — فلا يتأخر أول تفريغ حقيقي بزمن التحميل.
  /// يحذف مقاطع مؤقتة بقيت من جلسات قُطعت (إغلاق التطبيق أثناء التفريغ).
  /// الأقدم من دقيقتين فقط، حتى لا يُمسّ ملف جلسة جارية.
  Future<void> _sweepStaleAudio() async {
    try {
      final dir = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final ours =
            name.startsWith('live_') ||
            name.startsWith('warm_') ||
            name.startsWith('recitation_');
        if (!ours || !name.contains('.wav')) continue;
        if (entity.lastModifiedSync().isBefore(cutoff)) entity.deleteSync();
      }
    } catch (_) {}
  }

  Future<void> _warmUp() async {
    if (_busy || _warm) return;
    _busy = true;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/warm_${DateTime.now().microsecondsSinceEpoch}.wav';
    try {
      await File(path)
          .writeAsBytes(_wav(Uint8List(_bytesPerSecond)), flush: true);
      final model = await modelFile();
      final watch = Stopwatch()..start();
      await const Whisper(model: WhisperModel.base).transcribe(
        modelPath: model.path,
        transcribeRequest: TranscribeRequest(
          audio: path,
          language: 'ar',
          isNoTimestamps: true,
          noContext: true,
          suppressNonSpeechTokens: true,
          keepModelLoaded: true,
          speedUp: true,
          noFallback: true,
          threads: Platform.numberOfProcessors.clamp(2, 6),
        ),
      );
      _warm = true;
      debugPrint('[YousufAsr] حُمِّل النموذج (${watch.elapsedMilliseconds}ms)');
    } catch (error) {
      debugPrint('[YousufAsr] تعذّر تحميل النموذج مسبقاً: $error');
    } finally {
      try {
        File(path).deleteSync();
      } catch (_) {}
      _busy = false;
    }
  }

  /// يفرّغ آخر [liveWindow] من الصوت المسجَّل ويرسل النص بنوع [kind].
  Future<void> _transcribeTail(String kind) async {
    if (_busy) return;
    _busy = true;
    final end = _pcmBytes;
    final windowBytes = _bytesPerSecond * _window.inMilliseconds ~/ 1000;
    final pcm = _tail(math.min(end, windowBytes));
    _transcribedUpTo = end;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/live_${DateTime.now().microsecondsSinceEpoch}.wav';
    final watch = Stopwatch()..start();
    try {
      await File(path).writeAsBytes(_wav(pcm), flush: true);
      if (kDebugMode) {
        // نسخة التطوير: آخر مقطع مسموع للفحص (لا تُبنى في نسخة الإصدار).
        final debugCopy = File(
          '${(await modelFile()).parent.path}/last_live.wav',
        );
        await File(path).copy(debugCopy.path);
      }
      final model = await modelFile();
      final response = await const Whisper(model: WhisperModel.base).transcribe(
        modelPath: model.path,
        transcribeRequest: TranscribeRequest(
          audio: path,
          language: 'ar',
          isNoTimestamps: true,
          noContext: true,
          suppressNonSpeechTokens: true,
          keepModelLoaded: true,
          // مرمِّز بطول المقطع الفعلي (رقعة packages/whisper_ggml).
          speedUp: true,
          noFallback: true,
          initialPrompt: _prompt,
          threads: Platform.numberOfProcessors.clamp(2, 6),
        ),
      );
      final text = response.text.trim();
      debugPrint(
        '[YousufAsr] ($kind ${watch.elapsedMilliseconds}ms '
        '${(pcm.length / _bytesPerSecond).toStringAsFixed(1)}s) $text',
      );
      _events.add(SpeechEvent(type: kind, text: text, onDevice: true));
    } catch (error) {
      debugPrint('[YousufAsr] فشل التفريغ: $error');
      if (kind == SpeechEventKind.finalResult) {
        _events.add(
          const SpeechEvent(type: SpeechEventKind.error, code: 'no_match'),
        );
      }
    } finally {
      for (final file in [File(path), File('$path.wav')]) {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
      _busy = false;
    }
  }

  /// آخر [bytes] من الصوت المسجَّل.
  Uint8List _tail(int bytes) {
    final out = Uint8List(bytes);
    var remaining = bytes;
    for (var i = _pcm.length - 1; i >= 0 && remaining > 0; i--) {
      final chunk = _pcm[i];
      final take = math.min(remaining, chunk.length);
      out.setRange(remaining - take, remaining, chunk, chunk.length - take);
      remaining -= take;
    }
    return out;
  }

  /// ملف WAV (PCM 16 بت، ١٦ كيلوهرتز، أحادي).
  static Uint8List _wav(Uint8List pcm) {
    final header = ByteData(44);
    void ascii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        header.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, _bytesPerSecond, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(header.buffer.asUint8List())
          ..add(pcm))
        .takeBytes();
  }

  Future<void> _stopLive() async {
    _live = false;
    _liveTimer?.cancel();
    _liveTimer = null;
    final recorder = _recorder;
    _recorder = null;
    try {
      await recorder?.stop();
    } catch (_) {}
    await _pcmSub?.cancel();
    _pcmSub = null;
    await recorder?.dispose();
    _events.add(
      const SpeechEvent(type: SpeechEventKind.speechEnd, onDevice: true),
    );
    // ما قيل بعد آخر تفريغ جزئي.
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_spoke && _pcmBytes > _transcribedUpTo) {
      await _transcribeTail(SpeechEventKind.finalResult);
    } else {
      _events.add(
        const SpeechEvent(type: SpeechEventKind.finalResult, onDevice: true),
      );
    }
    _pcm.clear();
    _pcmBytes = 0;
  }

  /// إيقاف تلقائي: بعد بدء الكلام، سكوت ١٫٦ ثانية يعني انتهاء الآية.
  /// وحدّ أقصى ٤٥ ثانية للتسجيل الواحد.
  void _watchSilence(AudioRecorder recorder) {
    var spoke = false;
    DateTime? quietSince;
    final began = DateTime.now();
    _amplitudeSub = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 150))
        .listen((amp) {
          final now = DateTime.now();
          final loud = amp.current > -38; // dBFS
          if (loud) {
            if (!spoke) {
              spoke = true;
              _events.add(
                const SpeechEvent(
                  type: SpeechEventKind.speechStart,
                  onDevice: true,
                ),
              );
            }
            quietSince = null;
          } else if (spoke) {
            quietSince ??= now;
          }
          final silentEnough =
              spoke &&
              quietSince != null &&
              now.difference(quietSince!) > const Duration(milliseconds: 1600);
          final tooLong = now.difference(began) > const Duration(seconds: 45);
          if (silentEnough || tooLong) unawaited(stop());
        });
  }

  /// يوقف التسجيل ويفرّغه، ثم يرسل النص النهائي.
  Future<void> stop() async {
    if (_live) return _stopLive();
    final recorder = _recorder;
    final path = _audioPath;
    _recorder = null;
    _audioPath = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    if (recorder == null || path == null) return;
    try {
      await recorder.stop();
    } catch (_) {}
    await recorder.dispose();
    _events.add(
      const SpeechEvent(type: SpeechEventKind.speechEnd, onDevice: true),
    );

    final model = await modelFile();
    final watch = Stopwatch()..start();
    try {
      final response = await const Whisper(model: WhisperModel.base).transcribe(
        modelPath: model.path,
        transcribeRequest: TranscribeRequest(
          audio: path,
          language: 'ar',
          isNoTimestamps: true,
          noContext: true,
          suppressNonSpeechTokens: true,
          keepModelLoaded: true,
          speedUp: true,
          noFallback: true,
          threads: Platform.numberOfProcessors.clamp(2, 6),
        ),
      );
      final text = response.text.trim();
      debugPrint('[YousufAsr] (${watch.elapsedMilliseconds}ms) $text');
      _events.add(
        SpeechEvent(
          type: SpeechEventKind.finalResult,
          text: text,
          onDevice: true,
        ),
      );
    } catch (error) {
      debugPrint('[YousufAsr] فشل التفريغ: $error');
      _events.add(
        const SpeechEvent(type: SpeechEventKind.error, code: 'no_match'),
      );
    } finally {
      try {
        File(path).deleteSync();
        File('$path.wav').deleteSync();
      } catch (_) {}
    }
  }

  /// إلغاء بلا نتيجة.
  Future<void> cancel() async {
    _live = false;
    _liveTimer?.cancel();
    _liveTimer = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    _pcm.clear();
    _pcmBytes = 0;
    final recorder = _recorder;
    _recorder = null;
    _audioPath = null;
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    try {
      await recorder?.stop();
      await recorder?.dispose();
    } catch (_) {}
  }

  /// تحرير النموذج من الذاكرة (عند الخروج من وضع الحفظ).
  Future<void> release() async {
    _warm = false;
    await cancel();
    try {
      await const Whisper(model: WhisperModel.base).releaseModel();
    } catch (_) {}
  }
}
