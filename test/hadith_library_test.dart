import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/features/hadith/data/hadith_book_store.dart';
import 'package:yousuf/features/hadith/data/hadith_repository.dart';
import 'package:yousuf/features/hadith/domain/hadith_library.dart';

/// مكتبة الحديث: الأربعينات المضمَّنة، وقراءة كتاب منزَّل بصيغة
/// `hadith_books.py` (أبواب، درجات، بحث).
void main() {
  test('الأربعينات الثلاث مع التطبيق', () {
    final content = ContentDb.openFile(
      File('assets/db/content.sqlite').absolute.path,
    );
    addTearDown(content.dispose);
    final books = HadithRepository(content).books();
    expect(books.map((book) => book.slug), [
      'nawawi40',
      'qudsi40',
      'dehlawi40',
    ]);
    expect(books[1].total, 40);
    expect(books[2].total, 40);
  });

  test('فهرس الكتب التسعة: بصمات وأحجام وروابط', () {
    expect(hadithCatalog, hasLength(7));
    for (final book in hadithCatalog) {
      expect(book.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(book.bytes, greaterThan(100000));
      expect(book.url, endsWith('/${book.slug}.sqlite.gz'));
    }
    expect(hadithCollection('bukhari')!.graded, isFalse);
    expect(hadithCollection('abudawud')!.graded, isTrue);
  });

  group('كتاب منزَّل', () {
    late Directory temp;
    late HadithBookDb book;

    setUpAll(() {
      temp = Directory.systemTemp.createTempSync('hadith_book');
      final path = '${temp.path}/sample.sqlite';
      final db = sqlite3.open(path);
      // نفس مخطط hadith_books.py (SCHEMA).
      db.execute('''
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE section (id INTEGER PRIMARY KEY, name_en TEXT NOT NULL,
          first_number REAL, last_number REAL, total INTEGER NOT NULL);
        CREATE TABLE hadith (id INTEGER PRIMARY KEY, number TEXT NOT NULL,
          arabic_number TEXT, section_id INTEGER NOT NULL, text TEXT NOT NULL);
        CREATE TABLE grade (hadith_id INTEGER NOT NULL, grade_ar TEXT NOT NULL,
          grade_raw TEXT NOT NULL, category TEXT NOT NULL,
          grader_ar TEXT NOT NULL);
        CREATE VIRTUAL TABLE hadith_fts USING fts5(body, content='',
          columnsize=0, detail=column);
        INSERT INTO meta VALUES ('slug', 'sample');
        INSERT INTO section VALUES (1, 'Revelation', 1, 2, 2);
        INSERT INTO section VALUES (2, 'Belief', 3, 3, 1);
        INSERT INTO hadith VALUES (1, '1', '1', 1, 'إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ');
        INSERT INTO hadith VALUES (2, '2', '2', 1, 'الدِّينُ النَّصِيحَةُ');
        INSERT INTO hadith VALUES (3, '3.1', '3', 2, 'بُنِيَ الْإِسْلَامُ عَلَى خَمْسٍ');
        INSERT INTO hadith_fts (rowid, body) VALUES (1, 'انما الاعمال اعمال بالنيات النيات نيات');
        INSERT INTO hadith_fts (rowid, body) VALUES (2, 'الدين دين النصيحه نصيحه');
        INSERT INTO hadith_fts (rowid, body) VALUES (3, 'بني الاسلام اسلام علي خمس');
        INSERT INTO grade VALUES (1, 'صحيح', 'Sahih', 'sahih', 'الألباني');
        INSERT INTO grade VALUES (1, 'إسناده صحيح', 'Isnaad Sahih', 'sahih', 'زبير علي زئي');
        INSERT INTO grade VALUES (2, 'ضعيف', 'Daif', 'daif', 'الألباني');
      ''');
      db.close();
      book = HadithBookDb.open(path);
    });

    tearDownAll(() {
      book.close();
      temp.deleteSync(recursive: true);
    });

    test('الأبواب بترتيبها ومعها نطاق الأحاديث', () {
      final sections = book.sections();
      expect(sections.map((s) => s.nameEn), ['Revelation', 'Belief']);
      expect(sections.first.first, 1);
      expect(sections.first.last, 2);
    });

    test('أحاديث الباب ومعها درجاتها ومحققوها', () {
      final hadiths = book.inSection(1);
      expect(hadiths, hasLength(2));
      expect(hadiths.first.grades.map((g) => g.grader), [
        'الألباني',
        'زبير علي زئي',
      ]);
      expect(hadiths[1].grades.single.category, 'daif');
    });

    test('رقم الحديث غير الصحيح يبقى كما هو', () {
      expect(book.inSection(2).single.number, '3.1');
    });

    test('البحث يتجاهل التشكيل والهمزات ويطابق بادئة الكلمة', () {
      expect(book.search('الأعمالُ بالنية').map((h) => h.id), [1]);
      expect(book.search('الإسلام').map((h) => h.id), [3]);
      // «النيات» تجد «بالنيات» (الفهرس يحوي الكلمة بلا سوابقها).
      expect(book.search('النيات').map((h) => h.id), [1]);
      expect(book.search('غير موجود'), isEmpty);
      expect(book.search('ا'), isEmpty);
    });
  });
}
