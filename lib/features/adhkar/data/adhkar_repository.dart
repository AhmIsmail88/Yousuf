import '../../../core/db/content_db.dart';
import '../domain/adhkar_models.dart';

/// قراءة الأذكار من content.sqlite — بلا شبكة (SPEC §10).
///
/// الجداول تُملأ من `tools/content_builder/adhkar.py` بعد المراجعة الشرعية،
/// فإن كانت فارغة تعرض الشاشة حالة «قيد المراجعة» بدل محتوى غير موثوق.
class AdhkarRepository {
  AdhkarRepository(this._content);

  final ContentDb _content;

  /// الأقسام مرتبة حسب `sort`.
  List<DhikrCategory> categories() => _content.db
      .select('SELECT * FROM dhikr_category ORDER BY sort, id')
      .map((row) => DhikrCategory.fromRow(row))
      .toList(growable: false);

  /// أذكار قسم واحد بالترتيب.
  List<Dhikr> dhikrOf(int categoryId) => _content.db
      .select('SELECT * FROM dhikr WHERE category_id = ? ORDER BY id', [
        categoryId,
      ])
      .map((row) => Dhikr.fromRow(row))
      .toList(growable: false);

  /// هل يوجد أي محتوى أذكار معتمد؟ (لعرض الحالة الفارغة بدقة)
  bool get hasContent =>
      _content.db.select('SELECT 1 FROM dhikr LIMIT 1').isNotEmpty;

  /// عدد الأذكار في كل قسم — لفهرس الأبواب.
  Map<int, int> countsByCategory() => {
    for (final row in _content.db.select(
      'SELECT category_id, COUNT(*) AS total FROM dhikr GROUP BY category_id',
    ))
      row['category_id']! as int: row['total']! as int,
  };
}
