import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../data/quran_audio_repository.dart';
import '../data/quran_repository.dart';
import '../domain/quran_models.dart';
import 'quran_providers.dart';

/// حالة التلاوة المعروضة.
class QuranPlaybackState {
  const QuranPlaybackState({
    this.ayah,
    this.surahName = '',
    this.playing = false,
    this.loading = false,
    this.error,
    this.clip,
  });

  /// مقطع صوتي غير التلاوة يُشغَّل بالمشغّل نفسه (متن تحفة الأطفال…) —
  /// just_audio_background لا يسمح إلا بمشغّل واحد في التطبيق.
  final String? clip;

  /// الآية الجارية (null = لا تلاوة).
  final Ayah? ayah;
  final String surahName;
  final bool playing;
  final bool loading;
  final String? error;

  bool get active => ayah != null;

  QuranPlaybackState copyWith({
    Ayah? ayah,
    String? surahName,
    bool? playing,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => QuranPlaybackState(
    clip: clip,
    ayah: ayah ?? this.ayah,
    surahName: surahName ?? this.surahName,
    playing: playing ?? this.playing,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

/// مشغّل التلاوة العام — يعيش خارج شاشة المصحف (SPEC §7.3).
///
/// - الخروج من المصحف أو قفل الشاشة لا يوقف التلاوة (خدمة في المقدمة مع
///   إشعار وأزرار شاشة القفل عبر just_audio_background).
/// - التلاوة لا تقف عند آخر السورة: القائمة تمتد تلقائياً بالسور التالية
///   حتى آخر المصحف.
/// - كل آية تُشغَّل من الملف المحلي إن وُجد، وإلا تُبثّ وتُحفظ في الخلفية
///   (حسب «الحفظ أثناء التلاوة»)، وتُجهَّز الآية التالية مسبقاً.
class QuranPlayerNotifier extends Notifier<QuranPlaybackState> {
  AudioPlayer? _player;
  final List<Ayah> _queue = [];
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _extending = false;

  /// مستودع الصوت للقائمة الحالية: القارئ العام، أو قارئ آخر لتلاوة مفردة
  /// (المصحف المعلّم في قسم الأطفال).
  QuranAudioRepository? _override;

  /// تلاوة آية واحدة (قسم الأطفال): لا تمتد القائمة ولا تُحفظ بالقارئ العام.
  bool _single = false;

  /// كم سورة تُلحق بالقائمة في كل مرة.
  static const int _surahsPerChunk = 2;

  @override
  QuranPlaybackState build() {
    // تغيير القارئ يوقف التلاوة الحالية (الملفات من قارئ آخر).
    ref.listen(quranReciterProvider, (previous, next) {
      if (previous?.id != next.id) stop();
    });
    ref.onDispose(() {
      for (final sub in _subs) {
        sub.cancel();
      }
      _player?.dispose();
    });
    return const QuranPlaybackState();
  }

  QuranAudioRepository get _audio =>
      _override ?? ref.read(quranAudioRepositoryProvider);

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer();
    _subs
      ..add(player.currentIndexStream.listen(_onIndex))
      ..add(
        player.playerStateStream.listen((s) {
          final done = s.processingState == ProcessingState.completed;
          state = state.copyWith(
            playing: s.playing && !done,
            loading:
                s.processingState == ProcessingState.loading ||
                s.processingState == ProcessingState.buffering,
          );
          if (done) _finish();
        }),
      );
    return _player = player;
  }

  Future<QuranRepository> get _repository =>
      ref.read(quranRepositoryProvider.future);

  /// يبدأ التلاوة من آية ويستمر حتى آخر المصحف.
  Future<void> playFrom(Ayah start) async {
    _override = null;
    _single = false;
    final player = _ensurePlayer();
    final repository = await _repository;
    _queue
      ..clear()
      ..addAll(_ayatFrom(repository, start.surahId, startNumber: start.number));
    state = state.copyWith(
      ayah: start,
      surahName: repository.surah(start.surahId)?.nameAr ?? '',
      loading: true,
      clearError: true,
    );
    try {
      final sources = [
        for (final ayah in _queue) await _sourceFor(repository, ayah),
      ];
      await player.setAudioSources(sources, initialIndex: 0);
      unawaited(player.play());
    } catch (error) {
      debugPrint('[YousufAudio] تعذر بدء التلاوة: $error');
      state = state.copyWith(
        loading: false,
        playing: false,
        error: 'تعذر تشغيل التلاوة — تحقق من الإنترنت',
      );
    }
  }

  /// يشغّل آية واحدة بمستودع صوت محدد (المصحف المعلّم للأطفال).
  ///
  /// just_audio_background يسمح بمشغّل **واحد** في التطبيق، فكل صوت القرآن
  /// يمر من هنا — مشغّل ثانٍ يُرفض ولا يخرج صوت.
  Future<bool> playSingle(Ayah ayah, QuranAudioRepository audio) async {
    _override = audio;
    _single = true;
    final player = _ensurePlayer();
    final repository = await _repository;
    _queue
      ..clear()
      ..add(ayah);
    state = state.copyWith(
      ayah: ayah,
      surahName: repository.surah(ayah.surahId)?.nameAr ?? '',
      loading: true,
      clearError: true,
    );
    try {
      await player.setAudioSources([await _sourceFor(repository, ayah)]);
      unawaited(player.play());
      if (!await audio.isDownloaded(ayah.id)) {
        unawaited(audio.downloadAyah(ayah.id).then((_) {}, onError: (_) {}));
      }
      return true;
    } catch (error) {
      debugPrint('[YousufAudio] تعذر تشغيل الآية: $error');
      state = state.copyWith(
        loading: false,
        playing: false,
        error: 'تعذر تشغيل التلاوة — تحقق من الإنترنت',
      );
      return false;
    }
  }

  /// آيات سورة البداية (من آية معيّنة) + السور التالية بحجم الدفعة.
  List<Ayah> _ayatFrom(
    QuranRepository repository,
    int surahId, {
    int startNumber = 1,
  }) {
    final result = <Ayah>[];
    for (var s = surahId; s <= 114 && s < surahId + _surahsPerChunk; s++) {
      result.addAll(
        repository
            .ayatOfSurah(s)
            .where((ayah) => s != surahId || ayah.number >= startNumber),
      );
    }
    return result;
  }

  Future<AudioSource> _sourceFor(QuranRepository repository, Ayah ayah) async {
    final audio = _audio;
    final file = await audio.fileFor(ayah.id);
    final surah = repository.surah(ayah.surahId);
    final tag = MediaItem(
      id: '${audio.reciter.id}/${ayah.id}',
      title: 'سورة ${surah?.nameAr ?? ''} · آية ${ayah.number}',
      artist: audio.reciter.nameAr,
      album: 'القرآن الكريم',
    );
    if (await audio.isDownloaded(ayah.id)) {
      return AudioSource.file(file.path, tag: tag);
    }
    return AudioSource.uri(audio.urlFor(ayah.id), tag: tag);
  }

  void _onIndex(int? index) {
    if (index == null || index < 0 || index >= _queue.length) return;
    final ayah = _queue[index];
    _updateCurrent(ayah);
    if (_single) return;
    // حفظ الآية الجارية والتالية (بث + حفظ في الخلفية).
    if (ref.read(cacheWhilePlayingProvider)) {
      unawaited(_cache(ayah.id));
      if (index + 1 < _queue.length) unawaited(_cache(_queue[index + 1].id));
    }
    // قرب نهاية القائمة: نلحق السور التالية فلا تتوقف التلاوة.
    if (index >= _queue.length - 3) unawaited(_extend());
  }

  Future<void> _updateCurrent(Ayah ayah) async {
    final repository = await _repository;
    state = state.copyWith(
      ayah: ayah,
      surahName: repository.surah(ayah.surahId)?.nameAr ?? state.surahName,
    );
  }

  Future<void> _extend() async {
    if (_extending || _queue.isEmpty) return;
    final last = _queue.last;
    final nextSurah = last.surahId + 1;
    if (nextSurah > 114) return;
    _extending = true;
    try {
      final repository = await _repository;
      final more = _ayatFrom(repository, nextSurah);
      final sources = [
        for (final ayah in more) await _sourceFor(repository, ayah),
      ];
      _queue.addAll(more);
      await _player?.addAudioSources(sources);
    } catch (error) {
      debugPrint('[YousufAudio] تعذر إلحاق السور التالية: $error');
    } finally {
      _extending = false;
    }
  }

  Future<void> _cache(int ayahId) async {
    try {
      await _audio.downloadAyah(ayahId);
    } catch (_) {
      // الشبكة غير متاحة — التشغيل مستمر من البث.
    }
  }

  void _finish() {
    // انتهى المصحف (أو القائمة) — نحرّر الحالة.
    state = const QuranPlaybackState();
  }

  Future<void> togglePause() async {
    final player = _player;
    if (player == null) return;
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> next() async => _player?.seekToNext();

  Future<void> previous() async => _player?.seekToPrevious();

  /// يوقف التلاوة إن كانت من هذه السورة (عند مغادرة شاشة الطفل).
  Future<void> stopIfSurah(int surahId) async {
    if (state.ayah?.surahId == surahId) await stop();
  }

  /// يشغّل ملفاً صوتياً واحداً (غير التلاوة) بالمشغّل نفسه، ويوقف ما قبله.
  /// [id] يميّز المقطع في الحالة (`state.clip`) لتعرض الشاشة زر الإيقاف.
  Future<void> playClip({
    required String id,
    required String path,
    required String title,
    required String artist,
  }) async {
    await stop();
    final player = _ensurePlayer();
    state = QuranPlaybackState(clip: id, loading: true);
    try {
      await player.setAudioSource(
        AudioSource.file(
          path,
          tag: MediaItem(id: 'clip/$id', title: title, artist: artist),
        ),
      );
      await player.play();
    } catch (error) {
      debugPrint('[Yousuf] تعذّر تشغيل المقطع: $error');
      state = const QuranPlaybackState();
    }
  }

  Future<void> stop() async {
    _override = null;
    _single = false;
    await _player?.stop();
    _queue.clear();
    state = const QuranPlaybackState();
  }
}

final quranPlayerProvider =
    NotifierProvider<QuranPlayerNotifier, QuranPlaybackState>(
      QuranPlayerNotifier.new,
    );
