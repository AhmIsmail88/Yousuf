/// أدوات التاريخ العربي: أسماء الأيام والشهور الميلادية، والتحويل الهجري
/// (أم القرى) مع إزاحة يدوية ±2 يوم (SPEC §7.7).
library;

import 'package:hijri/hijri_calendar.dart';

/// أسماء الأيام بالعربية — مفتاحها [DateTime.weekday].
const arabicWeekdays = <int, String>{
  DateTime.monday: 'الإثنين',
  DateTime.tuesday: 'الثلاثاء',
  DateTime.wednesday: 'الأربعاء',
  DateTime.thursday: 'الخميس',
  DateTime.friday: 'الجمعة',
  DateTime.saturday: 'السبت',
  DateTime.sunday: 'الأحد',
};

/// أسماء الشهور الميلادية بالعربية.
const arabicMonths = <int, String>{
  1: 'يناير',
  2: 'فبراير',
  3: 'مارس',
  4: 'أبريل',
  5: 'مايو',
  6: 'يونيو',
  7: 'يوليو',
  8: 'أغسطس',
  9: 'سبتمبر',
  10: 'أكتوبر',
  11: 'نوفمبر',
  12: 'ديسمبر',
};

/// أسماء الشهور الهجرية بالعربية — بالصيغة المتعارف عليها.
const hijriMonths = <int, String>{
  1: 'محرم',
  2: 'صفر',
  3: 'ربيع الأول',
  4: 'ربيع الآخر',
  5: 'جمادى الأولى',
  6: 'جمادى الآخرة',
  7: 'رجب',
  8: 'شعبان',
  9: 'رمضان',
  10: 'شوال',
  11: 'ذو القعدة',
  12: 'ذو الحجة',
};

/// «الأربعاء ١١ نوفمبر ٢٠٢٦» — التاريخ الميلادي للعرض.
String formatGregorianDate(DateTime date) =>
    '${arabicWeekdays[date.weekday]} ${date.day} '
    '${arabicMonths[date.month]} ${date.year}';

/// تاريخ هجري جاهز للعرض.
class HijriDay {
  const HijriDay({required this.year, required this.month, required this.day});

  final int year;
  final int month;
  final int day;

  /// اسم الشهر بالعربية.
  String get monthName => hijriMonths[month] ?? '';

  /// «٣٠ جمادى الأولى ١٤٤٨هـ».
  String get formatted => '$day $monthName $yearهـ';

  /// هل هذا اليوم من الأيام البيض (١٣–١٥)؟ — للبطاقة الذكية وبند الصيام.
  bool get isWhiteDay => day >= 13 && day <= 15;
}

bool _hijriLocaleReady = false;

/// يحوّل تاريخاً ميلادياً إلى هجري (أم القرى) مع إزاحة بالأيام.
///
/// الإزاحة تسمح بمواءمة رؤية الهلال محلياً (SPEC §8: −2..+2).
/// يعيد null إن خرج التاريخ عن نطاق بيانات أم القرى في الحزمة.
HijriDay? hijriDay(DateTime gregorian, {int offsetDays = 0}) {
  if (!_hijriLocaleReady) {
    // أسماء الشهور لا تُستخدم من الحزمة (نستعمل جدولنا)، لكن ضبط اللغة
    // يمنع أي اعتماد على الافتراضي الإنجليزي.
    HijriCalendar.setLocal('ar');
    _hijriLocaleReady = true;
  }
  final shifted = DateTime(
    gregorian.year,
    gregorian.month,
    gregorian.day + offsetDays,
  );
  try {
    final hijri = HijriCalendar.fromDate(shifted);
    return HijriDay(year: hijri.hYear, month: hijri.hMonth, day: hijri.hDay);
  } catch (_) {
    return null;
  }
}

/// هل التاريخ الميلادي يوم جمعة؟
bool isFriday(DateTime date) => date.weekday == DateTime.friday;

/// مفتاح يوم محلي بصيغة yyyy-MM-dd — لتخزين الإحصاءات اليومية.
String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
