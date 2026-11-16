import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/kids/data/kids_repository.dart';
import 'package:yousuf/features/kids/domain/kid_profile.dart';
import 'package:yousuf/features/kids/presentation/kids_providers.dart';
import 'package:yousuf/features/kids/presentation/kids_screen.dart';

/// وضع الأطفال: الملفات، الرمز، ونجوم القرآن كامل (SPEC §7.9).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('النماذج والتخزين', () {
    test('الصورة الرمزية محصورة في القائمة', () {
      const profile = KidProfile(id: '1', name: 'يوسف', avatar: 99);
      expect(profile.avatarEmoji, kidAvatars.last);
    });

    test('ملف بلا اسم يأخذ اسماً افتراضياً', () {
      final profile = KidProfile.fromJson({'id': '1', 'name': '  '});
      expect(profile.name, 'صديق يوسف');
    });

    test('حفظ واسترجاع الملفات والرمز والتقدّم', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = KidsRepository(prefs);

      expect(repository.loadProfiles(), isEmpty);
      expect(repository.pin(), isNull);

      await repository.saveProfiles([
        const KidProfile(id: 'a', name: 'مريم', avatar: 3, stars: 2),
      ]);
      expect(repository.loadProfiles().single.name, 'مريم');
      expect(repository.loadProfiles().single.stars, 2);

      await repository.savePin('1234');
      expect(repository.pin(), '1234');
      await repository.savePin(null);
      expect(repository.pin(), isNull);

      await repository.saveProgress(
        'a',
        const KidProgress(completedSurahs: {78, 79}),
      );
      expect(repository.loadProgress('a').completedSurahs, {78, 79});
    });

    test('بيانات تالفة لا تُسقط التطبيق', () async {
      SharedPreferences.setMockInitialValues({'kids.profiles': 'x'});
      final prefs = await SharedPreferences.getInstance();
      expect(KidsRepository(prefs).loadProfiles(), isEmpty);
    });
  });

  group('الحالة', () {
    test('إتمام سورة يمنح نجمة واحدة فقط', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final profile = await container
          .read(kidProfilesProvider.notifier)
          .add('يوسف', 1);
      await container.read(activeKidProvider.notifier).select(profile);

      expect(
        await container.read(kidProgressProvider.notifier).completeSurah(78),
        isTrue,
      );
      expect(container.read(kidProgressProvider).isDone(78), isTrue);
      expect(container.read(kidProfilesProvider).single.stars, 1);

      expect(
        await container.read(kidProgressProvider.notifier).completeSurah(78),
        isFalse,
      );
      expect(container.read(kidProfilesProvider).single.stars, 1);
    });

    test('رمز غير رباعي لا يُحفظ', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      await container.read(kidPinProvider.notifier).set('12');
      expect(container.read(kidPinProvider), isNull);
    });
  });

  testWidgets('إنشاء ملف طفل يظهر في البوابة', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: KidsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('أهلاً بكم في ركن الأطفال'), findsOneWidget);
    await tester.tap(find.text('أنشئ ملف طفل'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'مريم');
    await tester.tap(find.text('إنشاء'));
    await tester.pumpAndSettle();

    // بعد الإنشاء ندخل مباشرة إلى شاشة الطفل.
    expect(find.textContaining('مريم'), findsWidgets);
    expect(find.textContaining('نجومك'), findsOneWidget);
    expect(find.text('القرآن'), findsOneWidget);
  });
}
