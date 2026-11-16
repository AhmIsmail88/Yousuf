/// أدوات نص القرآن للعرض: إزالة البسملة المكرّرة من أول آية (عرضاً فقط).
///
/// النص المخزَّن من Tanzil يبقى حرفياً كما هو (شرط الترخيص)؛ الإزالة هنا
/// تُطبَّق وقت البناء فقط لأن شاشة المصحف ترسم بسملة مستقلة لكل سورة.
library;

const String kBasmalaNormalized = 'بسم الله الرحمن الرحيم';

const String _diacritics =
    '\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640\uFEFF\u200B-\u200F';

bool _isDecoration(String ch) => RegExp('[$_diacritics]').hasMatch(ch);

String _normalizeChar(String ch) {
  switch (ch) {
    case 'ٱ':
    case 'أ':
    case 'إ':
    case 'آ':
      return 'ا';
    case 'ى':
      return 'ي';
    case 'ة':
      return 'ه';
    default:
      return ch;
  }
}

/// يزيل «بسم الله الرحمن الرحيم» من بداية الآية الأولى في السورة.
///
/// - سورة الفاتحة: الآية الأولى هي البسملة نفسها ⇒ لا تُمسّ.
/// - سورة التوبة: لا بسملة لها أصلاً.
/// - أي نص لا يبدأ بالبسملة يُعاد كما هو.
String stripLeadingBasmala(
  String text, {
  required int surahId,
  required int number,
}) {
  if (number != 1 || surahId == 1 || surahId == 9) return text;

  final buffer = StringBuffer();
  final positions = <int>[];
  var lastWasSpace = false;

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (_isDecoration(ch)) continue;
    final mapped = _normalizeChar(ch);
    if (mapped == ' ') {
      if (lastWasSpace) continue;
      lastWasSpace = true;
    } else {
      lastWasSpace = false;
    }
    buffer.write(mapped);
    positions.add(i);
  }

  final normalized = buffer.toString();
  if (!normalized.startsWith(kBasmalaNormalized)) return text;

  // موضع نهاية البسملة في النص الأصلي.
  var cut = positions[kBasmalaNormalized.length - 1] + 1;
  // التشكيل الذي يلي آخر حرف (مثل الكسرة على الميم) يُحذف مع البسملة.
  while (cut < text.length && _isDecoration(text[cut])) {
    cut++;
  }
  final rest = text.substring(cut);
  return rest.trimLeft();
}

/// علامات الوقف الصغيرة (صلى، قلى، الوقف اللازم، المعانقة…) — حروف تشكيل
/// فوقية في يونيكود (U+06D6–U+06DC).
final RegExp _spacedWaqfMark = RegExp(' ([ۖ-ۜ])');

/// يجهّز نص الآية للعرض: يلصق علامات الوقف بالكلمة السابقة.
///
/// في المصدر (Tanzil) تأتي العلامة كلمة مستقلة بين مسافتين («رَيْبَ ۛ فِيهِ»)،
/// فتظهر وحدها بفراغ واسع، ويتضاعف الفراغ مع المحاذاة للطرفين. في المصحف
/// المطبوع تُكتب العلامة فوق آخر الكلمة بلا فراغ. **الحروف لا تتغير** —
/// نحذف المسافة قبل العلامة فقط، للعرض، والنص المخزّن يبقى حرفياً.
String displayQuranText(String text) => text
    .replaceAll('﻿', '')
    .replaceAllMapped(_spacedWaqfMark, (m) => m.group(1)!);

/// نص الآية للمشاركة والنسخ: في أول آية من السورة (عدا الفاتحة والتوبة)
/// تُوضع البسملة في سطر مستقل قبل الآية، لا ملتصقة بها.
String ayahTextForSharing(
  String text, {
  required int surahId,
  required int number,
}) {
  final rest = stripLeadingBasmala(text, surahId: surahId, number: number);
  if (rest == text || !text.endsWith(rest)) return text;
  final basmala = text.substring(0, text.length - rest.length).trim();
  if (basmala.isEmpty) return text;
  return '$basmala\n${rest.trim()}';
}

/// رقم الآية بين قوسي المصحف المزخرفين «﴿١٢﴾» — كما يرسمها Tanzil بخط مجمع
/// الملك فهد. المسافة غير الفاصلة تُلصق الرقم بآخر كلمة فلا ينفصل عنها.
String ayahMark(int number) =>
    '\u00A0﴿${number.toString().replaceAllMapped(RegExp('[0-9]'), (m) => String.fromCharCode(0x0660 + int.parse(m.group(0)!)))}﴾';

final RegExp _bracketedAyahNumber = RegExp(r'\s*﴿([٠-٩]+)﴾');

/// يُلصق أرقام الآيات المخزّنة «﴿١٢﴾» بآخر كلمة (انظر [ayahMark]).
String withMushafAyahMarks(String text) =>
    text.replaceAllMapped(_bracketedAyahNumber, (m) => '\u00A0﴿${m.group(1)}﴾');

/// الألف الخنجرية مع المدّ «ٰٓ» بعد راء أو زاي أو واو أو همزة («إِسْرَٰٓءِيلَ»،
/// «جَزَٰٓؤُا۟»، «ٱلرِّبَوٰٓا۟»): يرسمها خط المجمع في Flutter بالمدّ فوق الفتحة،
/// وموقع Tanzil يرسمها بالمدّ فوق الألف. كشيدة قبل الألف الخنجرية (وهذه الحروف
/// لا تتصل بما بعدها فلا يظهر لها خط) تجعل الرسم مطابقاً لـ Tanzil.
final RegExp _daggerMaddAfterNonJoiner = RegExp(
  '([رزوء][\u064B-\u0652]*)(\u0670\u0653)',
);

/// نص قرآني جاهز للرسم بخط المصحف — **للعرض فقط**؛ النص المخزَّن والمنسوخ
/// والمُشارَك نصاً يبقى حرفياً كما في Tanzil.
String quranFontText(String text) =>
    text.replaceAllMapped(_daggerMaddAfterNonJoiner, (m) => '${m[1]}ـ${m[2]}');
