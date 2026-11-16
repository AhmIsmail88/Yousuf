import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/features/adhkar/data/adhkar_repository.dart';

/// اختبارات قراءة الأذكار على قاعدة مؤقتة بنفس سكيمة content.sqlite.
void main() {
  late String dbPath;
  late ContentDb content;
  late AdhkarRepository repository;

  setUpAll(() {
    dbPath = '${Directory.systemTemp.path}/yousuf_adhkar_test.sqlite';
    if (File(dbPath).existsSync()) File(dbPath).deleteSync();
    final db = sqlite3.open(dbPath);
    db.execute('''
      CREATE TABLE dhikr_category (
        id INTEGER PRIMARY KEY,
        slug TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        sort INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE dhikr (
        id INTEGER PRIMARY KEY,
        category_id INTEGER NOT NULL REFERENCES dhikr_category(id),
        text TEXT NOT NULL,
        repeat_count INTEGER NOT NULL DEFAULT 1,
        source TEXT,
        virtue TEXT,
        audio_ref TEXT
      );
    ''');
    db.execute(
      'INSERT INTO dhikr_category (id, slug, name, sort) VALUES (1, ?, ?, 2)',
      ['morning', 'أذكار الصباح'],
    );
    db.execute(
      'INSERT INTO dhikr_category (id, slug, name, sort) VALUES (2, ?, ?, 1)',
      ['quranic', 'أدعية من القرآن'],
    );
    // BOM في أول النص — يجب أن يُزال عند القراءة.
    db.execute(
      'INSERT INTO dhikr (id, category_id, text, repeat_count, source) '
      'VALUES (1, 1, ?, 3, ?)',
      ['\uFEFFسبحان الله وبحمده', 'رواه مسلم'],
    );
    db.execute(
      'INSERT INTO dhikr (id, category_id, text, repeat_count, source, virtue) '
      'VALUES (2, 1, ?, 1, ?, ?)',
      ['اللهم بك أصبحنا', 'رواه أبو داود', 'من قالها حين يصبح'],
    );
    db.execute(
      'INSERT INTO dhikr (id, category_id, text, repeat_count, source) '
      'VALUES (3, 2, ?, 1, ?)',
      ['رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً', 'سورة البقرة · آية 201'],
    );
    db.close();

    content = ContentDb.openFile(dbPath);
    repository = AdhkarRepository(content);
  });

  tearDownAll(() {
    content.dispose();
    if (File(dbPath).existsSync()) File(dbPath).deleteSync();
  });

  test('الأقسام مرتبة حسب sort', () {
    final categories = repository.categories();
    expect(categories.length, 2);
    expect(categories.first.slug, 'quranic');
    expect(categories.last.slug, 'morning');
  });

  test('أذكار القسم بالترتيب مع التكرار والمصدر', () {
    final dhikr = repository.dhikrOf(1);
    expect(dhikr.length, 2);
    expect(dhikr.first.repeatCount, 3);
    expect(dhikr.first.source, 'رواه مسلم');
    expect(dhikr.last.virtue, 'من قالها حين يصبح');
  });

  test('BOM يُزال من النص', () {
    expect(repository.dhikrOf(1).first.text, 'سبحان الله وبحمده');
  });

  test('hasContent يعكس وجود أذكار', () {
    expect(repository.hasContent, isTrue);
  });

  test('قسم بلا أذكار يرجع قائمة فارغة', () {
    expect(repository.dhikrOf(99), isEmpty);
  });
}
