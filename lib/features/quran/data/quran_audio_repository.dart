import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../domain/quran_reciter.dart';

/// استثناء التحميل الجزئي: بعض الآيات فشلت.
class QuranDownloadException implements Exception {
  QuranDownloadException({required this.failed, required this.done});

  final int failed;
  final int done;

  @override
  String toString() =>
      'تعذر تحميل $failed آية من ${done + failed} — تحقق من الاتصال';
}

/// صوت التلاوة: تنزيل آيات القارئ المختار وتخزينها محلياً.
///
/// الملفات تُحفظ باسم المعرّف العام للآية (١..٦٢٣٦) داخل مجلد القارئ.
///
/// متانة التنزيل:
/// - مهلة للاتصال ([connectTimeout]) ولتوقّف البيانات ([idleTimeout]) — لا
///   يعلق عامل التنزيل إلى الأبد على اتصال ميت.
/// - الكتابة في `.part` ثم إعادة تسمية؛ والجزئي يُحذف عند أي فشل.
/// - تنزيل الآية نفسها مرة واحدة: طلبان متزامنان (البث + التحميل الجماعي)
///   يشتركان في المستقبل نفسه بدل الكتابة في الملف معاً.
class QuranAudioRepository {
  QuranAudioRepository({
    QuranReciter? reciter,
    http.Client? client,
    Future<Directory> Function()? directoryResolver,
    this.concurrency = 4,
    this.connectTimeout = const Duration(seconds: 20),
    this.idleTimeout = const Duration(seconds: 30),
  }) : reciter = reciter ?? kQuranReciters.first,
       _client = client ?? http.Client(),
       _resolveDirectory = directoryResolver ?? getApplicationSupportDirectory;

  final QuranReciter reciter;
  final int concurrency;
  final Duration connectTimeout;
  final Duration idleTimeout;
  final http.Client _client;
  final Future<Directory> Function() _resolveDirectory;

  /// أقصى عدد محاولات تنزيل متزامنة (يقلّل زمن المصحف الكامل).
  static const int maxConcurrency = 6;

  /// التنزيلات الجارية مشتركة بين كل نسخ المستودع (بالمسار الكامل).
  static final Map<String, Future<File>> _inFlight = {};

  Directory? _cacheDir;

  Future<Directory> _ensureDir() async {
    final cached = _cacheDir;
    if (cached != null) return cached;
    final support = await _resolveDirectory();
    final dir = Directory(
      '${support.path}/audio/${reciter.id}_${reciter.bitrate}',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _cacheDir = dir;
  }

  /// رابط الآية على الشبكة.
  Uri urlFor(int globalAyahId) => reciter.urlFor(globalAyahId);

  Future<File> fileFor(int globalAyahId) async {
    final dir = await _ensureDir();
    return File('${dir.path}/$globalAyahId.mp3');
  }

  /// أصغر ملف آية معقول (أقصر الآيات بجودة ٣٢ ≈ ٤ ك.ب).
  static const int _minBytes = 512;

  static bool _isComplete(File file) =>
      file.existsSync() && file.lengthSync() >= _minBytes;

  /// هل الآية محمّلة فعلاً (حجم معقول)؟
  Future<bool> isDownloaded(int globalAyahId) async =>
      _isComplete(await fileFor(globalAyahId));

  /// عدد الآيات المحمّلة من قائمة — بقراءة المجلد مرة واحدة.
  Future<int> cachedCount(List<int> globalAyahIds) async {
    final downloaded = await downloadedIds();
    return globalAyahIds.where(downloaded.contains).length;
  }

  /// كل معرّفات الآيات المحمّلة لهذا القارئ.
  Future<Set<int>> downloadedIds() async {
    final dir = await _ensureDir();
    final ids = <int>{};
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.mp3')) continue;
      final name = entity.uri.pathSegments.last.replaceAll('.mp3', '');
      final id = int.tryParse(name);
      if (id != null) ids.add(id);
    }
    return ids;
  }

  /// ينزّل آية واحدة (يتخطى الموجودة مسبقاً) ويعيد ملفها.
  Future<File> downloadAyah(
    int globalAyahId, {
    void Function(double progress)? onProgress,
  }) async {
    final file = await fileFor(globalAyahId);
    if (_isComplete(file)) return file;
    final running = _inFlight[file.path];
    if (running != null) return running;

    final future = _download(globalAyahId, file, onProgress);
    _inFlight[file.path] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(file.path);
    }
  }

  Future<File> _download(
    int globalAyahId,
    File file,
    void Function(double progress)? onProgress,
  ) async {
    final url = urlFor(globalAyahId);
    final temp = File('${file.path}.part');
    IOSink? sink;
    try {
      final response = await _client
          .send(http.Request('GET', url))
          .timeout(connectTimeout);
      if (response.statusCode != 200) {
        throw HttpException(
          'فشل تنزيل الآية $globalAyahId (${response.statusCode})',
          uri: url,
        );
      }
      final type = response.headers['content-type'] ?? '';
      if (type.contains('text/html')) {
        throw HttpException('استجابة غير صوتية للآية $globalAyahId', uri: url);
      }

      final total = response.contentLength ?? 0;
      sink = temp.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(idleTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received < _minBytes) {
        throw HttpException('ملف ناقص للآية $globalAyahId', uri: url);
      }
      return await temp.rename(file.path);
    } catch (error) {
      debugPrint('[YousufAudio] $error');
      rethrow;
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (temp.existsSync()) {
        try {
          temp.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// ينزّل مدى آيات (شامل الطرفين) بعدة مسارات متوازية.
  ///
  /// [isCancelled] يُفحص قبل كل آية، و[onProgress] يُنادى بعد كل آية.
  /// يرمي [QuranDownloadException] إن فشلت آيات (مع الاستمرار في الباقي).
  Future<int> downloadRange(
    int first,
    int last, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = last - first + 1;
    if (total <= 0) return 0;

    var next = first;
    var done = 0;
    var failed = 0;

    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        final id = next++;
        if (id > last) return;
        try {
          await downloadAyah(id);
        } catch (_) {
          failed++;
        }
        done++;
        onProgress?.call(done, total);
      }
    }

    final workers = concurrency.clamp(1, maxConcurrency);
    await Future.wait(List.generate(workers, (_) => worker()));
    if (failed > 0) {
      throw QuranDownloadException(failed: failed, done: done - failed);
    }
    return done;
  }

  /// يحذف كل تحميلات هذا القارئ.
  Future<void> deleteAll() async {
    final dir = await _ensureDir();
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
    _cacheDir = null;
  }

  /// تقدير الحجم بالميغابايت (متوسط ~٠.٣ م.ب للآية بجودة ١٢٨).
  double estimatedMegabytes(int ayahCount) =>
      ayahCount * (reciter.bitrate / 128) * 0.32;

  void dispose() => _client.close();
}
