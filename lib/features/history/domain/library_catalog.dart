/// كتب المكتبة (الأذكار، المتون، السيرة والتاريخ…): ملف SQLite مضغوط لكل كتاب على Hugging Face،
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
    required this.section,
    required this.bytes,
    required this.sha256,
    required this.pages,
  });

  final String slug;
  final String title;
  final String author;

  /// سيرة | تاريخ | علوم القرآن …
  final String category;

  /// تبويب المكتبة الذي يظهر فيه ([librarySections]).
  final String section;

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
    section: 'السيرة والتاريخ',
    bytes: 1047705,
    sha256: 'adec2b83fe37f5a3999bb25ff39468c02029201a3faf00217b1eb164a24ccb64',
    pages: 1407,
  ),
  LibraryBook(
    slug: 'zad_almaad',
    title: 'زاد المعاد في هدي خير العباد',
    author: 'ابن قيم الجوزية (ت ٧٥١هـ)',
    category: 'سيرة وهدي',
    section: 'السيرة والتاريخ',
    bytes: 2026968,
    sha256: '44da81af60aff2a2f21feff16f354067bf1a758f37b66101709c7ee4561ee922',
    pages: 2628,
  ),
  LibraryBook(
    slug: 'bidaya',
    title: 'البداية والنهاية',
    author: 'ابن كثير (ت ٧٧٤هـ)',
    category: 'تاريخ',
    section: 'السيرة والتاريخ',
    bytes: 5451898,
    sha256: 'df4d0bcc75811e1ebc4f4333892e7a9c3877fbad41b56fd81352c34af6267a58',
    pages: 4918,
  ),
  LibraryBook(
    slug: 'tarikh_tabari',
    title: 'تاريخ الأمم والملوك (تاريخ الطبري)',
    author: 'محمد بن جرير الطبري (ت ٣١٠هـ)',
    category: 'تاريخ',
    section: 'السيرة والتاريخ',
    bytes: 4987078,
    sha256: 'cf6211700f397163b62765b815a54109a42f443b8321c2b452aa842e461de048',
    pages: 6431,
  ),
  LibraryBook(
    slug: 'alkamil',
    title: 'الكامل في التاريخ',
    author: 'ابن الأثير (ت ٦٣٠هـ)',
    category: 'تاريخ',
    section: 'السيرة والتاريخ',
    bytes: 5208944,
    sha256: 'ad1049a376fe70c79751585565cb6ba2bc5e592595c232431a926b1525047501',
    pages: 6163,
  ),
  LibraryBook(
    slug: 'asbab_suyuti',
    title: 'لباب النقول في أسباب النزول',
    author: 'جلال الدين السيوطي (ت ٩١١هـ)',
    category: 'علوم القرآن',
    section: 'علوم القرآن',
    bytes: 144096,
    sha256: 'a4fafe46ffb6ebe5b8ded2abc805ba2b6b7e89a969aca5a96b9e873b505b6274',
    pages: 218,
  ),
  LibraryBook(
    slug: 'rahiq_makhtum',
    title: 'الرحيق المختوم',
    author: 'صفي الرحمن المباركفوري',
    category: 'سيرة',
    section: 'السيرة والتاريخ',
    bytes: 412913,
    sha256: '0012437800c7451e980e7cefc96066765bb064a9abb82b1c0db3299ae2a64405',
    pages: 458,
  ),
  LibraryBook(
    slug: 'adhkar_nawawi',
    title: 'الأذكار',
    author: 'الإمام النووي (ت ٦٧٦هـ)',
    category: 'أذكار',
    section: 'الأذكار',
    bytes: 357208,
    sha256: '163a528aec89b0551d406826d4d759dd9f89c25496bac685c71434ceeeabcecd',
    pages: 411,
  ),
  LibraryBook(
    slug: 'kalim_tayyib',
    title: 'الكلم الطيب',
    author: 'ابن تيمية (ت ٧٢٨هـ)',
    category: 'أذكار',
    section: 'الأذكار',
    bytes: 32314,
    sha256: '4c43c04da1ce452e3abc2d2df76cbc68adedcd88473b6e766e46379eee8caf45',
    pages: 88,
  ),
  LibraryBook(
    slug: 'wabil_sayyib',
    title: 'الوابل الصيب من الكلم الطيب',
    author: 'ابن قيم الجوزية (ت ٧٥١هـ)',
    category: 'أذكار',
    section: 'الأذكار',
    bytes: 118892,
    sha256: 'dddd35230cc38f242b4f5f36daea3a25406ac09e8e788667a6b03ac50f37c6a7',
    pages: 148,
  ),
  LibraryBook(
    slug: 'why_they_hate_him',
    title: 'لماذا يكرهونه؟ الأصول الفكرية لموقف الغرب من نبي الإسلام',
    author: 'د. باسم خفاجي',
    category: 'الإسلام والغرب',
    section: 'الإسلام والغرب',
    bytes: 78641,
    sha256: '134f741a9c37854f12c44aa19a3bdaff257b37eb7e702783da3813c57e4360e0',
    pages: 110,
  ),
  LibraryBook(
    slug: 'orientalism_said',
    title: 'الاستشراق: المفاهيم الغربية للشرق',
    author: 'إدوارد سعيد · ترجمة محمد عناني',
    category: 'الإسلام والغرب',
    section: 'الإسلام والغرب',
    bytes: 490418,
    sha256: '12502221ee27dba89c2dfd94d9af6448e5ceae47710d9cd321db00ad684429d2',
    pages: 469,
  ),
  LibraryBook(
    slug: 'heroes_carlyle',
    title: 'الأبطال وعبادة البطولة',
    author: 'توماس كارليل · ترجمة محمد السباعي',
    category: 'الإسلام والغرب',
    section: 'الإسلام والغرب',
    bytes: 156176,
    sha256: 'fb85e782786e10c1ffd177f06c8b5ea9ae7be8df3b43091599c822c90adcf65d',
    pages: 192,
  ),
  LibraryBook(
    slug: 'islam_christianity',
    title: 'الإسلام والمسيحية: من التنافس والتصادم إلى آفاق الحوار والتفاهم',
    author: 'أليكسي جورافيسكي',
    category: 'الإسلام والغرب',
    section: 'الإسلام والغرب',
    bytes: 204587,
    sha256: '22a87b9e96043c5e80b53de27ebc4fe67577f991e7a39f0e8f4ecc8e92cf8641',
    pages: 202,
  ),
  LibraryBook(
    slug: 'europe_islam_djait',
    title: 'أوروبا والإسلام: صدام الثقافة والحداثة',
    author: 'هشام جعيط',
    category: 'الإسلام والغرب',
    section: 'الإسلام والغرب',
    bytes: 151468,
    sha256: 'a963efb396643904b5ef9dfceb6d9a76e55c618ff8572ebe1e8c125a94a34be1',
    pages: 130,
  ),
  LibraryBook(
    slug: 'islam_influence_europe',
    title: 'تأثير الإسلام في أوروبا العصور الوسطى',
    author: 'وليام مونتغمري واط · ترجمة سارة الذيب',
    category: 'الإسلام والغرب',
    section: 'الإسلام والغرب',
    bytes: 131261,
    sha256: 'da6550f7b430e9bd40b649128c53e352fee0b7ead3efd6ea7e1e8b61b286d6f2',
    pages: 172,
  ),
  LibraryBook(
    slug: 'west_muslim_world',
    title: 'الغرب والعالم الإسلامي: البحث عن بداية جديدة',
    author: 'أنطوني ت. سوليفان · ترجمة مروان حمدان',
    category: 'الإسلام والغرب',
    section: 'الإسلام والغرب',
    bytes: 14054,
    sha256: 'd0eaec15bf489475cf26d2df1a33a05fb6ccc15e59f89103170f33eb839f281b',
    pages: 11,
  ),
];

/// تبويبات المكتبة بالترتيب. «المتون» فيه تحفة الأطفال (مضمّنة في التطبيق)
/// إلى أن تُضاف متون للتنزيل. كتاب جديد يأخذ تبويبه من حقل [LibraryBook.section].
const List<String> librarySections = [
  'الأذكار',
  'المتون',
  'السيرة والتاريخ',
  'الإسلام والغرب',
  'علوم القرآن',
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
