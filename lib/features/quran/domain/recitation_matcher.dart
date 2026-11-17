/// مطابقة التلاوة المسموعة بنص الآية — قلب وضع الحفظ.
///
/// التعرّف الصوتي يخطئ في التشكيل والهمزات والمدّ، ويُسقط كلمات أو يدمجها،
/// فنُطبّع النصين ثم نقيس تطابق الكلمات **بالترتيب** (LCS) لا بالتساوي الحرفي.
library;

/// نتيجة مقارنة تلاوة بآية.
class RecitationScore {
  const RecitationScore({
    required this.score,
    required this.matchedWords,
    required this.totalWords,
    required this.heardWords,
    required this.threshold,
  });

  /// نسبة الكلمات المطابقة بالترتيب (0..1).
  final double score;
  final int matchedWords;
  final int totalWords;
  final int heardWords;
  final double threshold;

  bool get passed => score >= threshold;

  /// هل سمع المحرك كلاماً كافياً للحكم؟
  bool get hasSpeech => heardWords > 0;

  @override
  String toString() =>
      'RecitationScore(score: ${score.toStringAsFixed(2)}, '
      'matched: $matchedWords/$totalWords, heard: $heardWords)';
}

const _diacritics = r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED\u0640]';
const _punctuation = r'[^\u0621-\u064A\u0660-\u0669\s]';

const _letterMap = <String, String>{
  'أ': 'ا',
  'إ': 'ا',
  'آ': 'ا',
  'ٱ': 'ا',
  'ى': 'ي',
  'ئ': 'ي',
  'ؤ': 'و',
  'ة': 'ه',
  'ء': '',
};

/// تطبيع نص عربي/قرآني للمقارنة: بلا تشكيل ولا رسم عثماني ولا همزات.
String normalizeForMatch(String input) {
  var text = input.replaceAll(RegExp(_diacritics), '');
  // توحيد الحروف أولاً: «ٱ» ألف وصل تُحوَّل قبل حذف ما ليس من حروف العربية.
  for (final entry in _letterMap.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  text = text.replaceAll(RegExp(_punctuation), ' ');
  // أرقام الآيات المرسومة داخل النص لا تُنطق.
  text = text.replaceAll(RegExp(r'[\u0660-\u0669]'), ' ');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<String> _words(String normalized) =>
    normalized.isEmpty ? const [] : normalized.split(' ');

/// طول أطول تتابع مشترك (LCS) — يكفي لحجم الآية.
int _lcsLength(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  var previous = List<int>.filled(b.length + 1, 0);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      current[j] = a[i - 1] == b[j - 1]
          ? previous[j - 1] + 1
          : (previous[j] > current[j - 1] ? previous[j] : current[j - 1]);
    }
    final swap = previous;
    previous = current;
    current = swap;
    current.fillRange(0, current.length, 0);
  }
  return previous[b.length];
}

/// يقارن ما سمعه المحرك بنص الآية.
///
/// [threshold] نسبة القبول (0.6 من الكلمات بالترتيب)، و[allowPartial] يسمح
/// بقبول الآيات الطويلة عند بلوغ أغلبها (افتراضي: نعم، للطفل).
RecitationScore evaluateRecitation({
  required String heard,
  required String ayahText,
  double threshold = 0.6,
}) {
  final ayahWords = _words(normalizeForMatch(ayahText));
  final heardWords = _words(normalizeForMatch(heard));
  if (ayahWords.isEmpty || heardWords.isEmpty) {
    return RecitationScore(
      score: 0,
      matchedWords: 0,
      totalWords: ayahWords.length,
      heardWords: heardWords.length,
      threshold: threshold,
    );
  }

  final matched = _lcsLength(ayahWords, heardWords);
  // لا مقارنة بالحروف: أي جملة عربية تشترك مع أي آية في حروف كثيرة، فكانت
  // تُقبل التلاوة الخاطئة. للتحقق من آية كاملة استعمل [checkAyahRecitation].
  final score = matched / ayahWords.length;

  return RecitationScore(
    score: score.clamp(0, 1),
    matchedWords: matched,
    totalWords: ayahWords.length,
    heardWords: heardWords.length,
    threshold: threshold,
  );
}

