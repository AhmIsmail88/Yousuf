/// نماذج المصحف — Dart خالص (SPEC §5).
library;

/// سورة من قاعدة المحتوى.
class Surah {
  const Surah({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.revelation,
    required this.ayahCount,
    required this.startPage,
  });

  final int id;
  final String nameAr;
  final String nameEn;

  /// makki | madani
  final String revelation;
  final int ayahCount;

  /// صفحة بداية السورة في المصحف (1..604).
  final int startPage;

  bool get isMakki => revelation == 'makki';

  factory Surah.fromRow(Map<String, Object?> row) => Surah(
    id: row['id']! as int,
    nameAr: _cleanName(row['name_ar']! as String),
    nameEn: row['name_en']! as String,
    revelation: row['revelation']! as String,
    ayahCount: row['ayah_count']! as int,
    startPage: row['start_page']! as int,
  );

  /// المصدر يسمّي السورة «سُورَةُ الفَاتِحَةِ» — نزيل البادئة للعرض.
  static String _cleanName(String raw) {
    // «سُورَةُ ٱلْفَاتِحَةِ» → «الفاتحة»: إزالة البادئة والتشكيل وألف الوصل.
    final withoutDiacritics = raw
        .trim()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]'), '')
        .replaceAll('ٱ', 'ا');
    if (withoutDiacritics.startsWith('سورة ')) {
      final spaceIndex = withoutDiacritics.indexOf(' ');
      if (spaceIndex > 0) {
        return withoutDiacritics.substring(spaceIndex + 1).trim();
      }
    }
    return withoutDiacritics;
  }
}

/// آية من قاعدة المحتوى.
class Ayah {
  const Ayah({
    required this.id,
    required this.surahId,
    required this.number,
    required this.text,
    required this.page,
    this.juz,
    this.hizbQuarter,
  });

  final int id;
  final int surahId;

  /// رقم الآية داخل السورة.
  final int number;

  /// النص العثماني (يُنسخ حرفياً من المصدر).
  final String text;
  final int page;
  final int? juz;

  /// ربع الحزب (١–٢٤٠) كما في مصحف المدينة.
  final int? hizbQuarter;

  factory Ayah.fromRow(Map<String, Object?> row) => Ayah(
    id: row['id']! as int,
    surahId: row['surah_id']! as int,
    number: row['number']! as int,
    // المصدر يبدأ بعلامة BOM في أول آية — تُزال للعرض والنسخ.
    text: (row['text_uthmani']! as String)
        .replaceAll('\uFEFF', '')
        .replaceAll('\u200F', ''),
    page: (row['page'] as int?) ?? 0,
    juz: row['juz'] as int?,
    hizbQuarter: row['hizb_quarter'] as int?,
  );
}

/// تسمية موضع ربع الحزب كما تُكتب في ترويسة المصحف:
/// «الحزب ٥٢» / «ربع الحزب ٥٢» / «نصف الحزب ٥٢» / «ثلاثة أرباع الحزب ٥٢».
/// [number] يحوّل الرقم إلى أرقام المصحف.
String hizbQuarterLabel(int quarter, String Function(int) number) {
  final hizb = (quarter - 1) ~/ 4 + 1;
  const prefixes = ['الحزب', 'ربع الحزب', 'نصف الحزب', 'ثلاثة أرباع الحزب'];
  return '${prefixes[(quarter - 1) % 4]} ${number(hizb)}';
}

/// صفحة مصحف كاملة.
class QuranPage {
  const QuranPage({required this.page, required this.ayat});

  final int page;
  final List<Ayah> ayat;

  /// هل تبدأ الصفحة بسورة جديدة؟
  Ayah? get firstAyah => ayat.isEmpty ? null : ayat.first;
}

/// نتيجة بحث في المصحف.
class AyahSearchHit {
  const AyahSearchHit({
    required this.ayah,
    required this.surahNameAr,
    required this.snippet,
  });

  final Ayah ayah;
  final String surahNameAr;

  /// مقتطف حول الكلمة المطابقة (وسوم «»).
  final String snippet;
}

/// بداية جزء في المصحف — للفهرس (SPEC §7.3).
class JuzStart {
  const JuzStart({required this.juz, required this.page});

  final int juz;
  final int page;
}

/// عدد آيات كل سورة (١..١١٤) — مصحف المدينة، المجموع ٦٢٣٦.
const List<int> kSurahAyahCounts = [
  7,
  286,
  200,
  176,
  120,
  165,
  206,
  75,
  129,
  109,
  123,
  111,
  43,
  52,
  99,
  128,
  111,
  110,
  98,
  135,
  112,
  78,
  118,
  64,
  77,
  227,
  93,
  88,
  69,
  60,
  34,
  30,
  73,
  54,
  45,
  83,
  182,
  88,
  75,
  85,
  54,
  53,
  89,
  59,
  37,
  35,
  38,
  29,
  18,
  45,
  60,
  49,
  62,
  55,
  78,
  96,
  29,
  22,
  24,
  13,
  14,
  11,
  11,
  18,
  12,
  12,
  30,
  52,
  52,
  44,
  28,
  28,
  20,
  56,
  40,
  31,
  50,
  40,
  46,
  42,
  29,
  19,
  36,
  25,
  22,
  17,
  19,
  26,
  30,
  20,
  15,
  21,
  11,
  8,
  8,
  19,
  5,
  8,
  8,
  11,
  11,
  8,
  3,
  9,
  5,
  4,
  7,
  3,
  6,
  3,
  5,
  4,
  5,
  6,
];

/// (السورة، الآية) لمعرّف الآية العام ١..٦٢٣٦.
(int, int) surahAyahOf(int globalAyahId) {
  var remaining = globalAyahId;
  for (var i = 0; i < kSurahAyahCounts.length; i++) {
    if (remaining <= kSurahAyahCounts[i]) return (i + 1, remaining);
    remaining -= kSurahAyahCounts[i];
  }
  return (114, kSurahAyahCounts.last);
}
