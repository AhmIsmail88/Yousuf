import '../../../core/db/content_db.dart';
import '../domain/hadith_models.dart';

/// قراءة الحديث من content.sqlite — بلا شبكة (SPEC §10).
class HadithRepository {
  HadithRepository(this._content);

  final ContentDb _content;

  List<HadithBook> books() => _content.db
      .select('SELECT * FROM hadith_book ORDER BY id')
      .map((row) => HadithBook.fromRow(row))
      .toList(growable: false);

  List<Hadith> hadithOfBook(int bookId) => _content.db
      .select('SELECT * FROM hadith WHERE book_id = ? ORDER BY number', [
        bookId,
      ])
      .map((row) => Hadith.fromRow(row))
      .toList(growable: false);

  Hadith? hadith(int id) {
    final rows = _content.db.select('SELECT * FROM hadith WHERE id = ?', [id]);
    return rows.isEmpty ? null : Hadith.fromRow(rows.first);
  }
}
