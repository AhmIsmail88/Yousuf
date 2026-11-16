import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/net/resumable_download.dart';

import 'package:sqlite3/sqlite3.dart';

import '../../../core/db/content_db.dart';
import '../domain/quran_extras.dart';

/// ملفات التفاسير والترجمات المنزَّلة: `<appSupport>/quran_extras/<slug>.sqlite`.
///
/// التنزيل طلب GET عادي للملف — لا يُرسل أي بيان عن المستخدم.
class QuranExtrasStore {
  QuranExtrasStore._();

  static Future<File> fileFor(String slug) async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/quran_extras',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/$slug.sqlite');
  }

  static Future<Set<String>> downloaded() async {
    final result = <String>{};
    for (final extra in quranExtrasCatalog) {
      final file = await fileFor(extra.slug);
      if (file.existsSync() && file.lengthSync() > 0) result.add(extra.slug);
    }
    return result;
  }

  /// ينزّل المصدر ويتحقق من بصمته ثم يفكّ ضغطه. يرمي استثناءً عند الفشل.
  static Future<void> download(
    QuranExtra extra, {
    void Function(double progress)? onProgress,
  }) async {
    final target = await fileFor(extra.slug);
    final packed = File('${target.path}.gz.part');
    final unpacked = File('${target.path}.part');
    try {
      await downloadResumable(
        url: Uri.parse(extra.url),
        part: packed,
        expectedBytes: extra.bytes,
        onProgress: onProgress,
      );
      final digest = (await sha256.bind(packed.openRead()).first).toString();
      if (digest != extra.sha256) throw StateError('بصمة الملف غير مطابقة');
      await packed
          .openRead()
          .transform(gzip.decoder)
          .pipe(unpacked.openWrite());
      final db = sqlite3.open(unpacked.path, mode: OpenMode.readOnly);
      try {
        final slug = db
            .select("SELECT value FROM meta WHERE key = 'slug'")
            .firstOrNull?['value'];
        if (slug != extra.slug) throw StateError('ملف لمصدر آخر');
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

/// قراءة مصدر منزَّل: نص الآية (التفسير المشترك بين آيات يعود نفسه لكلٍّ منها).
class QuranExtraDb {
  QuranExtraDb(this._db);

  factory QuranExtraDb.open(String path) =>
      QuranExtraDb(sqlite3.open(path, mode: OpenMode.readOnly));

  final Database _db;

  String? textFor(int surah, int ayah) =>
      _db.select(
            'SELECT b.text FROM ayah a JOIN body b ON b.id = a.body_id '
            'WHERE a.ayah_key = ?',
            [surah * 1000 + ayah],
          ).firstOrNull?['text']
          as String?;

  /// الآيات التي يشترك معها هذا التفسير (لعرض «تفسير الآيات ٣–٥»).
  ({int first, int last}) sharedRange(int surah, int ayah) {
    final key = surah * 1000 + ayah;
    final rows = _db.select(
      'SELECT MIN(ayah_key) AS first, MAX(ayah_key) AS last FROM ayah '
      'WHERE body_id = (SELECT body_id FROM ayah WHERE ayah_key = ?) '
      'AND ayah_key / 1000 = ?',
      [key, surah],
    );
    final row = rows.firstOrNull;
    final first = (row?['first'] as int?) ?? key;
    final last = (row?['last'] as int?) ?? key;
    return (first: first % 1000, last: last % 1000);
  }

  void close() => _db.close();
}

/// التفسير الميسر وأسباب النزول — مضمَّنان في قاعدة المحتوى.
class AyahStudyRepository {
  AyahStudyRepository(this._content);

  final ContentDb _content;

  String? muyassar(int ayahId) =>
      _content.db.select(
            'SELECT t.text FROM tafsir_text t JOIN tafsir f ON f.id = t.tafsir_id '
            "WHERE f.slug = 'muyassar' AND t.ayah_id = ?",
            [ayahId],
          ).firstOrNull?['text']
          as String?;

  String? asbab(int ayahId) =>
      _content.db.select('SELECT text FROM asbab_nuzul WHERE ayah_id = ?', [
            ayahId,
          ]).firstOrNull?['text']
          as String?;
}
