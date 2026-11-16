import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/core/share/share_card.dart';
import 'package:yousuf/features/hadith/data/hadith_repository.dart';

/// الحديث المشحون (الأربعون النووية) وورقة المشاركة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('مستودع الحديث', () {
    late ContentDb content;
    late HadithRepository repository;

    setUpAll(() {
      content = ContentDb.openFile(
        File('assets/db/content.sqlite').absolute.path,
      );
      repository = HadithRepository(content);
    });

    tearDownAll(() => content.dispose());

    test('كتاب الأربعون النووية موجود بـ٤٢ حديثاً', () {
      final books = repository.books();
      expect(books, isNotEmpty);
      final nawawi = books.firstWhere((book) => book.slug == 'nawawi40');
      expect(nawawi.nameAr, 'الأربعون النووية');
      expect(nawawi.total, 42);
      expect(repository.hadithOfBook(nawawi.id).length, 42);
    });

    test('الحديث الأول هو «إنما الأعمال بالنيات»', () {
      final book = repository.books().first;
      final hadiths = repository.hadithOfBook(book.id);
      expect(hadiths.first.number, 1);
      expect(hadiths.first.text, contains('الْأَعْمَالُ'));
      expect(hadiths.first.text, contains('النِّيَّاتِ'));
      expect(hadiths.first.grade, isNull);
    });

    test('الترتيب تصاعدي والأرقام متصلة', () {
      final book = repository.books().first;
      final numbers = repository
          .hadithOfBook(book.id)
          .map((hadith) => hadith.number)
          .toList();
      expect(numbers.first, 1);
      expect(numbers.last, 42);
      expect(numbers, orderedEquals(List.generate(42, (index) => index + 1)));
    });
  });

  group('ورقة المشاركة', () {
    testWidgets('تعرض النص والمصدر وأزرار المشاركة', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShareContentSheet(
              text: 'إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ',
              source: 'الأربعون النووية — الحديث ١',
              title: 'من الأربعين النووية',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ'), findsOneWidget);
      expect(find.text('الأربعون النووية — الحديث ١'), findsOneWidget);
      expect(find.text('مشاركة كصورة'), findsOneWidget);
      expect(find.text('نص فقط'), findsOneWidget);
    });
  });
}
