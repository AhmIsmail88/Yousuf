/// كتب المكتبة (السيرة والتاريخ): ملف SQLite مضغوط لكل كتاب على Hugging Face،
/// يُنزَّل مرة ويُتحقق من بصمته ثم يُقرأ دون إنترنت. تُبنى بـ
/// `tools/content_builder/library_books.py` (المصادر وتراخيصها هناك).
library;

/// مكان الملفات — يمكن تغييره وقت البناء: `--dart-define=LIBRARY_BOOKS_URL=...`.
const String libraryBooksBaseUrl = String.fromEnvironment(
  'LIBRARY_BOOKS_URL',
  defaultValue:
      'https://huggingface.co/datasets/Ahm20/yousuf-library/resolve/main/',
);

class LibraryBook {
  const LibraryBook({
    required this.slug,
    required this.title,
    required this.author,
    required this.category,
    required this.bytes,
    required this.sha256,
    required this.pages,
  });

  final String slug;
  final String title;
  final String author;

  /// سيرة | تاريخ | علوم القرآن …
  final String category;

  /// حجم الملف المضغوط المنزَّل.
  final int bytes;

  /// بصمة SHA-256 للملف المضغوط — يُرفض أي ملف لا يطابقها.
  final String sha256;
  final int pages;

  String get fileName => '$slug.sqlite.gz';
  String get url => '$libraryBooksBaseUrl$fileName';
}

/// ناتج `library_books.py` (catalog.json).
const List<LibraryBook> libraryCatalog = [
  LibraryBook(
    slug: 'sira_ibn_hisham',
    title: 'السيرة النبوية لابن هشام',
    author: 'عبد الملك بن هشام (ت ٢١٣هـ)',
    category: 'سيرة',
    bytes: 1047705,
    sha256: 'adec2b83fe37f5a3999bb25ff39468c02029201a3faf00217b1eb164a24ccb64',
    pages: 1407,
  ),
  LibraryBook(
    slug: 'zad_almaad',
    title: 'زاد المعاد في هدي خير العباد',
    author: 'ابن قيم الجوزية (ت ٧٥١هـ)',
    category: 'سيرة وهدي',
    bytes: 2026968,
    sha256: '44da81af60aff2a2f21feff16f354067bf1a758f37b66101709c7ee4561ee922',
    pages: 2628,
  ),
  LibraryBook(
    slug: 'bidaya',
    title: 'البداية والنهاية',
    author: 'ابن كثير (ت ٧٧٤هـ)',
    category: 'تاريخ',
    bytes: 5451898,
    sha256: 'df4d0bcc75811e1ebc4f4333892e7a9c3877fbad41b56fd81352c34af6267a58',
    pages: 4918,
  ),
  LibraryBook(
    slug: 'tarikh_tabari',
    title: 'تاريخ الأمم والملوك (تاريخ الطبري)',
    author: 'محمد بن جرير الطبري (ت ٣١٠هـ)',
    category: 'تاريخ',
    bytes: 4987078,
    sha256: 'cf6211700f397163b62765b815a54109a42f443b8321c2b452aa842e461de048',
    pages: 6431,
  ),
  LibraryBook(
    slug: 'alkamil',
    title: 'الكامل في التاريخ',
    author: 'ابن الأثير (ت ٦٣٠هـ)',
    category: 'تاريخ',
    bytes: 5208944,
    sha256: 'ad1049a376fe70c79751585565cb6ba2bc5e592595c232431a926b1525047501',
    pages: 6163,
  ),
  LibraryBook(
    slug: 'asbab_suyuti',
    title: 'لباب النقول في أسباب النزول',
    author: 'جلال الدين السيوطي (ت ٩١١هـ)',
    category: 'علوم القرآن',
    bytes: 144096,
    sha256: 'a4fafe46ffb6ebe5b8ded2abc805ba2b6b7e89a969aca5a96b9e873b505b6274',
    pages: 218,
  ),
  LibraryBook(
    slug: 'rahiq_makhtum',
    title: 'الرحيق المختوم',
    author: 'صفي الرحمن المباركفوري',
    category: 'سيرة',
    bytes: 412913,
    sha256: '0012437800c7451e980e7cefc96066765bb064a9abb82b1c0db3299ae2a64405',
    pages: 458,
  ),
];

/// فصل في كتاب منزَّل: أول صفحة فيه.
class LibraryChapter {
  const LibraryChapter({
    required this.title,
    required this.firstPage,
    this.volume,
  });

  final String title;
  final String? volume;

  /// رقم الصفحة في ترتيب الكتاب (يبدأ من ١).
  final int firstPage;
}

/// صفحة من كتاب منزَّل.
class LibraryPage {
  const LibraryPage({
    required this.index,
    required this.chapter,
    required this.text,
    this.volume,
    this.pageNum,
  });

  /// ترتيب الصفحة في الكتاب (يبدأ من ١).
  final int index;
  final String chapter;
  final String text;
  final String? volume;

  /// رقم الصفحة المطبوع.
  final String? pageNum;
}
