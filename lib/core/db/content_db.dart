import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// قاعدة المحتوى `content.sqlite` — للقراءة فقط (SPEC §5).
///
/// في الإنتاج: تُنسخ من الأصول إلى مجلد دعم التطبيق ثم تُفتح للقراءة فقط.
/// **اسم النسخة المحلية يحمل بصمة المحتوى** (`assets/db/content.version`،
/// SHA-256 يكتبها `tools/content_builder/finalize.py`). أي تغيير في المحتوى
/// يغيّر البصمة فتُنسخ القاعدة الجديدة وتُحذف القديمة — حتى لو بقي الحجم
/// نفسه (حجم SQLite مضاعف لـ ٤٠٩٦ فلم يكن معياراً صالحاً).
///
/// والقاعدة الكبيرة لا تُقرأ من الأصول إلا عند الحاجة للنسخ: الفتح العادي
/// يقرأ ملف البصمة الصغير فقط.
///
/// في الاختبارات: افتح الملف مباشرة بـ [ContentDb.openFile].
class ContentDb {
  ContentDb._(this.db);

  final Database db;

  static const String assetPath = 'assets/db/content.sqlite';
  static const String stampPath = 'assets/db/content.version';

  /// اسم ملف النسخة المحلية — يعتمد على بصمة المحتوى.
  static String fileNameFor(String stamp) {
    final clean = stamp.trim().toLowerCase().replaceAll(
      RegExp('[^0-9a-f]'),
      '',
    );
    final short = clean.length > 16 ? clean.substring(0, 16) : clean;
    return 'content_$short.sqlite';
  }

  /// يفتح نسخة التطبيق (ينسخ الأصل عند أول تشغيل أو عند تغيّر المحتوى).
  static Future<ContentDb> openFromAsset() async {
    final directory = await getApplicationSupportDirectory();
    final stamp = await _readStamp();
    final file = File('${directory.path}/${fileNameFor(stamp)}');

    if (!file.existsSync() || file.lengthSync() == 0) {
      final asset = await rootBundle.load(assetPath);
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      // كتابة ذرّية: ملف مؤقت ثم إعادة تسمية — لا نسخة ناقصة إن قُطع التطبيق.
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      await _removeOldCopies(directory, keep: file.path);
    }

    return ContentDb._(sqlite3.open(file.path, mode: OpenMode.readOnly));
  }

  /// بصمة المحتوى المشحون (ملف صغير). إن غاب (بناء قديم) نستخدم الحجم.
  static Future<String> _readStamp() async {
    try {
      final stamp = (await rootBundle.loadString(stampPath)).trim();
      if (stamp.isNotEmpty) return stamp;
    } catch (_) {
      debugPrint('[Yousuf] لا توجد بصمة للمحتوى — استخدام الحجم');
    }
    final asset = await rootBundle.load(assetPath);
    return 'size${asset.lengthInBytes.toRadixString(16)}';
  }

  /// يحذف نسخ المحتوى القديمة (لا يمسّ أي ملف آخر).
  static Future<void> _removeOldCopies(
    Directory directory, {
    required String keep,
  }) async {
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('content_')) continue;
      if (!name.endsWith('.sqlite') && !name.endsWith('.tmp')) continue;
      if (entity.path == keep) continue;
      try {
        entity.deleteSync();
      } catch (_) {
        // ملف مقفل من عملية أخرى — يُترك ولا يضرّ.
      }
    }
  }

  /// يفتح ملفاً على القرص مباشرة — للاختبارات والأدوات.
  static ContentDb openFile(String path) =>
      ContentDb._(sqlite3.open(path, mode: OpenMode.readOnly));

  /// إصدار المحتوى (content_version) — للمقارنة عند التحديث.
  String? contentVersion() {
    final rows = db.select('SELECT version FROM content_version LIMIT 1');
    return rows.isEmpty ? null : rows.first['version'] as String?;
  }

  /// اسم المراجع الشرعي الذي وقّع المحتوى — null يعني «قيد المراجعة» (SPEC §4).
  String? reviewedBy() {
    final rows = db.select('SELECT reviewed_by FROM content_version LIMIT 1');
    if (rows.isEmpty) return null;
    final value = rows.first['reviewed_by'] as String?;
    return (value == null || value.trim().isEmpty) ? null : value;
  }

  void dispose() => db.close();
}
