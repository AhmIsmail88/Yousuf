/// نماذج الحديث — مطابقة لجداول content.sqlite (SPEC §5).
library;

class HadithBook {
  const HadithBook({
    required this.id,
    required this.slug,
    required this.nameAr,
    required this.total,
  });

  final int id;
  final String slug;
  final String nameAr;
  final int total;

  factory HadithBook.fromRow(Map<String, Object?> row) => HadithBook(
    id: row['id']! as int,
    slug: row['slug']! as String,
    nameAr: row['name_ar']! as String,
    total: (row['total'] as int?) ?? 0,
  );
}

class Hadith {
  const Hadith({
    required this.id,
    required this.bookId,
    required this.number,
    required this.text,
    this.grade,
    this.grader,
  });

  final int id;
  final int bookId;
  final int number;
  final String text;

  /// صحيح | حسن | ضعيف — فارغ في الأربعين النووية (كلها صحيحة).
  final String? grade;
  final String? grader;

  factory Hadith.fromRow(Map<String, Object?> row) => Hadith(
    id: row['id']! as int,
    bookId: row['book_id']! as int,
    number: row['number']! as int,
    text: (row['text_ar']! as String)
        .replaceAll('\uFEFF', '')
        .replaceAll('\u200F', '')
        .trim(),
    grade: row['grade'] as String?,
    grader: row['grader'] as String?,
  );
}
