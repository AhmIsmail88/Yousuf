/// تحويل الأرقام بين الصيغة العربية (123) والهندية (١٢٣)
/// حسب إعداد المستخدم في شاشة الإعدادات (قسم المظهر).
library;

/// صيغة عرض الأرقام في الواجهة — SPEC §8.
enum DigitStyle { hindi, arabic }

/// الصيغة الفعّالة؛ تُضبط من الإعدادات عند بدء التشغيل وعند تغييرها.
DigitStyle digitStyle = DigitStyle.hindi;

/// يضبط صيغة الأرقام العامة (يُنادى من جذر التطبيق).
void setDigitStyle(DigitStyle style) => digitStyle = style;

const _arabicToHindi = {
  '0': '٠',
  '1': '١',
  '2': '٢',
  '3': '٣',
  '4': '٤',
  '5': '٥',
  '6': '٦',
  '7': '٧',
  '8': '٨',
  '9': '٩',
};

const _hindiToArabic = {
  '٠': '0',
  '١': '1',
  '٢': '2',
  '٣': '3',
  '٤': '4',
  '٥': '5',
  '٦': '6',
  '٧': '7',
  '٨': '8',
  '٩': '9',
};

/// يعيد الأرقام في النص إلى الصيغة الهندية (١٢٣) صراحةً.
///
/// يُستخدم حيث تكون الهندية جزءاً من الشكل المقصود (أرقام الآيات في المصحف
/// لا تُمسّ — انظر `toArabicDigits`).
String toHindiDigits(String input) {
  final normalized = toArabicDigits(input);
  if (digitStyle == DigitStyle.arabic) return normalized;
  return normalized.replaceAllMapped(
    RegExp(r'[0-9]'),
    (m) => _arabicToHindi[m.group(0)]!,
  );
}

/// يحوّل الأرقام الهندية (١٢٣) في النص إلى عربية (123).
String toArabicDigits(String input) => input.replaceAllMapped(
  RegExp(r'[٠-٩]'),
  (m) => _hindiToArabic[m.group(0)]!,
);

/// ينسّق أرقام النص حسب إعداد المستخدم.
String formatDigits(String input, {required bool hindi}) =>
    hindi ? toHindiDigits(input) : toArabicDigits(input);
