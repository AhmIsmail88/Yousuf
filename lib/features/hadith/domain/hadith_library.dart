/// مكتبة الحديث القابلة للتنزيل: الكتب الكبيرة لا تُشحن مع التطبيق، بل
/// يُنزَّل كل كتاب عند الطلب (ملف SQLite مضغوط) من مستودع المشروع على
/// Hugging Face ويُتحقق من بصمته. تُبنى بـ `tools/content_builder/hadith_books.py`
/// من fawazahmed0/hadith-api (Unlicense — ملكية عامة).
library;

/// مكان ملفات الكتب — يمكن تغييره وقت البناء:
/// `--dart-define=HADITH_BOOKS_URL=...` (ينتهي بـ /).
const String hadithBooksBaseUrl = String.fromEnvironment(
  'HADITH_BOOKS_URL',
  defaultValue:
      'https://huggingface.co/datasets/Ahm20/yousuf-hadith/resolve/main/',
);

/// كتاب في المكتبة القابلة للتنزيل.
class HadithCollection {
  const HadithCollection({
    required this.slug,
    required this.nameAr,
    required this.nameEn,
    required this.bytes,
    required this.sha256,
    required this.count,
    required this.graded,
  });

  final String slug;
  final String nameAr;
  final String nameEn;

  /// حجم الملف المضغوط المنزَّل.
  final int bytes;

  /// بصمة SHA-256 للملف المضغوط — يُرفض أي ملف لا يطابقها.
  final String sha256;
  final int count;

  /// هل لأحاديثه درجات (السنن والموطأ)؟ الصحيحان بلا درجات.
  final bool graded;

  String get fileName => '$slug.sqlite.gz';
  String get url => '$hadithBooksBaseUrl$fileName';
  String name({required bool arabic}) => arabic ? nameAr : nameEn;
}

/// الكتب التسعة (ناتج `hadith_books.py books` — catalog.json).
const List<HadithCollection> hadithCatalog = [
  HadithCollection(
    slug: 'bukhari',
    nameAr: 'صحيح البخاري',
    nameEn: 'Sahih al-Bukhari',
    bytes: 2379568,
    sha256: '1a34221b35eb90a58761180f5da132670b6bc75af60016a69e7ed25b1e20badb',
    count: 7580,
    graded: false,
  ),
  HadithCollection(
    slug: 'muslim',
    nameAr: 'صحيح مسلم',
    nameEn: 'Sahih Muslim',
    bytes: 1972432,
    sha256: 'e68581322c664e050584f32e2461603c581da6cd5d3056127c56348ad581bdbc',
    count: 7360,
    graded: false,
  ),
  HadithCollection(
    slug: 'abudawud',
    nameAr: 'سنن أبي داود',
    nameEn: 'Sunan Abi Dawud',
    bytes: 1753038,
    sha256: 'e25e6b222ec6c21321b18c2b1d34eb697a7413713496af124053ef4f50b4402e',
    count: 5272,
    graded: true,
  ),
  HadithCollection(
    slug: 'tirmidhi',
    nameAr: 'جامع الترمذي',
    nameEn: 'Jami at-Tirmidhi',
    bytes: 1590576,
    sha256: '3ce48ad30ded30a6d126838898c9afd94eb8900e043f1ad1c92e3bf984692fe3',
    count: 3924,
    graded: true,
  ),
  HadithCollection(
    slug: 'nasai',
    nameAr: 'سنن النسائي',
    nameEn: 'Sunan an-Nasai',
    bytes: 1509093,
    sha256: '1fac3948874b818551af571239a411648fbde54fdc0e1cf41534170fe57e1410',
    count: 5679,
    graded: true,
  ),
  HadithCollection(
    slug: 'ibnmajah',
    nameAr: 'سنن ابن ماجه',
    nameEn: 'Sunan Ibn Majah',
    bytes: 1270354,
    sha256: 'b4a333bdd392efd2ce931b666aa39f2668f69138b8c61fc94e2d9943dc7e1fc7',
    count: 4338,
    graded: true,
  ),
  HadithCollection(
    slug: 'malik',
    nameAr: 'موطأ مالك',
    nameEn: 'Muwatta Malik',
    bytes: 546453,
    sha256: 'a4a26f8f1bc0be048ae41a619f5de22770980df47c8c066b9692627d3497f2ab',
    count: 1829,
    graded: true,
  ),
];

HadithCollection? hadithCollection(String slug) {
  for (final book in hadithCatalog) {
    if (book.slug == slug) return book;
  }
  return null;
}

/// باب/كتاب داخل كتاب الحديث (اسمه في المصدر إنجليزي فقط).
class HadithSection {
  const HadithSection({
    required this.id,
    required this.nameEn,
    required this.total,
    this.first,
    this.last,
  });

  final int id;
  final String nameEn;
  final int total;
  final num? first;
  final num? last;
}

/// درجة الحديث عند أحد المحققين.
class HadithGrade {
  const HadithGrade({
    required this.gradeAr,
    required this.raw,
    required this.category,
    required this.grader,
  });

  /// الدرجة بالمصطلح العربي (أو نصها الأصلي إن لم تُترجم كاملة).
  final String gradeAr;
  final String raw;

  /// sahih | hasan | daif | mawdu | other — للون الشارة.
  final String category;
  final String grader;
}

/// حديث من كتاب منزَّل.
class BookHadith {
  const BookHadith({
    required this.id,
    required this.number,
    required this.sectionId,
    required this.text,
    this.grades = const [],
  });

  final int id;

  /// رقم الحديث في الكتاب (قد يكون ١٢٣٤٫٢ في بعض الطبعات).
  final String number;
  final int sectionId;
  final String text;
  final List<HadithGrade> grades;
}
