/// نماذج الأذكار — Dart خالص، مطابقة لجداول content.sqlite (SPEC §5).
library;

/// قسم من أقسام الأذكار (الصباح، المساء، النوم…).
class DhikrCategory {
  const DhikrCategory({
    required this.id,
    required this.slug,
    required this.nameAr,
    required this.sort,
  });

  final int id;
  final String slug;
  final String nameAr;
  final int sort;

  factory DhikrCategory.fromRow(Map<String, Object?> row) => DhikrCategory(
    id: row['id']! as int,
    slug: row['slug']! as String,
    nameAr: row['name']! as String,
    sort: (row['sort'] as int?) ?? 0,
  );
}

/// ذكر واحد: النص، عدد التكرار، المصدر، والفضل إن وُجد.
class Dhikr {
  const Dhikr({
    required this.id,
    required this.categoryId,
    required this.text,
    required this.repeatCount,
    this.source,
    this.virtue,
    this.instruction,
  });

  final int id;
  final int categoryId;
  final String text;
  final int repeatCount;
  final String? source;
  final String? virtue;

  /// تعليمة المصدر المنفصلة عن نص الذكر («ثلاث مرات»، «إذا أصبح»…).
  final String? instruction;

  factory Dhikr.fromRow(Map<String, Object?> row) => Dhikr(
    id: row['id']! as int,
    categoryId: row['category_id']! as int,
    text: _clean(row['text']! as String),
    repeatCount: (row['repeat_count'] as int?) ?? 1,
    source: row['source'] as String?,
    virtue: row['virtue'] as String?,
    instruction: row.containsKey('instruction')
        ? row['instruction'] as String?
        : null,
  );

  /// يزيل BOM وأي علامات اتجاه قد تأتي من المصدر.
  static String _clean(String raw) =>
      raw.replaceAll('\uFEFF', '').replaceAll('\u200F', '').trim();
}
