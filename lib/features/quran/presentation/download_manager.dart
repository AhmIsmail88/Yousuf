import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/quran_reciter.dart';
import 'quran_providers.dart';

/// حالة تحميل جارٍ.
class DownloadJob {
  const DownloadJob({
    required this.label,
    required this.reciter,
    required this.done,
    required this.total,
    this.cancelled = false,
  });

  final String label;
  final QuranReciter reciter;
  final int done;
  final int total;
  final bool cancelled;

  double get progress => total == 0 ? 0 : done / total;

  DownloadJob copyWith({int? done, int? total, bool? cancelled}) => DownloadJob(
    label: label,
    reciter: reciter,
    done: done ?? this.done,
    total: total ?? this.total,
    cancelled: cancelled ?? this.cancelled,
  );
}

/// نتيجة آخر تحميل (لرسالة واحدة في الواجهة).
enum DownloadOutcome { completed, cancelled, failed }

typedef DownloadResult = ({
  String label,
  DownloadOutcome outcome,
  String? error,
});

/// مدير التحميلات العام — يعيش خارج الشاشات.
///
/// الخروج من مركز التحميلات أو المصحف أو قفل الهاتف لا يوقف التحميل:
/// على أندرويد تعمل خدمة في المقدمة (`yousuf/downloads`) تُبقي العملية حيّة
/// وتعرض التقدّم في إشعار بزر «إيقاف».
class DownloadManager extends Notifier<DownloadJob?> {
  static const _channel = MethodChannel('yousuf/downloads');
  static bool get _native => !kIsWeb && Platform.isAndroid;

  final _results = StreamController<DownloadResult>.broadcast();

  /// نتائج التحميلات المنتهية (للرسائل).
  Stream<DownloadResult> get results => _results.stream;

  @override
  DownloadJob? build() {
    if (_native) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'cancelled') cancel();
      });
    }
    ref.onDispose(_results.close);
    return null;
  }

  bool get busy => state != null;

  /// يبدأ تحميل مدى آيات للقارئ الحالي (تحميل واحد في كل مرة).
  Future<void> start({
    required String label,
    required int first,
    required int last,
  }) async {
    if (state != null || last < first) return;
    // مستودع القارئ الحالي؛ تغيير القارئ معطّل في الواجهة أثناء التحميل.
    final repository = ref.read(quranAudioRepositoryProvider);
    final reciter = repository.reciter;
    final total = last - first + 1;
    state = DownloadJob(label: label, reciter: reciter, done: 0, total: total);
    await _nativeCall('start', label, 0, total);

    var lastNotified = 0;
    DownloadOutcome outcome = DownloadOutcome.completed;
    String? error;
    try {
      await repository.downloadRange(
        first,
        last,
        isCancelled: () => state?.cancelled ?? true,
        onProgress: (done, total) {
          final job = state;
          if (job == null) return;
          state = job.copyWith(done: done, total: total);
          // تحديث الإشعار كل ١٪ تقريباً.
          if (done - lastNotified >= (total / 100).ceil() || done == total) {
            lastNotified = done;
            unawaited(_nativeCall('progress', label, done, total));
          }
        },
      );
      if (state?.cancelled ?? false) outcome = DownloadOutcome.cancelled;
    } catch (e) {
      outcome = (state?.cancelled ?? false)
          ? DownloadOutcome.cancelled
          : DownloadOutcome.failed;
      error = '$e';
    } finally {
      state = null;
      await _nativeCall('stop', label, 0, 0);
      ref.invalidate(downloadedIdsProvider(reciter.id));
      _results.add((label: label, outcome: outcome, error: error));
    }
  }

  void cancel() {
    final job = state;
    if (job != null && !job.cancelled) state = job.copyWith(cancelled: true);
  }

  Future<void> _nativeCall(
    String method,
    String title,
    int done,
    int total,
  ) async {
    if (!_native) return;
    try {
      await _channel.invokeMethod<bool>(method, {
        'title': title,
        'done': done,
        'total': total,
      });
    } catch (error) {
      debugPrint('[YousufDownloads] $method: $error');
    }
  }
}

final downloadManagerProvider = NotifierProvider<DownloadManager, DownloadJob?>(
  DownloadManager.new,
);

/// معرّفات الآيات المحمّلة لقارئ — تُبطَل عند الحذف أو بعد التحميل.
final downloadedIdsProvider = FutureProvider.family<Set<int>, String>((
  ref,
  reciterId,
) async {
  final repository = ref.watch(quranAudioRepositoryProvider);
  if (repository.reciter.id != reciterId) return const <int>{};
  return repository.downloadedIds();
});
