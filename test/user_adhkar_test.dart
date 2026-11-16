import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/features/adhkar/data/user_adhkar_store.dart';
import 'package:yousuf/features/adhkar/domain/user_dhikr.dart';

/// أذكار المستخدم: التحقق من المدخلات والحفظ المحلي (SPEC §10).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('إنشاء ذكر يرفض النص الفارغ', () {
    expect(() => UserDhikr.create(text: '   ', repeat: 1), throwsArgumentError);
  });

  test('التكرار محصور بين ١ و١٠٠', () {
    final low = UserDhikr.create(text: 'سبحان الله', repeat: 0);
    expect(low.repeat, 1);
    final high = UserDhikr.create(text: 'سبحان الله', repeat: 500);
    expect(high.repeat, kUserDhikrMaxRepeat);
  });

  test('المصدر الفارغ يصبح null', () {
    final dhikr = UserDhikr.create(text: 'سبحان الله', repeat: 3, source: '  ');
    expect(dhikr.source, isNull);
    expect(dhikr.repeat, 3);
  });

  test('حفظ واسترجاع قائمة أذكار المستخدم', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = UserAdhkarStore(prefs);

    expect(store.load(), isEmpty);

    final first = UserDhikr.create(text: 'أستغفر الله', repeat: 100);
    final second = UserDhikr.create(
      text: 'اللهم صل على محمد',
      repeat: 10,
      source: 'رواه مسلم',
    );
    await store.save([first, second]);

    final loaded = store.load();
    expect(loaded.length, 2);
    expect(loaded.first.text, 'أستغفر الله');
    expect(loaded.first.repeat, 100);
    expect(loaded.last.source, 'رواه مسلم');
  });

  test('بيانات تالفة ترجع قائمة فارغة بلا انهيار', () async {
    SharedPreferences.setMockInitialValues({'adhkar.user': 'not json'});
    final prefs = await SharedPreferences.getInstance();
    expect(UserAdhkarStore(prefs).load(), isEmpty);
  });

  test('تعديل ذكر يحفظ الحقول الجديدة ويبقي المعرّف', () {
    final dhikr = UserDhikr.create(text: 'سبحان الله', repeat: 33);
    final edited = dhikr.copyWith(text: 'سبحان الله وبحمده', repeat: 100);
    expect(edited.id, dhikr.id);
    expect(edited.text, 'سبحان الله وبحمده');
    expect(edited.repeat, 100);
  });
}
