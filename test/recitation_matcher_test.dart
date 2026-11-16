import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/features/quran/domain/recitation_matcher.dart';

/// مطابقة التلاوة: التطبيع ثم أطول تتابع مشترك (LCS) بالترتيب.
void main() {
  group('التطبيع', () {
    test('يزيل التشكيل والمدّ', () {
      expect(normalizeForMatch('الْحَمْدُ لِلَّهِ'), 'الحمد لله');
    });

    test('يوحّد الهمزات والألف المقصورة والتاء المربوطة', () {
      expect(normalizeForMatch('أَنعَمتَ'), 'انعمت');
      expect(normalizeForMatch('إِسْرَائِيل'), 'اسراييل');
      expect(normalizeForMatch('هُدًى'), 'هدي');
      expect(normalizeForMatch('جَنَّة'), 'جنه');
    });

    test('يحذف علامات الوقف والأرقام', () {
      expect(normalizeForMatch('قُلْ ۞ هُوَ ٱللَّهُ ۩ ١'), 'قل هو الله');
    });
  });

  group('المطابقة', () {
    const fatiha = 'الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ';

    test('تلاوة صحيحة تماماً تنجح', () {
      final score = evaluateRecitation(
        heard: 'الحمد لله رب العالمين',
        ayahText: fatiha,
      );
      expect(score.passed, isTrue);
      expect(score.score, closeTo(1, 0.001));
      expect(score.matchedWords, 4);
      expect(score.totalWords, 4);
    });

    test('الكلمات الزائدة من المحرك لا تُفشل التلاوة', () {
      final score = evaluateRecitation(
        heard: 'بسم الله الرحمن الرحيم الحمد لله رب العالمين',
        ayahText: fatiha,
      );
      expect(score.passed, isTrue);
    });

    test('نقص كلمة يمرّ بالحد الافتراضي ويفشل بالحد الصارم', () {
      final heard = 'الحمد لله العالمين';
      expect(evaluateRecitation(heard: heard, ayahText: fatiha).passed, isTrue);
      expect(
        evaluateRecitation(
          heard: heard,
          ayahText: fatiha,
          threshold: 0.9,
        ).passed,
        isFalse,
      );
    });

    test('آية مختلفة تفشل', () {
      final score = evaluateRecitation(
        heard: 'قل هو الله أحد',
        ayahText: fatiha,
      );
      expect(score.passed, isFalse);
      expect(score.score, lessThan(0.4));
    });

    test('صمت تام لا يُعدّ تلاوة', () {
      final score = evaluateRecitation(heard: '   ', ayahText: fatiha);
      expect(score.hasSpeech, isFalse);
      expect(score.passed, isFalse);
    });

    test('السور القصيرة تُقبل بحد أدنى مناسب', () {
      final score = evaluateRecitation(
        heard: 'قل هو الله احد',
        ayahText: 'قُلْ هُوَ ٱللَّهُ أَحَدٌ',
        threshold: 0.5,
      );
      expect(score.passed, isTrue);
    });
  });
}
