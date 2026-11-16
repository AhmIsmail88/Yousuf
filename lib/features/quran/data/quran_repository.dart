import '../../../core/db/content_db.dart';
import '../domain/quran_models.dart';

/// الوصول إلى نص القرآن والبحث — كله محلي من content.sqlite (SPEC §5، §10).
class QuranRepository {
  QuranRepository(this._content);

  final ContentDb _content;

  static const int totalPages = 604;

  /// السور الـ114.
  List<Surah> surahs() => _content.db
      .select('SELECT * FROM surah ORDER BY id')
      .map((row) => Surah.fromRow(row))
      .toList(growable: false);

  Surah? surah(int id) {
    final rows = _content.db.select('SELECT * FROM surah WHERE id = ?', [id]);
    return rows.isEmpty ? null : Surah.fromRow(rows.first);
  }

  /// آيات صفحة كاملة (1..604) — مرتبة.
  QuranPage page(int pageNumber) {
    final rows = _content.db.select(
      'SELECT * FROM ayah WHERE page = ? ORDER BY surah_id, number',
      [pageNumber],
    );
    return QuranPage(
      page: pageNumber,
      ayat: rows.map((row) => Ayah.fromRow(row)).toList(growable: false),
    );
  }

  /// آية محددة (سورة/رقم) — لبطاقات العرض (آية اليوم).
  Ayah? ayahOf(int surahId, int number) {
    final rows = _content.db.select(
      'SELECT * FROM ayah WHERE surah_id = ? AND number = ? LIMIT 1',
      [surahId, number],
    );
    return rows.isEmpty ? null : Ayah.fromRow(rows.first);
  }

  /// كل آيات سورة.
  List<Ayah> ayatOfSurah(int surahId) => _content.db
      .select('SELECT * FROM ayah WHERE surah_id = ? ORDER BY number', [
        surahId,
      ])
      .map((row) => Ayah.fromRow(row))
      .toList(growable: false);

  /// بحث نصي في المصحف (FTS5 على النص المطبع) — مع تجاهل التشكيل.
  ///
  /// يدعم البحث بعدة كلمات (يجب أن تجتمع كلها) وبادئة الكلمة.
  List<AyahSearchHit> search(String query, {int limit = 50}) {
    final match = _buildMatchQuery(query);
    if (match == null) return const [];
    final rows = _content.db.select(
      '''
      SELECT a.*, s.name_ar AS surah_name,
             snippet(ayah_fts, 0, '«', '»', '…', 10) AS snippet
      FROM ayah_fts
      JOIN ayah a ON a.id = ayah_fts.ayah_id
      JOIN surah s ON s.id = a.surah_id
      WHERE ayah_fts.text_simple MATCH ?
      ORDER BY a.surah_id, a.number
      LIMIT ?
      ''',
      [match, limit],
    );
    return rows
        .map(
          (row) => AyahSearchHit(
            ayah: Ayah.fromRow(row),
            surahNameAr: row['surah_name']! as String,
            snippet: (row['snippet'] as String?) ?? '',
          ),
        )
        .toList(growable: false);
  }

  /// أول صفحة تبدأ بها سورة.
  int startPageOfSurah(int surahId) => surah(surahId)?.startPage ?? 1;

  /// أول جزء تبدأ به كل سورة — لفهرس الأجزاء (وضع الأطفال والمصحف).
  Map<int, int> startJuzOfSurahs() => {
    for (final row in _content.db.select(
      'SELECT surah_id, MIN(juz) AS juz FROM ayah '
      'WHERE juz IS NOT NULL GROUP BY surah_id',
    ))
      row['surah_id']! as int: row['juz']! as int,
  };

  /// بدايات الأجزاء الثلاثين — للفهرس.
  List<JuzStart> juzStarts() => _content.db
      .select(
        'SELECT juz, MIN(page) AS page FROM ayah '
        'WHERE juz IS NOT NULL GROUP BY juz ORDER BY juz',
      )
      .map(
        (row) => JuzStart(juz: row['juz']! as int, page: row['page']! as int),
      )
      .toList(growable: false);

  /// مدى معرّفات الآيات لسورة (شامل الطرفين) — للتحميل.
  ({int first, int last}) rangeOfSurah(int surahId) =>
      _range('surah_id = ?', [surahId]);

  /// مدى معرّفات الآيات لجزء.
  ({int first, int last}) rangeOfJuz(int juz) => _range('juz = ?', [juz]);

  /// مدى معرّفات الآيات لصفحة.
  ({int first, int last}) rangeOfPage(int page) => _range('page = ?', [page]);

  /// مدى المصحف كاملاً.
  ({int first, int last}) wholeMushaf() => _range('1 = 1', const []);

  /// مدى معرّفات الآيات بشرط — المعرّفات متصلة بترتيب المصحف.
  ({int first, int last}) _range(String where, List<Object?> args) {
    final row = _content.db
        .select(
          'SELECT MIN(id) AS first, MAX(id) AS last FROM ayah WHERE $where',
          args,
        )
        .first;
    return (
      first: (row['first'] as int?) ?? 0,
      last: (row['last'] as int?) ?? 0,
    );
  }

  /// يبني استعلام FTS آمن: تطبيع لكل كلمة + بادئة.
  String? _buildMatchQuery(String raw) {
    final normalized = _normalizeArabic(raw);
    final tokens = normalized
        .split(RegExp(r'[^\u0600-\u06FF0-9A-Za-z]+'))
        .where((token) => token.isNotEmpty)
        .map((token) => '"$token"*')
        .toList(growable: false);
    if (tokens.isEmpty) return null;
    return tokens.join(' AND ');
  }
}

const _diacriticsPattern = '[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]';

/// تطبيع مطابق لقاعدة البناء (build.py) — للبحث فقط.
String _normalizeArabic(String text) {
  return text
      .replaceAll(RegExp(_diacriticsPattern), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه');
}