// ---------------- التسميع كلمة بكلمة ----------------

/// كلمات نص العرض مُطبَّعةً، بنفس ترتيب الكلمات المفصولة بمسافة في النص.
/// الكلمة التي لا تُنطق (علامة الحزب «۞» مثلاً) تصير نصاً فارغاً.
///
/// الألف الخنجرية «ٰ» (ٱلصَّٰلِحَٰتِ) تُنطق ألفاً، والمحرك يكتبها أحياناً
/// ويُسقطها أحياناً، فتُحفظ الكلمة بصيغتيها مفصولتين بـ«|».
List<String> recitationTokens(String displayText) => [
  for (final token in displayText.split(' '))
    {
      normalizeForMatch(token),
      normalizeForMatch(token.replaceAll('ٰ', 'ا')),
    }.join('|'),
];

/// مسافة التحرير بين كلمتين (Levenshtein).
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final best = previous[j] + 1 < current[j - 1] + 1
          ? previous[j] + 1
          : current[j - 1] + 1;
      current[j] = best < previous[j - 1] + cost
          ? best
          : previous[j - 1] + cost;
    }
    previous = current;
  }
  return previous[b.length];
}

/// هل الكلمة المسموعة هي الكلمة المتوقعة؟ يتسامح مع خطأ حرف في القصيرة
/// وحرفين في الطويلة — المحرك يخطئ في الحروف المتقاربة والمدود.
bool wordsMatch(String heard, String expected) {
  if (expected.contains('|')) {
    return expected.split('|').any((form) => wordsMatch(heard, form));
  }
  if (heard == expected) return true;
  final length = expected.length;
  if (length < 3 || heard.length < 2) return false;
  final allowed = length >= 7 ? 2 : 1;
  return _editDistance(heard, expected) <= allowed;
}

