import 'package:flutter_test/flutter_test.dart';
import 'package:yousuf/features/quran/domain/recitation_matcher.dart';

void main() {
  // البقرة ٢٥ (أولها) بنص مجمع الملك فهد.
  const ayah =
      'وَبَشِّرِ ٱلَّذِينَ ءَامَنُواْ وَعَمِلُواْ ٱلصَّٰلِحَٰتِ أَنَّ لَهُمۡ جَنَّٰتٖ '
      'تَجۡرِي مِن تَحۡتِهَا ٱلۡأَنۡهَٰرُۖ';
  final expected = recitationTokens(ayah);

  test('تتقدّم كلمة بكلمة مع كل مقطع مسموع', () {
    var position = followRecitation(
      expected: expected,
      position: 0,
      heard: 'وبشر الذين',
    );
    expect(position, 2);
    position = followRecitation(
      expected: expected,
      position: position,
      // المقاطع متداخلة: يتكرر ما سبق ثم يأتي الجديد.
      heard: 'وبشر الذين آمنوا وعملوا الصالحات',
    );
    expect(position, 5);
  });

  test('تتسامح مع التشكيل وخطأ حرف واحد', () {
    final position = followRecitation(
      expected: expected,
      position: 0,
      heard: 'وَبَشِّرْ الَّذِينَ آمَنُو',
    );
    expect(position, 3);
  });

  test('لا تتقدّم بكلام لا علاقة له بالآية', () {
    final position = followRecitation(
      expected: expected,
      position: 2,
      heard: 'فوصر فقطهم وخلفك',
    );
    expect(position, 2);
  });

  test('تتجاوز كلمة أسقطها المحرك بين كلمتين صحيحتين', () {
    final position = followRecitation(
      expected: expected,
      position: 0,
      heard: 'وبشر آمنوا وعملوا',
    );
    expect(position, 4);
  });

  test('لا تقفز بعيداً بكلمة شائعة متأخرة', () {
    final position = followRecitation(
      expected: expected,
      position: 0,
      heard: 'من',
    );
    expect(position, 0);
  });

  test('علامة الحزب «۞» لا تُنطق فتُطوى', () {
    final tokens = recitationTokens('۞ إِنَّ ٱللَّهَ');
    expect(tokens.first, isEmpty);
    expect(followRecitation(expected: tokens, position: 0, heard: 'ان'), 2);
  });
}
