/// نماذج حساب المواقيت — Dart خالص بلا اعتماد على Flutter (SPEC §2).
library;

/// طرق الحساب المعتمدة (CONTRACTS §2).
///
/// «طهران» محسوبة بالمعاملات نفسها في Dart وKotlin (فجر ١٧٫٧° وعشاء ١٤°،
/// والمغرب عند الغروب) حتى يطابق الوقت المعروض وقت الأذان تماماً.
/// «مخصصة» حُذفت (لا واجهة لضبط زواياها)؛ القيمة المحفوظة تُقرأ كأم القرى.
enum CalculationMethod {
  ummAlQura('umm_al_qura', 'أم القرى', 'Umm al-Qura'),
  egyptian(
    'egyptian',
    'الهيئة المصرية العامة للمساحة',
    'Egyptian General Authority of Survey',
  ),
  mwl('mwl', 'رابطة العالم الإسلامي', 'Muslim World League'),
  isna('isna', 'الجمعية الإسلامية لأمريكا الشمالية', 'ISNA (North America)'),
  karachi('karachi', 'جامعة العلوم الإسلامية بكراتشي', 'University of Karachi'),
  kuwait('kuwait', 'الكويت', 'Kuwait'),
  qatar('qatar', 'قطر', 'Qatar'),
  dubai('dubai', 'دبي', 'Dubai'),
  singapore('singapore', 'سنغافورة', 'Singapore'),
  turkey('turkey', 'تركيا (ديانت)', 'Turkey (Diyanet)'),
  tehran('tehran', 'طهران', 'Tehran');

  const CalculationMethod(this.id, this.labelAr, this.labelEn);

  /// المعرّف المستخدم في AdhanConfig والملفات.
  final String id;

  /// الاسم العربي للعرض.
  final String labelAr;

  /// الاسم الإنجليزي للعرض.
  final String labelEn;

  String label({required bool arabic}) => arabic ? labelAr : labelEn;

  /// الطرق المعروضة للاختيار.
  static const List<CalculationMethod> selectable = values;

  static CalculationMethod fromId(String? id) => values.firstWhere(
    (method) => method.id == id,
    orElse: () => CalculationMethod.ummAlQura,
  );
}

/// مذهب العصر: ظل المثل (الجمهور) أو المثلين (حنفي).
enum AsrMadhab {
  shafi('shafi', 'الجمهور (شافعي)', 'Standard (Shafii)'),
  hanafi('hanafi', 'حنفي', 'Hanafi');

  const AsrMadhab(this.id, this.labelAr, this.labelEn);

  final String id;
  final String labelAr;
  final String labelEn;

  String label({required bool arabic}) => arabic ? labelAr : labelEn;

  static AsrMadhab fromId(String? id) => values.firstWhere(
    (madhab) => madhab.id == id,
    orElse: () => AsrMadhab.shafi,
  );
}

/// قاعدة العرض العالي (ما فوق 48°).
enum HighLatRule {
  middleOfTheNight('middle_of_the_night', 'منتصف الليل', 'Middle of the night'),
  seventhOfTheNight(
    'seventh_of_the_night',
    'سُبع الليل',
    'Seventh of the night',
  ),
  twilightAngle('twilight_angle', 'زاوية الشفق', 'Twilight angle');

  const HighLatRule(this.id, this.labelAr, this.labelEn);

  final String id;
  final String labelAr;
  final String labelEn;

  String label({required bool arabic}) => arabic ? labelAr : labelEn;

  static HighLatRule fromId(String? id) => values.firstWhere(
    (rule) => rule.id == id,
    orElse: () => HighLatRule.middleOfTheNight,
  );
}

/// أسماء الصلوات الموحدة (CONTRACTS §3).
enum PrayerName {
  fajr('fajr', 'الفجر', 'Fajr'),
  sunrise('sunrise', 'الشروق', 'Sunrise'),
  dhuhr('dhuhr', 'الظهر', 'Dhuhr'),
  asr('asr', 'العصر', 'Asr'),
  maghrib('maghrib', 'المغرب', 'Maghrib'),
  isha('isha', 'العشاء', 'Isha');

  const PrayerName(this.id, this.labelAr, this.labelEn);

  final String id;
  final String labelAr;
  final String labelEn;

  String label({required bool arabic}) => arabic ? labelAr : labelEn;

  static PrayerName fromId(String? id) => values.firstWhere(
    (prayer) => prayer.id == id,
    orElse: () => PrayerName.fajr,
  );
}