/// يتابع التلاوة كلمة بكلمة: يعيد موضع أول كلمة لم تُتلَ بعد في [expected].
///
/// [heard] نص آخر مقطع سمعه المحرك؛ المقاطع متداخلة فيتكرر فيها ما سبق،
/// لذا نحاذي المسموع (بالترتيب، مع التسامح في الحروف) على نافذة تبدأ قبل
/// [position] بقليل: الكلمات المكرَّرة تقع على ما كُشف ولا تدفع الموضع.
/// يُسمح بتجاوز [maxSkip] كلمات أسقطها المحرك بين كلمتين مسموعتين صحيحتين.
int followRecitation({
  required List<String> expected,
  required int position,
  required String heard,
  int maxSkip = 2,
}) {
  while (position < expected.length && expected[position].isEmpty) {
    position++;
  }
  final words = _words(normalizeForMatch(heard));
  if (words.isEmpty || position >= expected.length) return position;
  final start = position - 20 < 0 ? 0 : position - 20;
  final end = position + words.length + maxSkip + 2 > expected.length
      ? expected.length
      : position + words.length + maxSkip + 2;
  final window = expected.sublist(start, end);

  // محاذاة بالترتيب (LCS مع تطابق متسامح)، ثم نتتبع الأزواج المتطابقة.
  final rows = words.length + 1;
  final cols = window.length + 1;
  final table = List.generate(rows, (_) => List<int>.filled(cols, 0));
  bool same(int i, int j) => wordsMatch(words[i], window[j]);
  for (var i = 1; i < rows; i++) {
    for (var j = 1; j < cols; j++) {
      table[i][j] = same(i - 1, j - 1)
          ? table[i - 1][j - 1] + 1
          : (table[i - 1][j] > table[i][j - 1]
                ? table[i - 1][j]
                : table[i][j - 1]);
    }
  }
  final matched = <int>[];
  var i = rows - 1;
  var j = cols - 1;
  while (i > 0 && j > 0) {
    if (same(i - 1, j - 1) && table[i][j] == table[i - 1][j - 1] + 1) {
      matched.add(start + j - 1);
      i--;
      j--;
    } else if (table[i - 1][j] >= table[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  matched.sort();

  // نتقدّم كلمة فكلمة: كل كلمة مطابقة بعد الموضع تُقبل ما دام ما تخطّته
  // من كلمات لا يتجاوز [maxSkip].
  var next = position;
  for (final index in matched) {
    if (index < next) continue;
    if (index - next > maxSkip) break;
    next = index + 1;
  }
  // الكلمات غير المنطوقة (فارغة) تُطوى تلقائياً.
  while (next < expected.length && expected[next].isEmpty) {
    next++;
  }
  return next;
}

// ---------------- التحقق من آية كاملة (قسم الأطفال) ----------------

/// نتيجة التحقق من تلاوة آية كاملة.
class AyahCheck {
  const AyahCheck({
    required this.correct,
    required this.matched,
    required this.total,
    required this.heardWords,
    required this.extraInside,
  });

  /// الآية صحيحة: كلماتها بالترتيب من أولها إلى آخرها (مع تسامح بسيط).
  final bool correct;
  final int matched;
  final int total;
  final int heardWords;

  /// كلمات مسموعة ليست من الآية بين أول كلمة مطابقة وآخرها.
  final int extraInside;

  bool get hasSpeech => heardWords > 0;

  @override
  String toString() =>
      'AyahCheck(correct: $correct, matched: $matched/$total, '
      'heard: $heardWords, extra: $extraInside)';
}

/// تطابق كلمة للتحقق من آية كاملة — أصرم من [wordsMatch]: الكلمات القصيرة
/// (٤ أحرف فأقل) يجب أن تطابق تماماً («واحد» ليست «أحد»)، والمتوسطة تتحمل
/// حرفاً (الرحمان/الرحمن)، والطويلة حرفين.
bool _strictWord(String heard, String expected) {
  if (heard == expected) return true;
  final length = expected.length;
  if (length <= 4) return false;
  return _editDistance(heard, expected) <= (length >= 8 ? 2 : 1);
}

/// كم كلمة يُتسامح في فقدها (أخطاء المحرك لا الطفل): لا شيء في الآيات
/// القصيرة، وكلمة لكل ثمانٍ تقريباً في الطويلة.
int _allowedMisses(int total) => total < 8 ? 0 : (total ~/ 8).clamp(1, 4);

const List<String> _basmala = ['بسم', 'الله', 'الرحمن', 'الرحيم'];
const List<String> _istiadha = ['اعوذ', 'بالله', 'من', 'الشيطان', 'الرجيم'];

/// يحذف الاستعاذة والبسملة من أول المسموع إن لم تكونا من الآية نفسها.
List<String> _dropOpening(List<String> heard, List<String> expected) {
  var words = heard;
  bool startsWith(List<String> list, List<String> prefix) {
    if (list.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (!_strictWord(list[i], prefix[i])) return false;
    }
    return true;
  }

  if (startsWith(words, _istiadha)) words = words.sublist(_istiadha.length);
  final ayahIsBasmala =
      expected.isNotEmpty && expected.first.split('|').first == 'بسم';
  if (!ayahIsBasmala && startsWith(words, _basmala)) {
    words = words.sublist(_basmala.length);
  }
  return words;
}

/// يتحقق أن [heard] هو الآية [ayahDisplayText] كاملةً.
///
/// - الكلمات بالترتيب (محاذاة LCS بتطابق متسامح: همزات، ألف خنجرية، حرف).
/// - يجب أن تبدأ من أول كلمة وتنتهي بآخر كلمة.
/// - لا يُتسامح في فقد كلمة إلا في الآيات الطويلة ([_allowedMisses]).
/// - كلمات غريبة كثيرة وسط التلاوة ⇐ خطأ (آية أخرى أو كلام مختلف).
/// - **لا مقارنة بالحروف**: أي جملة عربية تشترك مع أي آية في حروف كثيرة،
///   فكانت تُقبل التلاوة الخاطئة.
AyahCheck checkAyahRecitation({
  required String heard,
  required String ayahDisplayText,
}) {
  final expected = recitationTokens(ayahDisplayText)
      .where((w) => w.isNotEmpty)
      .toList();
  final words = _dropOpening(_words(normalizeForMatch(heard)), expected);
  final total = expected.length;
  if (total == 0 || words.isEmpty) {
    return AyahCheck(
      correct: false,
      matched: 0,
      total: total,
      heardWords: words.length,
      extraInside: 0,
    );
  }

  // محاذاة بالترتيب؛ والكلمة المسموعة قد تكون كلمتين ملتصقتين (يا+أيها).
  bool same(int h, int e) =>
      expected[e].split('|').any((form) => _strictWord(words[h], form));
  bool merged(int h, int e) =>
      e + 1 < total &&
      expected[e]
          .split('|')
          .any(
            (a) => expected[e + 1]
                .split('|')
                .any((b) => _editDistance(words[h], a + b) <= 1),
          );
  final rows = words.length + 1;
  final cols = total + 1;
  final table = List.generate(rows, (_) => List<int>.filled(cols, 0));
  for (var h = 1; h < rows; h++) {
    for (var e = 1; e < cols; e++) {
      var best = table[h - 1][e] > table[h][e - 1]
          ? table[h - 1][e]
          : table[h][e - 1];
      if (same(h - 1, e - 1) && table[h - 1][e - 1] + 1 > best) {
        best = table[h - 1][e - 1] + 1;
      }
      if (e >= 2 && merged(h - 1, e - 2) && table[h - 1][e - 2] + 2 > best) {
        best = table[h - 1][e - 2] + 2;
      }
      table[h][e] = best;
    }
  }
  // تتبّع المحاذاة لمعرفة الكلمات المسموعة المطابقة وأولى/آخر كلمة في الآية.
  final heardUsed = <int>[];
  var firstExpected = total;
  var lastExpected = -1;
  var h = rows - 1;
  var e = cols - 1;
  while (h > 0 && e > 0) {
    if (same(h - 1, e - 1) && table[h][e] == table[h - 1][e - 1] + 1) {
      heardUsed.add(h - 1);
      firstExpected = e - 1;
      if (lastExpected < 0) lastExpected = e - 1;
      h--;
      e--;
    } else if (e >= 2 &&
        merged(h - 1, e - 2) &&
        table[h][e] == table[h - 1][e - 2] + 2) {
      heardUsed.add(h - 1);
      firstExpected = e - 2;
      if (lastExpected < 0) lastExpected = e - 1;
      h--;
      e -= 2;
    } else if (table[h - 1][e] >= table[h][e - 1]) {
      h--;
    } else {
      e--;
    }
  }
  final matched = table[rows - 1][cols - 1];
  var extraInside = 0;
  if (heardUsed.isNotEmpty) {
    final first = heardUsed.reduce((a, b) => a < b ? a : b);
    final last = heardUsed.reduce((a, b) => a > b ? a : b);
    extraInside = (last - first + 1) - heardUsed.length;
  }
  final allowed = _allowedMisses(total);
  final correct =
      matched >= total - allowed &&
      firstExpected == 0 &&
      lastExpected == total - 1 &&
      extraInside <= allowed;
  return AyahCheck(
    correct: correct,
    matched: matched,
    total: total,
    heardWords: words.length,
    extraInside: extraInside,
  );
}
