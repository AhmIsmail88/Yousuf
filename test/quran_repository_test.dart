import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/features/quran/data/quran_repository.dart';

/// اختبارات بيانات المصحف على ملف المحتوى الحقيقي (assets/db/content.sqlite).
void main() {
  late ContentDb content;
  late QuranRepository repository;

  setUpAll(() {
    final path = File('assets/db/content.sqlite').absolute.path;
    expect(
      File(path).existsSync(),
      isTrue,
      reason: 'شغّل tools/content_builder/build.py أولاً',
    );
    content = ContentDb.openFile(path);
    repository = QuranRepository(content);
  });

  tearDownAll(() => content.dispose());

  test('السور 114 وبيناتها الأساسية سليمة', () {
    final surahs = repository.surahs();
    expect(surahs.length, 114);

    final fatiha = repository.surah(1)!;
    expect(fatiha.nameAr, isNotEmpty);
    expect(fatiha.ayahCount, 7);
    expect(fatiha.isMakki, isTrue); // الفاتحة مكية

    final ikhlas = repository.surah(112)!;
    expect(ikhlas.ayahCount, 4);
    expect(ikhlas.isMakki, isTrue);
  });

  test('صفحة الفاتحة (1) فيها 7 آيات وتبدأ بسورة الفاتحة', () {
    final page = repository.page(1);
    expect(page.ayat.length, 7);
    expect(page.firstAyah!.surahId, 1);
    expect(page.firstAyah!.number, 1);
  });

  test('الصفحة 2 تبدأ بالبقرة:١ (مصحف المدينة)', () {
    final page = repository.page(2);
    expect(page.firstAyah!.surahId, 2);
    expect(page.firstAyah!.number, 1);
  });

  test('آيات سورة الإخلاص كاملة', () {
    final ayat = repository.ayatOfSurah(112);
    expect(ayat.length, 4);
    expect(ayat.first.text, contains('قُلْ'));
  });

  test('البحث يجد "الرحمن" ويستبعد التشكيل', () {
    final hits = repository.search('الرحمن', limit: 500);
    expect(hits, isNotEmpty);
    // الفاتحة 1:3 و الرحمن 55:1 من أشهر المواضع.
    expect(
      hits.any((hit) => hit.ayah.surahId == 55 && hit.ayah.number == 1),
      isTrue,
    );
  });

  test('البحث بكلمتين يشترط اجتماعهما', () {
    final hits = repository.search('رب العالمين');
    expect(hits, isNotEmpty);
    expect(hits.first.ayah.surahId, 1);
    expect(hits.first.ayah.number, 2); // الحمد لله رب العالمين
  });

  test('البحث لا يكسر عند رموز FTS', () {
    expect(repository.search('"'), isEmpty);
    expect(repository.search('  '), isEmpty);
    expect(repository.search('*'), isEmpty);
  });

  test('بدايات الأجزاء: ٣٠ جزءاً تبدأ من الصفحة ١ وتنتهي عند الجزء ٣٠', () {
    final juzStarts = repository.juzStarts();
    expect(juzStarts.length, 30);
    expect(juzStarts.first.juz, 1);
    expect(juzStarts.first.page, 1);
    expect(juzStarts.last.juz, 30);
    expect(
      juzStarts.last.page,
      582,
    ); // الجزء ٣٠ يبدأ من صفحة ٥٨٢ في مصحف المدينة
    // الصفحات تتزايد مع الأجزاء.
    for (var i = 1; i < juzStarts.length; i++) {
      expect(juzStarts[i].page, greaterThan(juzStarts[i - 1].page));
    }
  });

  test('آيات القرآن بلا BOM في أول آية', () {
    final fatiha = repository.ayatOfSurah(1).first;
    expect(fatiha.text.startsWith('\uFEFF'), isFalse);
    expect(fatiha.text.startsWith('بِسْمِ'), isTrue);
  });
}