/// تعديلات بالدقائق لكل صلاة (−30..+30).
class PrayerAdjustments {
  const PrayerAdjustments({
    this.fajr = 0,
    this.sunrise = 0,
    this.dhuhr = 0,
    this.asr = 0,
    this.maghrib = 0,
    this.isha = 0,
  });

  final int fajr;
  final int sunrise;
  final int dhuhr;
  final int asr;
  final int maghrib;
  final int isha;

  bool get isZero =>
      fajr == 0 &&
      sunrise == 0 &&
      dhuhr == 0 &&
      asr == 0 &&
      maghrib == 0 &&
      isha == 0;

  Map<String, int> toMap() => {
    'fajr': fajr,
    'sunrise': sunrise,
    'dhuhr': dhuhr,
    'asr': asr,
    'maghrib': maghrib,
    'isha': isha,
  };

  factory PrayerAdjustments.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PrayerAdjustments();
    int read(String key) => (map[key] as num?)?.toInt() ?? 0;
    return PrayerAdjustments(
      fajr: read('fajr'),
      sunrise: read('sunrise'),
      dhuhr: read('dhuhr'),
      asr: read('asr'),
      maghrib: read('maghrib'),
      isha: read('isha'),
    );
  }
}

/// موقع الحساب: إحداثيات + منطقة زمنية (CONTRACTS §3).
class PrayerLocation {
  const PrayerLocation({
    required this.latitude,
    required this.longitude,
    required this.timezoneId,
    this.cityName,
    this.cityNameEn,
    this.fromGps = false,
  });

  /// الرياض — الافتراضي عند أول تشغيل (SPEC §7.1).
  static const riyadh = PrayerLocation(
    latitude: 24.7136,
    longitude: 46.6753,
    timezoneId: 'Asia/Riyadh',
    cityName: 'الرياض',
    cityNameEn: 'Riyadh',
  );

  final double latitude;
  final double longitude;
  final String timezoneId;

  /// اسم المدينة (عربي) — لموقع GPS هو اسم أقرب مدينة.
  final String? cityName;

  /// اسم المدينة بالإنجليزية.
  final String? cityNameEn;

  /// هل الإحداثيات من GPS الجهاز (لا مركز المدينة)؟
  final bool fromGps;

  /// اسم العرض بلغة الواجهة.
  String? displayName({required bool arabic}) =>
      arabic ? cityName : (cityNameEn ?? cityName);

  Map<String, Object?> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'timezoneId': timezoneId,
    'cityName': cityName,
    'cityNameEn': cityNameEn,
    'fromGps': fromGps,
  };

  factory PrayerLocation.fromMap(Map<String, dynamic> map) => PrayerLocation(
    latitude: (map['latitude'] as num).toDouble(),
    longitude: (map['longitude'] as num).toDouble(),
    timezoneId: map['timezoneId'] as String? ?? 'Asia/Riyadh',
    cityName: map['cityName'] as String?,
    cityNameEn: map['cityNameEn'] as String?,
    fromGps: map['fromGps'] as bool? ?? false,
  );
}

/// مواقيت يوم كامل — نصوص "HH:mm" بتوقيت الموقع.
class PrayerTimesDay {
  const PrayerTimesDay({
    required this.date,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
    this.duha,
    this.middleOfTheNight,
    this.lastThirdOfTheNight,
  });

  /// التاريخ المدني (سنة/شهر/يوم فقط).
  final DateTime date;

  final String fajr;
  final String sunrise;
  final String dhuhr;
  final String asr;
  final String maghrib;
  final String isha;

  /// بداية الضحى (شروق + 15 دقيقة) — للعرض فقط، لا تُجدول.
  final String? duha;

  /// منتصف الليل الشرعي.
  final String? middleOfTheNight;

  /// الثلث الأخير من الليل.
  final String? lastThirdOfTheNight;

  /// الأوقات الستة بصيغة CONTRACTS §4.
  Map<String, String> toTimesMap() => {
    'fajr': fajr,
    'sunrise': sunrise,
    'dhuhr': dhuhr,
    'asr': asr,
    'maghrib': maghrib,
    'isha': isha,
  };

  /// وقت صلاة بالاسم الموحد.
  String timeFor(PrayerName prayer) => switch (prayer) {
    PrayerName.fajr => fajr,
    PrayerName.sunrise => sunrise,
    PrayerName.dhuhr => dhuhr,
    PrayerName.asr => asr,
    PrayerName.maghrib => maghrib,
    PrayerName.isha => isha,
  };
}
