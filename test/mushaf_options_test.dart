import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/quran/domain/quran_reciter.dart';
import 'package:yousuf/features/quran/presentation/mushaf_reader_screen.dart';
import 'package:yousuf/features/quran/presentation/quran_providers.dart';

/// خيارات القراءة: مقياس خط الوضع الأفقي، حفظ التلاوة أثناء التشغيل، والقارئ.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('تخطيط الصفحة: الخط يكبر مع العرض (كالمصحف الكبير)', () {
    final portrait = mushafLayout(width: 400, height: 800);
    expect(portrait.pageWidth, 400);
    expect(portrait.fontScale, 1.0);

    final landscape = mushafLayout(width: 800, height: 400);
    expect(landscape.pageWidth, 800);
    expect(landscape.fontScale, closeTo(800 / 420, 1e-9));

    // لا يصغر الخط أبداً على الشاشات الضيقة.
    expect(mushafLayout(width: 320, height: 640).fontScale, 1.0);
    // ويقف عند حد أقصى حتى لا يخرج النص عن السيطرة.
    expect(mushafLayout(width: 2000, height: 1200).fontScale, 2.2);
  });

  test('حفظ التلاوة أثناء التشغيل مفعّل افتراضياً ويُحفظ', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(cacheWhilePlayingProvider), isTrue);

    await container.read(cacheWhilePlayingProvider.notifier).set(false);
    expect(container.read(cacheWhilePlayingProvider), isFalse);
    expect(prefs.getBool('quran.cache_while_playing'), isFalse);

    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restored.dispose);
    expect(restored.read(cacheWhilePlayingProvider), isFalse);
  });

  test('اختيار القارئ يُحفظ ويُستعاد', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(quranReciterProvider).id, 'ar.minshawi');

    final target = kQuranReciters.firstWhere((r) => r.id == 'ar.husary');
    await container.read(quranReciterProvider.notifier).select(target);
    expect(prefs.getString('quran.reciter'), 'ar.husary');

    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restored.dispose);
    expect(restored.read(quranReciterProvider).id, 'ar.husary');
  });
}
