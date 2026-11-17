import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/features/adhkar/data/adhkar_repository.dart';

/// تبويب الأذكار على «حصن المسلم» (hisn_sellam.py): الأبواب المميزة موجودة،
/// والصباح والمساء بلفظ كل منهما، والآيات الكاملة من نص المصحف.
void main() {
  late ContentDb content;
  late AdhkarRepository repository;
  setUpAll(() {
    content = ContentDb.openFile(
      File('assets/db/content.sqlite').absolute.path,
    );
    repository = AdhkarRepository(content);
  });
  tearDownAll(() => content.dispose());

  // مقارنة بلا تشكيل: ترتيب الحركات قد يختلف بين المصدر ونص الاختبار.
  String bare(String text) => text.replaceAll(RegExp('[ً-ْٰـ]'), '');

  List<String> textsOf(String slug) {
    final category = repository.categories().firstWhere((c) => c.slug == slug);
    return repository.dhikrOf(category.id).map((d) => d.text).toList();
  }

  test('الأبواب المميزة كلها موجودة وغير فارغة', () {
    for (final slug in const [
      'quranic',
      'morning',
      'evening',
      'wake',
      'sleep',
      'after_prayer',
      'distress',
      'travel',
    ]) {
      expect(textsOf(slug), isNotEmpty, reason: slug);
    }
    // ١٣٣ باباً من حصن المسلم + أدعية من القرآن.
    expect(repository.categories(), hasLength(134));
  });

  test('الصباح والمساء بلفظ كل منهما', () {
    final morning = textsOf('morning');
    final evening = textsOf('evening');
    expect(morning.any((t) => bare(t).startsWith('أصبحنا')), isTrue);
    expect(evening.any((t) => bare(t).startsWith('أمسينا')), isTrue);
    expect(evening.any((t) => bare(t).startsWith('أصبحنا')), isFalse);
    // تمهيد الباب «الحمد لله وحده…» ليس ذكراً.
    expect(bare(morning.first).contains('الحمد لله وحده'), isFalse);
  });

  test('آية الكرسي في أذكار الصباح بنص المصحف ورقمها', () {
    final kursi = textsOf('morning').firstWhere((t) => t.contains('﴿٢٥٥﴾'));
    expect(bare(kursi), contains('ٱلحى ٱلقيوم'));
    expect(kursi, isNot(contains('{')));
  });

  test('التسبيح بعد الصلاة: ٣٣ ثم تمام المائة', () {
    final category = repository.categories().firstWhere(
      (c) => c.slug == 'after_prayer',
    );
    final items = repository.dhikrOf(category.id);
    final tasbih = items.indexWhere((d) => d.repeatCount == 33);
    expect(tasbih, isNonNegative);
    expect(items[tasbih + 1].repeatCount, 1);
    expect(bare(items[tasbih + 1].text), startsWith('لا إله إلا الله'));
  });
}
