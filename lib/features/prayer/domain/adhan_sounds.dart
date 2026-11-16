/// كتالوج أصوات الأذان (SPEC §8).
///
/// يُعرض للمستخدم ما هو **موجود فعلاً** داخل الحزمة فقط
/// (`android/app/src/main/assets/adhan/<id>.mp3|ogg`) إضافة إلى
/// [kDefaultAdhanSound] الذي يشغّل التسجيل المؤقت (CC0). إضافة مؤذن جديد =
/// وضع ملفه بالمعرّف نفسه في الأصول بعد التحقق من ترخيصه.
library;

class AdhanSound {
  const AdhanSound(this.id, this.labelAr, this.labelEn, {this.downloadUrl});

  final String id;
  final String labelAr;
  final String labelEn;

  /// رابط تحميل اختياري — الصوت لا يُضمَّن في الحزمة بل يُحمَّل عند الطلب.
  final String? downloadUrl;

  bool get downloadable => downloadUrl != null;

  String label({required bool arabic}) => arabic ? labelAr : labelEn;
}

const String _aladhan = 'https://cdn.aladhan.com/audio/adhans';

/// الصوت الافتراضي — التسجيل المؤقت المضمّن.
const String kDefaultAdhanSound = 'default';

const List<AdhanSound> kAdhanSounds = [
  AdhanSound(kDefaultAdhanSound, 'الأذان الافتراضي', 'Default adhan'),
  // مضمّنة في الحزمة — تسجيلات قدّمها مالك التطبيق (انظر «المصادر»).
  AdhanSound('ali_mulla', 'علي أحمد ملا', 'Ali Ahmed Mulla'),
  AdhanSound('abdelbaset', 'عبد الباسط عبد الصمد', 'Abdul Basit Abdus Samad'),
  AdhanSound('husary', 'محمود خليل الحصري', 'Mahmoud Khalil al-Husary'),
  AdhanSound('menshawi', 'محمد صديق المنشاوي', 'Muhammad Siddiq al-Minshawi'),
  AdhanSound('rifaat', 'محمد رفعت', 'Muhammad Rifaat'),
  AdhanSound('banna', 'محمود علي البنا', 'Mahmoud Ali al-Banna'),
  // تسجيلات مرخّصة مضمّنة (Wikimedia Commons، CC BY-SA 4.0 — انظر «المصادر»).
  AdhanSound('aaqib_azeez', 'عاقب عزيز', 'Aaqib Azeez'),
  AdhanSound('commons_azan', 'أذان طويل مرتّل', 'Long melodic adhan'),
  // للتحميل عند الطلب من AlAdhan (Islamic Network) — صفحة «Download Adhans»:
  // https://aladhan.com/download-adhans
  AdhanSound(
    'mishary',
    'مشاري العفاسي',
    'Mishary Alafasy',
    downloadUrl: '$_aladhan/a9.mp3',
  ),
  AdhanSound(
    'mishary_2',
    'مشاري العفاسي (أذان آخر)',
    'Mishary Alafasy (another)',
    downloadUrl: '$_aladhan/a7.mp3',
  ),
  AdhanSound(
    'mishary_dubai',
    'مشاري العفاسي (قناة ون دبي)',
    "Mishary Alafasy (Dubai One TV)",
    downloadUrl: '$_aladhan/a4.mp3',
  ),
  AdhanSound(
    'nafees',
    'أحمد النفيس',
    'Ahmad al-Nafees',
    downloadUrl: '$_aladhan/a1.mp3',
  ),
  AdhanSound(
    'mansour_zahrani',
    'منصور الزهراني',
    'Mansour Al-Zahrani',
    downloadUrl: '$_aladhan/a11-mansour-al-zahrani.mp3',
  ),
  AdhanSound(
    'ozcan',
    'حافظ مصطفى أوزجان (تركيا)',
    'Hafiz Mustafa Özcan (Turkey)',
    downloadUrl: '$_aladhan/a2.mp3',
  ),
  // معرّفات محجوزة: تظهر فقط إن وُضع ملف مرخَّص بالاسم نفسه في الأصول.
  AdhanSound('makkah', 'الحرم المكي', 'Masjid al-Haram (Makkah)'),
  AdhanSound('madinah', 'المسجد النبوي', 'Masjid an-Nabawi (Madinah)'),
  AdhanSound('egypt', 'أذان مصري (الإذاعة)', 'Egyptian adhan'),
  AdhanSound('aqsa', 'المسجد الأقصى', 'Al-Aqsa Mosque'),
];

/// كل المعرّفات المعروفة (للتحقق عند القراءة من التخزين).
final Set<String> kAdhanSoundIds = {for (final s in kAdhanSounds) s.id};

AdhanSound adhanSoundById(String id) => kAdhanSounds.firstWhere(
  (sound) => sound.id == id,
  orElse: () => kAdhanSounds.first,
);

/// الأصوات القابلة للاختيار: الافتراضي + ما وُجد ملفه فعلاً.
List<AdhanSound> selectableAdhanSounds(Iterable<String> available) {
  final set = available.toSet();
  return [
    for (final sound in kAdhanSounds)
      if (sound.id == kDefaultAdhanSound || set.contains(sound.id)) sound,
  ];
}

/// الصوت الفعلي الذي سيُسمع: المختار إن توفّر ملفه، وإلا الافتراضي.
String effectiveAdhanSound(String id, Iterable<String> available) =>
    available.contains(id) ? id : kDefaultAdhanSound;

/// أصوات يمكن تحميلها ولم تُحمَّل بعد.
List<AdhanSound> downloadableAdhanSounds(Iterable<String> available) {
  final set = available.toSet();
  return [
    for (final sound in kAdhanSounds)
      if (sound.downloadable && !set.contains(sound.id)) sound,
  ];
}
