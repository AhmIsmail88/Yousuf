import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/content_db.dart';
import '../../../core/prefs/shared_preferences_provider.dart';
import '../data/quran_audio_repository.dart';
import '../data/quran_repository.dart';
import '../domain/quran_models.dart';
import '../domain/quran_reciter.dart';

/// قاعدة المحتوى (تُفتح مرة واحدة لكل تشغيل).
final contentDbProvider = FutureProvider<ContentDb>((ref) async {
  final content = await ContentDb.openFromAsset();
  ref.onDispose(content.dispose);
  return content;
});

/// مستودع المصحف.
final quranRepositoryProvider = FutureProvider<QuranRepository>((ref) async {
  final content = await ref.watch(contentDbProvider.future);
  return QuranRepository(content);
});

/// السور الـ114.
final surahsProvider = FutureProvider<List<Surah>>((ref) async {
  final repository = await ref.watch(quranRepositoryProvider.future);
  return repository.surahs();
});

const String _reciterKey = 'quran.reciter';

/// القارئ المختار للاستماع والتحميل — يُحفظ محلياً.
class QuranReciterNotifier extends Notifier<QuranReciter> {
  @override
  QuranReciter build() =>
      reciterById(ref.watch(sharedPreferencesProvider).getString(_reciterKey));

  Future<void> select(QuranReciter reciter) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(_reciterKey, reciter.id);
    state = reciter;
  }
}

final quranReciterProvider =
    NotifierProvider<QuranReciterNotifier, QuranReciter>(
      QuranReciterNotifier.new,
    );

/// مستودع صوت القارئ الحالي — يُغلق تلقائياً عند تغيير القارئ.
final quranAudioRepositoryProvider = Provider<QuranAudioRepository>((ref) {
  final reciter = ref.watch(quranReciterProvider);
  final repository = QuranAudioRepository(reciter: reciter);
  ref.onDispose(repository.dispose);
  return repository;
});

const String _cacheWhilePlayingKey = 'quran.cache_while_playing';

/// حفظ الآية أثناء التلاوة (بث فوري + حفظ محلي) — مفعّل افتراضياً.
class CacheWhilePlayingNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_cacheWhilePlayingKey) ??
      true;

  Future<void> set(bool value) async {
    await ref
        .read(sharedPreferencesProvider)
        .setBool(_cacheWhilePlayingKey, value);
    state = value;
  }
}

final cacheWhilePlayingProvider =
    NotifierProvider<CacheWhilePlayingNotifier, bool>(
      CacheWhilePlayingNotifier.new,
    );

/// نص البحث الحالي.
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

/// نتائج البحث (فارغة لأقل من حرفين).
final searchResultsProvider = FutureProvider<List<AyahSearchHit>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.length < 2) return const [];
  final repository = await ref.watch(quranRepositoryProvider.future);
  return repository.search(query);
});

/// آيات صفحة مصحف — تُحرَّر من الذاكرة حين لا تعرضها أي شاشة.
final quranPageProvider = FutureProvider.autoDispose.family<QuranPage, int>((
  ref,
  pageNumber,
) async {
  final repository = await ref.watch(quranRepositoryProvider.future);
  return repository.page(pageNumber);
});

/// بدايات الأجزاء الثلاثين — تبويب «الأجزاء» في الفهرس.
final juzStartsProvider = FutureProvider<List<JuzStart>>((ref) async {
  final repository = await ref.watch(quranRepositoryProvider.future);
  return repository.juzStarts();
});

/// أول جزء تبدأ به كل سورة — لفهرس الأجزاء في وضع الأطفال.
final surahStartJuzProvider = FutureProvider<Map<int, int>>((ref) async {
  final repository = await ref.watch(quranRepositoryProvider.future);
  return repository.startJuzOfSurahs();
});

const _lastPageKey = 'quran.last_page';

/// آخر صفحة قراءة (لمتابعة القراءة).
final lastReadPageProvider = FutureProvider<int>((ref) async {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getInt(_lastPageKey) ?? 1;
});

/// يحفظ آخر صفحة قراءة ويحدّث البطاقات التي تعرضها.
Future<void> saveLastReadPage(WidgetRef ref, int page) async {
  final prefs = ref.read(sharedPreferencesProvider);
  if (prefs.getInt(_lastPageKey) == page) return;
  await prefs.setInt(_lastPageKey, page);
  ref.invalidate(lastReadPageProvider);
}

/// علامات الآيات — تُحفظ محلياً بمفتاح «سورة:آية».
class QuranBookmarksNotifier extends Notifier<Set<String>> {
  static const key = 'quran.bookmarks';

  @override
  Set<String> build() =>
      (ref.watch(sharedPreferencesProvider).getStringList(key) ?? const [])
          .toSet();

  bool contains(int surahId, int number) => state.contains('$surahId:$number');

  /// يضيف علامة (العلامات السابقة تبقى كما هي).
  Future<void> add(int surahId, int number) async {
    final mark = '$surahId:$number';
    if (state.contains(mark)) return;
    await _save({...state, mark});
  }

  /// يحذف علامة واحدة.
  Future<void> remove(int surahId, int number) async {
    final mark = '$surahId:$number';
    if (!state.contains(mark)) return;
    await _save({...state}..remove(mark));
  }

  Future<void> _save(Set<String> next) async {
    state = next;
    await ref
        .read(sharedPreferencesProvider)
        .setStringList(key, next.toList(growable: false));
  }

  /// يضيف/يزيل علامة ويعيد الحالة الجديدة (true = صار معلَّماً).
  Future<bool> toggle(int surahId, int number) async {
    final mark = '$surahId:$number';
    final next = {...state};
    final added = !next.remove(mark);
    if (added) next.add(mark);
    state = next;
    await ref
        .read(sharedPreferencesProvider)
        .setStringList(key, next.toList(growable: false));
    return added;
  }
}

final quranBookmarksProvider =
    NotifierProvider<QuranBookmarksNotifier, Set<String>>(
      QuranBookmarksNotifier.new,
    );

/// الآيات المعلَّمة كاملة (لعرضها في تبويب «العلامات»).
final bookmarkedAyahsProvider = FutureProvider<List<AyahSearchHit>>((
  ref,
) async {
  final marks = ref.watch(quranBookmarksProvider);
  if (marks.isEmpty) return const [];
  final repository = await ref.watch(quranRepositoryProvider.future);
  final hits = <AyahSearchHit>[];
  // الأحدث إضافةً أولاً.
  for (final mark in marks.toList().reversed) {
    final parts = mark.split(':');
    if (parts.length != 2) continue;
    final surahId = int.tryParse(parts[0]);
    final number = int.tryParse(parts[1]);
    if (surahId == null || number == null) continue;
    final ayah = repository.ayahOf(surahId, number);
    if (ayah == null) continue;
    hits.add(
      AyahSearchHit(
        ayah: ayah,
        surahNameAr: repository.surah(surahId)?.nameAr ?? '',
        snippet: ayah.text,
      ),
    );
  }
  return hits;
});
