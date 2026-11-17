import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:yousuf/features/history/data/library_store.dart';
import 'package:yousuf/features/history/domain/library_catalog.dart';

/// كتب المكتبة: الفهرس، وقراءة ملف كتاب منزَّل بصيغة library_books.py.
void main() {
  test('فهرس المكتبة: الكتب ببصمات وروابط وتبويبات', () {
    expect(libraryCatalog.map((b) => b.slug), contains('rahiq_makhtum'));
    expect(libraryCatalog, hasLength(17));
    for (final book in libraryCatalog) {
      expect(book.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(book.url, endsWith('/${book.slug}.sqlite.gz'));
      expect(book.pages, greaterThan(10));
      expect(librarySections, contains(book.section));
    }
    expect(
      libraryCatalog.where((b) => b.section == 'الأذكار').map((b) => b.slug),
      ['adhkar_nawawi', 'kalim_tayyib', 'wabil_sayyib'],
    );
  });

  test('الفهرس مطابق لناتج library_books.py (البصمة والحجم والتبويب)', () {
    final file = File('tools/content_builder/out/library_books/catalog.json');
    final books = (jsonDecode(file.readAsStringSync()) as Map)['books'] as List;
    expect(books, hasLength(libraryCatalog.length));
    for (final raw in books.cast<Map<String, dynamic>>()) {
      final book = libraryCatalog.firstWhere((b) => b.slug == raw['slug']);
      expect(book.sha256, raw['sha256'], reason: book.slug);
      expect(book.bytes, raw['bytes'], reason: book.slug);
      expect(book.section, raw['section'], reason: book.slug);
    }
  });

  test('كتاب منزَّل: الفصول وأول صفحة لكل فصل، والصفحة مع فصلها', () {
    final temp = Directory.systemTemp.createTempSync('library');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = '${temp.path}/b.sqlite';
    sqlite3.open(path)
      ..execute('''
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE chapter (id INTEGER PRIMARY KEY, title TEXT NOT NULL,
          volume TEXT, first_page INTEGER NOT NULL);
        CREATE TABLE page (id INTEGER PRIMARY KEY, volume TEXT, page_num TEXT,
          chapter_id INTEGER NOT NULL, text TEXT NOT NULL);
        INSERT INTO meta VALUES ('license', 'ملك عام');
        INSERT INTO chapter VALUES (1, 'مولده', '1', 1), (2, 'هجرته', '1', 3);
        INSERT INTO page VALUES (1, '1', '10', 1, 'أ'), (2, '1', '11', 1, 'ب'),
          (3, '1', '12', 2, 'ج');
      ''')
      ..close();
    final db = LibraryBookDb.open(path);
    addTearDown(db.close);
    expect(db.pageCount, 3);
    expect(db.chapters().map((c) => c.firstPage), [1, 3]);
    final page = db.page(2)!;
    expect(page.chapter, 'مولده');
    expect(page.pageNum, '11');
    expect(db.page(3)!.chapter, 'هجرته');
    expect(db.page(9), isNull);
    expect(db.meta('license'), 'ملك عام');
  });
}
