import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/core/db/content_db.dart';

/// اسم نسخة المحتوى المحلية يتبع بصمة المحتوى لا حجمه: حجم SQLite مضاعف
/// لـ ٤٠٩٦ فقد يتغيّر المحتوى ويبقى الحجم، فتبقى الأجهزة على قاعدة قديمة.
void main() {
  test('اسم النسخة يحمل البصمة (أول ١٦ خانة)', () {
    expect(
      ContentDb.fileNameFor('1A890BD340836077d85e1a2af64f552e'),
      'content_1a890bd340836077.sqlite',
    );
  });

  test('بصمتان مختلفتان → اسمان مختلفان، والبصمة نفسها → الاسم نفسه', () {
    expect(ContentDb.fileNameFor('aaaa'), isNot(ContentDb.fileNameFor('bbbb')));
    expect(ContentDb.fileNameFor('abcd\n'), ContentDb.fileNameFor('abcd'));
  });

  test('البصمة المشحونة تطابق القاعدة المشحونة (شغّل finalize.py)', () {
    final db = File('assets/db/content.sqlite').readAsBytesSync();
    final stamp = File('assets/db/content.version').readAsStringSync().trim();
    expect(sha256.convert(db).toString(), stamp);
  });
}
