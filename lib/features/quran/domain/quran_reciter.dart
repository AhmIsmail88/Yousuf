/// القرّاء المعتمدون للتحميل والاستماع.
///
/// مصدران:
/// - Islamic Network CDN (معرّف الآية العام ١..٦٢٣٦) — `docs/QURAN-AUDIO.md`.
/// - EveryAyah (سورة/آية بثلاث خانات) — للمصحف المعلّم (الحصري والمنشاوي
///   مع ترديد الأطفال)، وهو ما يُعرض في قسم الأطفال.
library;

import 'quran_models.dart';

enum ReciterSource { islamicNetwork, everyAyah }

class QuranReciter {
  const QuranReciter({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.bitrate,
    required this.style,
    this.source = ReciterSource.islamicNetwork,
    this.folder,
    this.teacher = false,
  });

  /// معرّف القارئ (ومسار الخادم لـ Islamic Network).
  final String id;

  /// الاسم المعروض.
  final String nameAr;
  final String nameEn;

  /// جودة الملفات (kbps) — تختلف بين القرّاء على الخادم.
  final int bitrate;

  /// مرتل | مجود | معلّم
  final String style;

  final ReciterSource source;

  /// مجلد EveryAyah (لمصدر everyAyah فقط).
  final String? folder;

  /// المصحف المعلّم (تلقين للأطفال).
  final bool teacher;

  String name({required bool arabic}) => arabic ? nameAr : nameEn;

  /// وصف مختصر للعرض.
  String get subtitle => '$style · ${bitrate}kbps';

  /// رابط ملف الآية.
  Uri urlFor(int globalAyahId) {
    switch (source) {
      case ReciterSource.islamicNetwork:
        return Uri.parse(
          'https://cdn.islamic.network/quran/audio/$bitrate/$id/$globalAyahId.mp3',
        );
      case ReciterSource.everyAyah:
        final (surah, ayah) = surahAyahOf(globalAyahId);
        String three(int n) => n.toString().padLeft(3, '0');
        return Uri.parse(
          'https://everyayah.com/data/$folder/${three(surah)}${three(ayah)}.mp3',
        );
    }
  }
}

/// القرّاء المشهورون المتاحون في التطبيق — الأكثر شهرة أولاً.
const List<QuranReciter> kQuranReciters = [
  QuranReciter(
    id: 'ar.minshawi',
    nameAr: 'محمد صديق المنشاوي',
    nameEn: 'Muhammad Siddiq al-Minshawi',
    bitrate: 128,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.abdulbasitmurattal',
    nameAr: 'عبد الباسط عبد الصمد',
    nameEn: 'Abdul Basit Abdus Samad',
    bitrate: 64,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.abdurrahmaansudais',
    nameAr: 'عبد الرحمن السديس',
    nameEn: 'Abdur-Rahman as-Sudais',
    bitrate: 64,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.mahermuaiqly',
    nameAr: 'ماهر المعيقلي',
    nameEn: 'Maher al-Muaiqly',
    bitrate: 128,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.husary',
    nameAr: 'محمود خليل الحصري',
    nameEn: 'Mahmoud Khalil al-Husary',
    bitrate: 128,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.saoodshuraym',
    nameAr: 'سعود الشريم',
    nameEn: 'Saud ash-Shuraym',
    bitrate: 64,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.muhammadayyoub',
    nameAr: 'محمد أيوب',
    nameEn: 'Muhammad Ayyub',
    bitrate: 128,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.shaatree',
    nameAr: 'أبو بكر الشاطري',
    nameEn: 'Abu Bakr ash-Shatri',
    bitrate: 128,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.hudhaify',
    nameAr: 'علي الحذيفي',
    nameEn: 'Ali al-Hudhaify',
    bitrate: 128,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.ahmedajamy',
    nameAr: 'أحمد بن علي العجمي',
    nameEn: 'Ahmad al-Ajmy',
    bitrate: 128,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.aymanswoaid',
    nameAr: 'أيمن سويد',
    nameEn: 'Ayman Suwayd',
    bitrate: 64,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.abdullahbasfar',
    nameAr: 'عبد الله بصفر',
    nameEn: 'Abdullah Basfar',
    bitrate: 64,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.ibrahimakhbar',
    nameAr: 'إبراهيم الأخضر',
    nameEn: 'Ibrahim al-Akhdar',
    bitrate: 32,
    style: 'مرتل',
  ),
  QuranReciter(
    id: 'ar.husarymujawwad',
    nameAr: 'محمود خليل الحصري',
    nameEn: 'Al-Husary (mujawwad)',
    bitrate: 128,
    style: 'مجود',
  ),
  QuranReciter(
    id: 'ar.minshawimujawwad',
    nameAr: 'محمد صديق المنشاوي',
    nameEn: 'Al-Minshawi (mujawwad)',
    bitrate: 64,
    style: 'مجود',
  ),
  // المصحف المعلّم — للأطفال (تلقين وترديد).
  QuranReciter(
    id: 'everyayah.husary_muallim',
    nameAr: 'الحصري — المصحف المعلّم',
    nameEn: 'Al-Husary (teaching)',
    bitrate: 128,
    style: 'معلّم',
    source: ReciterSource.everyAyah,
    folder: 'Husary_Muallim_128kbps',
    teacher: true,
  ),
  QuranReciter(
    id: 'everyayah.minshawi_teacher',
    nameAr: 'المنشاوي — مع ترديد الأطفال',
    nameEn: 'Al-Minshawi (with children)',
    bitrate: 128,
    style: 'معلّم',
    source: ReciterSource.everyAyah,
    folder: 'Minshawy_Teacher_128kbps',
    teacher: true,
  ),
];

/// قرّاء المصحف المعلّم (قسم الأطفال).
List<QuranReciter> get kTeacherReciters =>
    kQuranReciters.where((reciter) => reciter.teacher).toList(growable: false);

/// يبحث عن قارئ بالمعرّف، ويعيد الأول إن لم يوجد.
QuranReciter reciterById(String? id) => kQuranReciters.firstWhere(
  (reciter) => reciter.id == id,
  orElse: () => kQuranReciters.first,
);
