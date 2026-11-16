import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../utils/arabic_dates.dart';
import '../utils/arabic_digits.dart';
import 'tr.dart';

const _enWeekdays = <int, String>{
  DateTime.monday: 'Monday',
  DateTime.tuesday: 'Tuesday',
  DateTime.wednesday: 'Wednesday',
  DateTime.thursday: 'Thursday',
  DateTime.friday: 'Friday',
  DateTime.saturday: 'Saturday',
  DateTime.sunday: 'Sunday',
};

const _enMonths = <int, String>{
  1: 'January',
  2: 'February',
  3: 'March',
  4: 'April',
  5: 'May',
  6: 'June',
  7: 'July',
  8: 'August',
  9: 'September',
  10: 'October',
  11: 'November',
  12: 'December',
};

const _enHijriMonths = <int, String>{
  1: 'Muharram',
  2: 'Safar',
  3: 'Rabi al-Awwal',
  4: 'Rabi al-Akhir',
  5: 'Jumada al-Ula',
  6: 'Jumada al-Akhirah',
  7: 'Rajab',
  8: 'Shaban',
  9: 'Ramadan',
  10: 'Shawwal',
  11: 'Dhu al-Qadah',
  12: 'Dhu al-Hijjah',
};

/// تنسيق الأرقام والتواريخ والأوقات حسب لغة الواجهة وصيغة الأرقام.
///
/// صيغة الأرقام تُقرأ من الثيم ([DigitsTheme]) لا من متغير عام، فيُعاد بناء
/// كل نص يعتمد عليها فور تغييرها. الواجهة الإنجليزية تستخدم 123 دائماً.
extension FormatContext on BuildContext {
  /// هل تُعرض الأرقام هندية (١٢٣)؟
  bool get hindiDigits {
    if (!isArabic) return false;
    final style = Theme.of(this).extension<DigitsTheme>()?.style;
    return (style ?? DigitStyle.hindi) == DigitStyle.hindi;
  }

  /// يحوّل أرقام النص حسب الإعداد.
  String digits(Object text) {
    final value = '$text';
    if (!hindiDigits) return toArabicDigits(value);
    return toArabicDigits(value).replaceAllMapped(
      RegExp('[0-9]'),
      (m) => String.fromCharCode(0x0660 + int.parse(m.group(0)!)),
    );
  }

  /// «الأربعاء ١١ نوفمبر ٢٠٢٦» أو «Wednesday 11 November 2026».
  String formatDate(DateTime date) => isArabic
      ? digits(formatGregorianDate(date))
      : '${_enWeekdays[date.weekday]} ${date.day} '
            '${_enMonths[date.month]} ${date.year}';

  /// اسم اليوم فقط.
  String weekdayName(DateTime date) =>
      isArabic ? arabicWeekdays[date.weekday]! : _enWeekdays[date.weekday]!;

  /// اسم الشهر الميلادي.
  String monthName(int month) =>
      isArabic ? arabicMonths[month]! : _enMonths[month]!;

  /// اسم الشهر الهجري.
  String hijriMonthName(int month) =>
      isArabic ? (hijriMonths[month] ?? '') : (_enHijriMonths[month] ?? '');

  /// «٣٠ جمادى الأولى ١٤٤٨هـ» أو «30 Jumada al-Ula 1448 AH».
  String formatHijri(HijriDay day) => isArabic
      ? digits(day.formatted)
      : '${day.day} ${_enHijriMonths[day.month]} ${day.year} AH';

  /// "16:05" ← «٤:٠٥ م» أو «4:05 PM».
  String formatTime(String hhmm, {bool withPeriod = true}) {
    final parts = hhmm.split(':');
    final hour24 = int.parse(parts[0]);
    final minute = parts[1];
    final isPm = hour24 >= 12;
    var hour12 = hour24 % 12;
    if (hour12 == 0) hour12 = 12;
    final period = isArabic ? (isPm ? 'م' : 'ص') : (isPm ? 'PM' : 'AM');
    final text = withPeriod ? '$hour12:$minute $period' : '$hour12:$minute';
    return digits(text);
  }

  /// مدة بالدقائق بعد «بعد»: «ساعتين و٥ دقائق» / «2 h 5 min».
  String formatDuration(int minutes) {
    if (minutes <= 0) return tr('الآن', 'now');
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (!isArabic) {
      if (hours == 0) return '$rest min';
      return rest == 0 ? '$hours h' : '$hours h $rest min';
    }
    String h() => hours == 1
        ? 'ساعة'
        : hours == 2
        ? 'ساعتين'
        : '${digits(hours)} ${hours <= 10 ? 'ساعات' : 'ساعة'}';
    String m() => rest == 1
        ? 'دقيقة'
        : rest == 2
        ? 'دقيقتين'
        : '${digits(rest)} ${rest <= 10 ? 'دقائق' : 'دقيقة'}';
    if (hours == 0) return m();
    if (rest == 0) return h();
    return '${h()} و${m()}';
  }
}
