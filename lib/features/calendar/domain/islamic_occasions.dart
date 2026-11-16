/// المناسبات الإسلامية الثابتة في التقويم الهجري (SPEC §7.7).
///
/// اقتصرنا على المناسبات المتفق عليها وأيام الصيام المسنونة المشهورة،
/// دون المختلف فيها. التواريخ هجرية، وتُحوَّل للميلادي بأم القرى مع إزاحة
/// المستخدم (±٢).
library;

enum OccasionKind {
  /// عيد أو يوم عظيم.
  feast,

  /// صيام مسنون.
  fasting,

  /// موسم عبادة (العشر، رمضان).
  season,
}

class IslamicOccasion {
  const IslamicOccasion({
    required this.month,
    required this.day,
    required this.titleAr,
    required this.titleEn,
    required this.kind,
    this.noteAr,
    this.noteEn,
  });

  final int month;
  final int day;
  final String titleAr;
  final String titleEn;
  final OccasionKind kind;
  final String? noteAr;
  final String? noteEn;

  String title({required bool arabic}) => arabic ? titleAr : titleEn;

  String? note({required bool arabic}) => arabic ? noteAr : noteEn;
}

const List<IslamicOccasion> kIslamicOccasions = [
  IslamicOccasion(
    month: 1,
    day: 1,
    titleAr: 'رأس السنة الهجرية',
    titleEn: 'Islamic New Year',
    kind: OccasionKind.season,
  ),
  IslamicOccasion(
    month: 1,
    day: 9,
    titleAr: 'تاسوعاء',
    titleEn: 'Tasua',
    kind: OccasionKind.fasting,
    noteAr: 'يُستحب صيامه مع عاشوراء',
    noteEn: 'Recommended to fast with Ashura',
  ),
  IslamicOccasion(
    month: 1,
    day: 10,
    titleAr: 'يوم عاشوراء',
    titleEn: 'Day of Ashura',
    kind: OccasionKind.fasting,
    noteAr: 'صيامه يكفّر السنة الماضية',
    noteEn: 'Fasting it expiates the previous year',
  ),
  IslamicOccasion(
    month: 9,
    day: 1,
    titleAr: 'أول رمضان',
    titleEn: 'First of Ramadan',
    kind: OccasionKind.season,
    noteAr: 'بحسب التقويم — العبرة برؤية الهلال',
    noteEn: 'By calendar — subject to moon sighting',
  ),
  IslamicOccasion(
    month: 9,
    day: 21,
    titleAr: 'العشر الأواخر',
    titleEn: 'Last ten nights',
    kind: OccasionKind.season,
    noteAr: 'تحرّوا ليلة القدر في الوتر من العشر الأواخر',
    noteEn: 'Seek Laylat al-Qadr in the odd nights',
  ),
  IslamicOccasion(
    month: 10,
    day: 1,
    titleAr: 'عيد الفطر',
    titleEn: 'Eid al-Fitr',
    kind: OccasionKind.feast,
  ),
  IslamicOccasion(
    month: 10,
    day: 2,
    titleAr: 'صيام ستٍّ من شوال',
    titleEn: 'Six days of Shawwal',
    kind: OccasionKind.fasting,
    noteAr: 'من صام رمضان ثم أتبعه ستاً من شوال',
    noteEn: 'Fasting six days after Ramadan',
  ),
  IslamicOccasion(
    month: 12,
    day: 1,
    titleAr: 'العشر الأوائل من ذي الحجة',
    titleEn: 'First ten days of Dhu al-Hijjah',
    kind: OccasionKind.season,
  ),
  IslamicOccasion(
    month: 12,
    day: 8,
    titleAr: 'يوم التروية',
    titleEn: 'Day of Tarwiyah',
    kind: OccasionKind.season,
  ),
  IslamicOccasion(
    month: 12,
    day: 9,
    titleAr: 'يوم عرفة',
    titleEn: 'Day of Arafah',
    kind: OccasionKind.fasting,
    noteAr: 'صيامه لغير الحاج يكفّر سنتين',
    noteEn: 'Fasting it (for non-pilgrims) expiates two years',
  ),
  IslamicOccasion(
    month: 12,
    day: 10,
    titleAr: 'عيد الأضحى',
    titleEn: 'Eid al-Adha',
    kind: OccasionKind.feast,
  ),
  IslamicOccasion(
    month: 12,
    day: 11,
    titleAr: 'أيام التشريق',
    titleEn: 'Days of Tashreeq',
    kind: OccasionKind.feast,
    noteAr: '١١–١٣ ذي الحجة — لا صيام فيها',
    noteEn: '11–13 Dhu al-Hijjah — no fasting',
  ),
  IslamicOccasion(
    month: 12,
    day: 12,
    titleAr: 'أيام التشريق',
    titleEn: 'Days of Tashreeq',
    kind: OccasionKind.feast,
  ),
  IslamicOccasion(
    month: 12,
    day: 13,
    titleAr: 'أيام التشريق',
    titleEn: 'Days of Tashreeq',
    kind: OccasionKind.feast,
  ),
];

/// مناسبات يوم هجري.
List<IslamicOccasion> occasionsOn(int month, int day) => [
  for (final occasion in kIslamicOccasions)
    if (occasion.month == month && occasion.day == day) occasion,
];
