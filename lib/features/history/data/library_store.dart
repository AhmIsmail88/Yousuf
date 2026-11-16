import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/net/resumable_download.dart';

import 'package:sqlite3/sqlite3.dart';

import '../domain/library_catalog.dart';

/// ملفات كتب المكتبة المنزَّلة: `<appSupport>/library/<slug>.sqlite`.
///
/// التنزيل طلب GET عادي للملف — لا يُرسل أي بيان عن المستخدم.
class LibraryStore {
  LibraryStore._();

  static Future<File> fileFor(String slug) async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/library',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/$slug.sqlite');
  }

  static Future<Set<String>> downloaded() async {
    final result = <String>{};
    for (final book in libraryCatalog) {
      final file = await fileFor(book.slug);
      if (file.existsSync() && file.lengthSync() > 0) result.add(book.slug);
    }
    return result;
  }

  /// ينزّل الكتاب ويتحقق من بصمته ثم يفكّ ضغطه. يرمي استثناءً عند الفشل.
  static Future<void> download(
    LibraryBook book, {
    void Function(double progress)? onProgress,
  }) async {
    final target = await fileFor(book.slug);
    final packed = File('${target.path}.gz.part');
    final unpacked = File('${target.path}.part');
    try {
      await downloadResumable(
        url: Uri.parse(book.url),
        part: packed,
        expectedBytes: book.bytes,
        onProgress: onProgress,
      );
      final digest = (await sha256.bind(packed.openRead()).first).toString();
      if (digest != book.sha256) throw StateError('بصمة الملف غير مطابقة');
      await packed
          .openRead()
          .transform(gzip.decoder)
          .pipe(unpacked.openWrite());
      final db = sqlite3.open(unpacked.path, mode: OpenMode.readOnly);
      try {
        final slug = db
            .select("SELECT value FROM meta WHERE key = 'slug'")
            .firstOrNull?['value'];
        if (slug != book.slug) throw StateError('ملف لكتاب آخر');
      } finally {
        db.close();
      }
      await unpacked.rename(target.path);
    } finally {
      for (final file in [packed, unpacked]) {
        if (file.existsSync()) file.deleteSync();
      }
    }
  }

  static Future<void> delete(String slug) async {
    final file = await fileFor(slug);
    if (file.existsSync()) file.deleteSync();
  }
}

/// قراءة كتاب منزَّل (للقراءة فقط).
class LibraryBookDb {
  LibraryBookDb(this._db);

  factory LibraryBookDb.open(String path) =>
      LibraryBookDb(sqlite3.open(path, mode: OpenMode.readOnly));

  final Database _db;

  late final int pageCount =
      _db.select('SELECT COUNT(*) AS n FROM page').first['n'] as int;

  List<LibraryChapter> chapters() => _db
      .select('SELECT title, volume, first_page FROM chapter ORDER BY id')
      .map(
        (row) => LibraryChapter(
          title: row['title'] as String,
          volume: row['volume'] as String?,
          firstPage: row['first_page'] as int,
        ),
      )
      .toList(growable: false);

  /// الصفحة رقم [index] (يبدأ من ١).
  LibraryPage? page(int index) {
    final row = _db.select(
      'SELECT p.id, p.volume, p.page_num, p.text, c.title FROM page p '
      'JOIN chapter c ON c.id = p.chapter_id WHERE p.id = ?',
      [index],
    ).firstOrNull;
    if (row == null) return null;
    return LibraryPage(
      index: row['id'] as int,
      chapter: row['title'] as String,
      text: row['text'] as String,
      volume: row['volume'] as String?,
      pageNum: row['page_num'] as String?,
    );
  }

  String meta(String key) =>
      (_db.select('SELECT value FROM meta WHERE key = ?', [
            key,
          ]).firstOrNull?['value']
          as String?) ??
      '';

  void close() => _db.close();
}

// ---------------- المزوّدات ----------------

final downloadedLibraryProvider = FutureProvider<Set<String>>(
  (ref) => LibraryStore.downloaded(),
);

/// تنزيلات جارية: معرّف الكتاب ← التقدّم (٠–١).
class LibraryDownloads extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  Future<void> download(LibraryBook book) async {
    if (state.containsKey(book.slug)) return;
    state = {...state, book.slug: 0};
    try {
      await LibraryStore.download(
        book,
        onProgress: (progress) => state = {...state, book.slug: progress},
      );
    } finally {
      state = {...state}..remove(book.slug);
      ref.invalidate(downloadedLibraryProvider);
    }
  }

  Future<void> delete(String slug) async {
    ref.invalidate(libraryBookDbProvider(slug));
    await LibraryStore.delete(slug);
    ref.invalidate(downloadedLibraryProvider);
  }
}

final libraryDownloadsProvider =
    NotifierProvider<LibraryDownloads, Map<String, double>>(
      LibraryDownloads.new,
    );

/// كتاب منزَّل مفتوح للقراءة — يُغلق حين لا يستعمله أحد.
final libraryBookDbProvider = FutureProvider.autoDispose
    .family<LibraryBookDb, String>((ref, slug) async {
      final file = await LibraryStore.fileFor(slug);
      if (!file.existsSync()) throw StateError('الكتاب غير منزَّل');
      final db = LibraryBookDb.open(file.path);
      ref.onDispose(db.close);
      return db;
    });
