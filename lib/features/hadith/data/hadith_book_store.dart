import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/net/resumable_download.dart';

import 'package:sqlite3/sqlite3.dart';

import '../../quran/domain/recitation_matcher.dart' show normalizeForMatch;
import '../domain/hadith_library.dart';

/// ملفات كتب الحديث المنزَّلة: `<appSupport>/hadith/<slug>.sqlite`.
///
/// التنزيل طلب GET عادي للملف — لا يُرسل أي بيان عن المستخدم.
class HadithBookStore {
  HadithBookStore._();

  static Future<Directory> _dir() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/hadith',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<File> fileFor(String slug) async =>
      File('${(await _dir()).path}/$slug.sqlite');

  /// معرّفات الكتب الموجودة على الجهاز.
  static Future<Set<String>> downloaded() async {
    final result = <String>{};
    for (final book in hadithCatalog) {
      final file = await fileFor(book.slug);
      if (file.existsSync() && file.lengthSync() > 0) result.add(book.slug);
    }
    return result;
  }

  /// ينزّل الكتاب ويتحقق من بصمته ثم يفكّ ضغطه. يرمي استثناءً عند الفشل.
  static Future<void> download(
    HadithCollection book, {
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
      if (digest != book.sha256) {
        throw StateError('بصمة الملف غير مطابقة');
      }
      await packed
          .openRead()
          .transform(gzip.decoder)
          .pipe(unpacked.openWrite());
      // تحقّق أخير: الملف قاعدة صحيحة لهذا الكتاب.
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
class HadithBookDb {
  HadithBookDb(this._db);

  /// يفتح ملف كتاب (يستعمل في الاختبارات أيضاً).
  factory HadithBookDb.open(String path) =>
      HadithBookDb(sqlite3.open(path, mode: OpenMode.readOnly));

  final Database _db;

  List<HadithSection> sections() => _db
      .select('SELECT * FROM section ORDER BY id')
      .map(
        (row) => HadithSection(
          id: row['id'] as int,
          nameEn: row['name_en'] as String,
          total: row['total'] as int,
          first: row['first_number'] as num?,
          last: row['last_number'] as num?,
        ),
      )
      .toList(growable: false);

  List<BookHadith> inSection(int sectionId) => _withGrades(
    _db.select(
      'SELECT id, number, section_id, text FROM hadith '
      'WHERE section_id = ? ORDER BY id',
      [sectionId],
    ),
  );

  BookHadith? byId(int id) {
    final rows = _withGrades(
      _db.select(
        'SELECT id, number, section_id, text FROM hadith WHERE id = ?',
        [id],
      ),
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// بحث في نص الكتاب: كل كلمة بادئة (تطابق «النية» و«النيات»).
  List<BookHadith> search(String query, {int limit = 100}) {
    // التاء المربوطة في آخر الكلمة تُحذف: «النية» تطابق «النيات» و«النية».
    final words =
        normalizeForMatch(query.replaceAll(RegExp(r'ة(?=[ً-ْ]*(\s|$))'), ''))
            .split(' ')
            // «ال» تُحذف: الفهرس يحوي كل كلمة بلا سوابقها (بالنيات ← نيات).
            .map(
              (word) => word.length > 3 && word.startsWith('ال')
                  ? word.substring(2)
                  : word,
            )
            .where((word) => word.length >= 2)
            .toList();
    if (words.isEmpty) return const [];
    final match = words.map((word) => '"$word"*').join(' ');
    return _withGrades(
      _db.select(
        'SELECT h.id, h.number, h.section_id, h.text FROM hadith_fts f '
        'JOIN hadith h ON h.id = f.rowid '
        'WHERE hadith_fts MATCH ? ORDER BY h.id LIMIT ?',
        [match, limit],
      ),
    );
  }

  List<BookHadith> _withGrades(ResultSet rows) {
    if (rows.isEmpty) return const [];
    final ids = rows.map((row) => row['id'] as int).toList();
    final grades = <int, List<HadithGrade>>{};
    final placeholders = List.filled(ids.length, '?').join(',');
    for (final row in _db.select(
      'SELECT * FROM grade WHERE hadith_id IN ($placeholders) ORDER BY rowid',
      ids,
    )) {
      (grades[row['hadith_id'] as int] ??= []).add(
        HadithGrade(
          gradeAr: row['grade_ar'] as String,
          raw: row['grade_raw'] as String,
          category: row['category'] as String,
          grader: row['grader_ar'] as String,
        ),
      );
    }
    return [
      for (final row in rows)
        BookHadith(
          id: row['id'] as int,
          number: row['number'] as String,
          sectionId: row['section_id'] as int,
          text: row['text'] as String,
          grades: grades[row['id'] as int] ?? const [],
        ),
    ];
  }

  void close() => _db.close();
}
