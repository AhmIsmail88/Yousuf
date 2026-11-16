import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../quran/presentation/quran_providers.dart';
import '../data/hadith_book_store.dart';
import '../data/hadith_repository.dart';
import '../domain/hadith_library.dart';
import '../domain/hadith_models.dart';

/// مستودع الحديث — يقرأ من قاعدة المحتوى المشحونة.
final hadithRepositoryProvider = FutureProvider<HadithRepository>((ref) async {
  final content = await ref.watch(contentDbProvider.future);
  return HadithRepository(content);
});

/// كتب الحديث المضمَّنة (الأربعينات).
final hadithBooksProvider = FutureProvider<List<HadithBook>>((ref) async {
  final repository = await ref.watch(hadithRepositoryProvider.future);
  return repository.books();
});

// ---------------- المكتبة القابلة للتنزيل ----------------

/// الكتب الموجودة على الجهاز.
final downloadedHadithBooksProvider = FutureProvider<Set<String>>(
  (ref) => HadithBookStore.downloaded(),
);

/// تنزيلات جارية: معرّف الكتاب ← التقدّم (٠–١).
class HadithDownloads extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  bool isDownloading(String slug) => state.containsKey(slug);

  /// ينزّل الكتاب ويرمي استثناءً عند الفشل.
  Future<void> download(HadithCollection book) async {
    if (isDownloading(book.slug)) return;
    state = {...state, book.slug: 0};
    try {
      await HadithBookStore.download(
        book,
        onProgress: (progress) => state = {...state, book.slug: progress},
      );
    } finally {
      state = {...state}..remove(book.slug);
      ref.invalidate(downloadedHadithBooksProvider);
    }
  }

  Future<void> delete(String slug) async {
    ref.invalidate(hadithBookDbProvider(slug));
    await HadithBookStore.delete(slug);
    ref.invalidate(downloadedHadithBooksProvider);
  }
}

final hadithDownloadsProvider =
    NotifierProvider<HadithDownloads, Map<String, double>>(HadithDownloads.new);

/// كتاب منزَّل مفتوح للقراءة — يُغلق حين لا يستعمله أحد.
final hadithBookDbProvider = FutureProvider.autoDispose
    .family<HadithBookDb, String>((ref, slug) async {
      final file = await HadithBookStore.fileFor(slug);
      if (!file.existsSync()) throw StateError('الكتاب غير منزَّل');
      final db = HadithBookDb.open(file.path);
      ref.onDispose(db.close);
      return db;
    });

/// أبواب كتاب منزَّل.
final hadithSectionsProvider = FutureProvider.autoDispose
    .family<List<HadithSection>, String>((ref, slug) async {
      final db = await ref.watch(hadithBookDbProvider(slug).future);
      return db.sections();
    });

/// أحاديث باب من كتاب منزَّل.
final hadithSectionProvider = FutureProvider.autoDispose
    .family<List<BookHadith>, ({String slug, int section})>((ref, key) async {
      final db = await ref.watch(hadithBookDbProvider(key.slug).future);
      return db.inSection(key.section);
    });

/// أحاديث كتاب مضمَّن (الأربعينات).
final bundledHadithProvider = FutureProvider.family<List<Hadith>, int>((
  ref,
  bookId,
) async {
  final repository = await ref.watch(hadithRepositoryProvider.future);
  return repository.hadithOfBook(bookId);
});
