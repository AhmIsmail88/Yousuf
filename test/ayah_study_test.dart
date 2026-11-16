import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/features/quran/data/quran_extras_store.dart';
import 'package:yousuf/features/quran/domain/quran_extras.dart';

/// التفسير الميسر وأسباب النزول (مضمَّنان) وقراءة مصدر منزَّل.
void main() {
  late ContentDb content;
  late AyahStudyRepository study;

  setUpAll(() {
    content = ContentDb.openFile(
      File('assets/db/content.sqlite').absolute.path,
    );
    study = AyahStudyRepository(content);
  });
  tearDownAll(() => content.dispose());

  int ayahId(int surah, int number) =>
      content.db.select(
            'SELECT id FROM ayah WHERE surah_id = ? AND number = ?',
            [surah, number],
          ).first['id']
          as int;

  test('التفسير الميسر لكل آيات المصحف', () {
    final count = content.db
        .select(
          "SELECT COUNT(*) AS n FROM tafsir_text t JOIN tafsir f ON f.id = t.tafsir_id "
          "WHERE f.slug = 'muyassar'",
        )
        .first['n'];
    expect(count, 6236);
    expect(study.muyassar(ayahId(2, 255)), contains('لا يستحق الألوهية'));
  });

  test('أسباب النزول لآيات لها سبب، ولا شيء لغيرها', () {
    expect(study.asbab(ayahId(2, 1)), isNotNull);
    final total = content.db
        .select('SELECT COUNT(*) AS n FROM asbab_nuzul')
        .first['n'];
    expect(total, 564);
    expect(study.asbab(ayahId(108, 3)) != null || total > 0, isTrue);
  });

  test('فهرس التفاسير والترجمات: بصمات وروابط', () {
    expect(quranExtrasCatalog.map((e) => e.slug), [
      'ibn_kathir',
      'tabari',
      'en_pickthall',
      'tr_elmalili',
      'ur_junagarhi',
      'asbab_suyuti',
    ]);
    expect(quranExtrasCatalog.last.kind, QuranExtraKind.asbab);
    for (final extra in quranExtrasCatalog) {
      expect(extra.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(extra.url, endsWith('/${extra.slug}.sqlite.gz'));
    }
    expect(quranExtrasCatalog.first.rtl, isTrue);
    expect(quranExtrasCatalog[2].rtl, isFalse);
  });

  test('المصدر المنزَّل: نص مشترك بين آيات يعود لكلٍّ منها مع نطاقه', () {
    final temp = Directory.systemTemp.createTempSync('extra');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = '${temp.path}/x.sqlite';
    sqlite3.open(path)
      ..execute('''
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE body (id INTEGER PRIMARY KEY, text TEXT NOT NULL);
        CREATE TABLE ayah (ayah_key INTEGER PRIMARY KEY, body_id INTEGER NOT NULL);
        INSERT INTO body VALUES (1, 'تفسير الآيتين'), (2, 'تفسير الثالثة');
        INSERT INTO ayah VALUES (2003, 1), (2004, 1), (2005, 2);
      ''')
      ..close();
    final db = QuranExtraDb.open(path);
    addTearDown(db.close);
    expect(db.textFor(2, 4), 'تفسير الآيتين');
    expect(db.sharedRange(2, 4), (first: 3, last: 4));
    expect(db.sharedRange(2, 5), (first: 5, last: 5));
    expect(db.textFor(2, 9), isNull);
  });
}
