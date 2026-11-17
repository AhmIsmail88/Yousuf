import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/core/utils/quran_text.dart';
import 'package:yousuf/features/quran/domain/recitation_matcher.dart';

/// التحقق من آية كاملة (قسم الأطفال): الصحيح يُقبل والخطأ يُرفض.
void main() {
  late ContentDb content;
  setUpAll(() {
    content = ContentDb.openFile(
      File('assets/db/content.sqlite').absolute.path,
    );
  });
  tearDownAll(() => content.dispose());

  String ayah(int surah, int number) {
    final text =
        content.db.select(
              'SELECT text_uthmani FROM ayah WHERE surah_id = ? AND number = ?',
              [surah, number],
            ).first['text_uthmani']
            as String;
    return stripLeadingBasmala(text, surahId: surah, number: number);
  }

  bool ok(String heard, int surah, int number) => checkAyahRecitation(
    heard: heard,
    ayahDisplayText: ayah(surah, number),
  ).correct;

  group('يُقبل', () {
    test('الآية كما يكتبها النموذج (تشكيل وإملاء مختلف)', () {
      expect(ok('قُلْ هُوَ اللَّهُ أَحَدٌ', 112, 1), isTrue);
      expect(ok('اللَّهُ الصَّمَدُ', 112, 2), isTrue);
      expect(ok('الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ', 1, 2), isTrue);
      expect(ok('بسم الله الرحمن الرحيم', 1, 1), isTrue);
    });

    test('مع الاستعاذة أو البسملة قبلها', () {
      expect(
        ok(
          'أعوذ بالله من الشيطان الرجيم بسم الله الرحمن الرحيم قل هو الله أحد',
          112,
          1,
        ),
        isTrue,
      );
    });

    test('الألف الخنجرية والهمزات بكتابة النموذج', () {
      // ٱلصَّٰلِحَٰتِ ← الصالحات، يَسْـَٔلُونَكَ ← يسألونك
      expect(
        ok(
          'إِلَّا الَّذِينَ آمَنُوا وَعَمِلُوا الصَّالِحَاتِ وَتَوَاصَوْا بِالْحَقِّ وَتَوَاصَوْا بِالصَّبْرِ',
          103,
          3,
        ),
        isTrue,
      );
    });

    test('آية طويلة مع خطأ واحد من المحرك', () {
      // آية الكرسي، بكلمة واحدة سمعها المحرك خطأً (سنة ← سنت).
      final heard = normalizeForMatch(ayah(2, 255)).replaceFirst('سنه', 'سنت');
      expect(ok(heard, 2, 255), isTrue);
    });
  });

  group('يُرفض', () {
    test('آية أخرى من السورة نفسها', () {
      expect(ok('اللَّهُ الصَّمَدُ', 112, 1), isFalse);
      expect(ok('لَمْ يَلِدْ وَلَمْ يُولَدْ', 112, 1), isFalse);
      expect(ok('قُلْ هُوَ اللَّهُ أَحَدٌ', 112, 2), isFalse);
    });

    test('كلام عربي لا علاقة له بالآية (كان يُقبل بمقارنة الحروف)', () {
      expect(ok('فوصر فقطهم وخلفك فوصر', 1, 2), isFalse);
      expect(ok('الحمد لله على كل حال', 1, 2), isFalse);
    });

    test('نصف الآية أو كلمة ناقصة في آية قصيرة', () {
      expect(ok('الحمد لله', 1, 2), isFalse);
      expect(ok('الحمد لله العالمين', 1, 2), isFalse);
      expect(ok('قل هو الله', 112, 1), isFalse);
    });

    test('كلمة مبدَّلة في آية قصيرة', () {
      expect(ok('قل هو الله واحد', 112, 1), isFalse);
      expect(ok('الحمد لله رب الناس', 1, 2), isFalse);
    });

    test('البدء من وسط الآية', () {
      expect(ok('رب العالمين', 1, 2), isFalse);
    });

    test('صمت', () {
      expect(ok('', 1, 2), isFalse);
      expect(ok('   ', 112, 1), isFalse);
    });
  });
}
