import 'arabic_digits.dart';

/// أدوات تنسيق الوقت: 12/24 ساعة، وأرقام هندية أو عربية.
class TimeFormat {
  TimeFormat._();

  /// يحوّل "HH:mm" (24 ساعة) إلى صيغة 12 ساعة: "4:08 ص" أو "٤:٠٨ ص".
  static String to12h(String hhmm, {bool hindiDigits = true}) {
    final parts = hhmm.split(':');
    final hour24 = int.parse(parts[0]);
    final minute = parts[1];
    final isPm = hour24 >= 12;
    var hour12 = hour24 % 12;
    if (hour12 == 0) hour12 = 12;
    final text = '$hour12:$minute ${isPm ? 'م' : 'ص'}';
    return hindiDigits ? toHindiDigits(text) : text;
  }

  /// يعيد "HH:mm" بأرقام هندية أو عربية حسب إعداد المستخدم.
  static String digits(String hhmm, {required bool hindi}) =>
      hindi ? toHindiDigits(hhmm) : hhmm;

  /// دقائق من منتصف الليل لوقت "HH:mm".
  static int minutesOfDay(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// فرق زمني بين وقتين "HH:mm" بالدقائق (موجب إذا كان b بعد a).
  static int minutesBetween(String a, String b) =>
      minutesOfDay(b) - minutesOfDay(a);
}
