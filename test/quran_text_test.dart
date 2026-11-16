import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/core/utils/quran_text.dart';

/// إزالة البسملة من أول آية للعرض فقط (النص المخزَّن يبقى حرفياً).
void main() {
  test('يزيل البسملة من أول آية في السورة', () {
    const text = 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ حمٓ';
    expect(stripLeadingBasmala(text, surahId: 42, number: 1), 'حمٓ');
  });

  test('لا يمسّ سورة الفاتحة (آيتها الأولى هي البسملة)', () {
    const text = '\uFEFFبِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ';
    expect(stripLeadingBasmala(text, surahId: 1, number: 1), text);
  });

  test('لا يمسّ سورة التوبة', () {
    const text = 'بَرَآءَةٌۭ مِّنَ ٱللَّهِ وَرَسُولِهِ';
    expect(stripLeadingBasmala(text, surahId: 9, number: 1), text);
  });

  test('لا يمسّ آية ليست أولى', () {
    const text = 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ';
    expect(stripLeadingBasmala(text, surahId: 2, number: 2), text);
  });

  test('نص بلا بسملة يبقى كما هو', () {
    const text = 'إِنَّمَا ٱلْأَعْمَٰلُ بِٱلنِّيَّٰتِ';
    expect(stripLeadingBasmala(text, surahId: 2, number: 1), text);
  });

  test('يعمل على النص الحقيقي في القاعدة', () {
    final content = ContentDb.openFile(
      File('assets/db/content.sqlite').absolute.path,
    );
    addTearDown(content.dispose);

    final rows = content.db.select(
      'SELECT surah_id, number, text_uthmani FROM ayah '
      'WHERE (surah_id = 2 AND number = 1) OR (surah_id = 42 AND number = 1)',
    );
    expect(rows.length, 2);
    for (final row in rows) {
      final stripped = stripLeadingBasmala(
        row['text_uthmani']! as String,
        surahId: row['surah_id']! as int,
        number: 1,
      );
      expect(stripped.contains('بِسْمِ'), isFalse);
      expect(stripped.trim(), isNotEmpty);
    }
  });

  group('عرض علامات الوقف', () {
    test('العلامة تُلصق بالكلمة السابقة بلا فراغ، والحروف لا تتغير', () {
      const source = 'ذَٰلِكَ ٱلْكِتَٰبُ لَا رَيْبَ ۛ فِيهِ ۛ هُدًۭى';
      final shown = displayQuranText(source);
      expect(shown, 'ذَٰلِكَ ٱلْكِتَٰبُ لَا رَيْبَۛ فِيهِۛ هُدًۭى');
      // لا حرف أُضيف أو حُذف — فقط المسافات قبل العلامات.
      expect(shown.replaceAll(' ', ''), source.replaceAll(' ', ''));
    });

    test('لا تبقى علامة وقف معزولة في المصحف كله', () {
      final content = ContentDb.openFile(
        File('assets/db/content.sqlite').absolute.path,
      );
      addTearDown(content.dispose);
      final isolated = RegExp(' [ۖ-ۜ]( |\$)');
      for (final row in content.db.select('SELECT text_uthmani FROM ayah')) {
        final shown = displayQuranText(row['text_uthmani']! as String);
        expect(isolated.hasMatch(shown), isFalse, reason: shown);
      }
    });
  });

  test('رقم الآية بين قوسي المصحف وملتصق بآخر كلمة', () {
    expect(ayahMark(127), ' ﴿١٢٧﴾');
    expect(
      withMushafAyahMarks('قُلْ هُوَ ٱللَّهُ أَحَدٌ ﴿١﴾ ٱللَّهُ'),
      'قُلْ هُوَ ٱللَّهُ أَحَدٌ ﴿١﴾ ٱللَّهُ',
    );
  });

  test('كشيدة للعرض قبل «ٰٓ» بعد الراء وما لا يتصل بعده — فقط', () {
    expect(quranFontText('إِسْرَٰٓءِيلَ'), 'إِسْرَـٰٓءِيلَ');
    // بعد الكشيدة أو الألف المقصورة يبقى كما هو.
    expect(quranFontText('أُو۟لَـٰٓئِكَ'), 'أُو۟لَـٰٓئِكَ');
    expect(quranFontText('عَلَىٰٓ'), 'عَلَىٰٓ');
  });
}
