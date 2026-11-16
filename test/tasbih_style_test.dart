import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/tasbih/presentation/tasbih_style.dart';

/// شكل المسبحة: كلاسيكي (حبات) أو إلكتروني — يُحفظ بين التشغيلات.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('الافتراضي كلاسيكي، والتبديل يُحفظ ويُستعاد', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(tasbihStyleProvider), TasbihStyle.classic);

    await container.read(tasbihStyleProvider.notifier).toggle();
    expect(container.read(tasbihStyleProvider), TasbihStyle.electronic);
    expect(prefs.getString('tasbih.style'), 'electronic');

    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restored.dispose);
    expect(restored.read(tasbihStyleProvider), TasbihStyle.electronic);

    await restored.read(tasbihStyleProvider.notifier).set(TasbihStyle.classic);
    expect(prefs.getString('tasbih.style'), 'classic');
  });

  test('قيمة غير معروفة ترجع للكلاسيكي', () async {
    SharedPreferences.setMockInitialValues({'tasbih.style': 'weird'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(tasbihStyleProvider), TasbihStyle.classic);
  });
}
