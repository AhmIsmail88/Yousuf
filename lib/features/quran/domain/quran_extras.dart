/// التفاسير والترجمات القابلة للتنزيل: ملف SQLite مضغوط لكل مصدر على
/// Hugging Face، يُتحقق من بصمته، ثم يُقرأ دون إنترنت. تُبنى بـ
/// `tools/content_builder/quran_extras.py` (المصادر وتراخيصها هناك).
library;

/// مكان الملفات — يمكن تغييره وقت البناء: `--dart-define=QURAN_EXTRAS_URL=...`.
const String quranExtrasBaseUrl = String.fromEnvironment(
  'QURAN_EXTRAS_URL',
  defaultValue:
      'https://huggingface.co/datasets/Ahm20/yousuf-tafsir/resolve/main/',
);

/// tafsir | translation | asbab (أسباب النزول — تُعرض مع الواحدي).
enum QuranExtraKind { tafsir, translation, asbab }

class QuranExtra {
  const QuranExtra({
    required this.slug,
    required this.kind,
    required this.nameAr,
    required this.nameEn,
    required this.language,
    required this.author,
    required this.bytes,
    required this.sha256,
  });

  final String slug;
  final QuranExtraKind kind;
  final String nameAr;
  final String nameEn;

  /// لغة النص (ar | en | tr | ur) — لاتجاه السطر.
  final String language;
  final String author;

  /// حجم الملف المضغوط المنزَّل.
  final int bytes;

  /// بصمة SHA-256 للملف المضغوط — يُرفض أي ملف لا يطابقها.
  final String sha256;

  String get fileName => '$slug.sqlite.gz';
  String get url => '$quranExtrasBaseUrl$fileName';
  bool get rtl => language == 'ar' || language == 'ur';
  String name({required bool arabic}) => arabic ? nameAr : nameEn;
}

/// ناتج `quran_extras.py extras` (catalog.json).
const List<QuranExtra> quranExtrasCatalog = [
  QuranExtra(
    slug: 'ibn_kathir',
    kind: QuranExtraKind.tafsir,
    nameAr: 'تفسير ابن كثير',
    nameEn: 'Tafsir Ibn Kathir',
    language: 'ar',
    author: 'إسماعيل بن عمر بن كثير (ت ٧٧٤هـ)',
    bytes: 5405273,
    sha256: '428a9465094ad36bbbc37374a469fca2a044e0d53467af17220b2e93a7936bd8',
  ),
  QuranExtra(
    slug: 'tabari',
    kind: QuranExtraKind.tafsir,
    nameAr: 'جامع البيان — تفسير الطبري',
    nameEn: 'Tafsir al-Tabari',
    language: 'ar',
    author: 'محمد بن جرير الطبري (ت ٣١٠هـ)',
    bytes: 8432437,
    sha256: 'd91292e70d3b0560bf6a93dd4fee0f3291213140bf088cbc6f5751609386ebd1',
  ),
  QuranExtra(
    slug: 'en_pickthall',
    kind: QuranExtraKind.translation,
    nameAr: 'الإنجليزية — Pickthall',
    nameEn: 'English — Pickthall',
    language: 'en',
    author: 'Marmaduke Pickthall (d. 1936)',
    bytes: 366131,
    sha256: '0a479055766058c7a29a5664494e4fb3f087f96902313e39ee6e4276032f1c50',
  ),
  QuranExtra(
    slug: 'tr_elmalili',
    kind: QuranExtraKind.translation,
    nameAr: 'التركية — Elmalılı Hamdi Yazır',
    nameEn: 'Turkish — Elmalılı Hamdi Yazır',
    language: 'tr',
    author: 'Elmalılı Hamdi Yazır (ö. 1942)',
    bytes: 400504,
    sha256: '69f6c7eba6ac3a47576317e3c892cdb20ae52be558320f49bc236b796535937f',
  ),
  QuranExtra(
    slug: 'ur_junagarhi',
    kind: QuranExtraKind.translation,
    nameAr: 'الأردية — محمد جوناگڑھی',
    nameEn: 'Urdu — Muhammad Junagarhi',
    language: 'ur',
    author: 'محمد جوناگڑھی (1941)',
    bytes: 450125,
    sha256: '94f996ce82261fdffd46085625464a23e520e9e7d283cbaed66294959d9033e9',
  ),
  QuranExtra(
    slug: 'asbab_suyuti',
    kind: QuranExtraKind.asbab,
    nameAr: 'لباب النقول — للسيوطي',
    nameEn: 'Lubab al-Nuqul — al-Suyuti',
    language: 'ar',
    author: 'جلال الدين السيوطي (ت ٩١١هـ)',
    bytes: 101269,
    sha256: '1a751291c399b4b5c16bdfd6601c5d591cd4192e480815a2dead50e6ea710410',
  ),
];
