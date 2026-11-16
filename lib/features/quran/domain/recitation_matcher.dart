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
  var score = matched / ayahWords.length;

  // احتياط: إذا دمج المحرك الكلمات في كلمة واحدة (بسمالله) نقيس الحروف.
  if (score < threshold) {
    final ayahChars = ayahWords.join();
    final heardChars = heardWords.join();
    final charScore =
        _lcsLength(ayahChars.split(''), heardChars.split('')) /
        ayahChars.length;
    if (charScore * 0.95 > score) score = charScore * 0.95;
  }

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
