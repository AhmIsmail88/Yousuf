import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/kids/presentation/kid_learning_screens.dart';
import 'package:yousuf/features/quran/presentation/hifz_providers.dart';
import 'package:yousuf/features/quran/presentation/quran_providers.dart';

/// وضع الحفظ: القرار، الحفظ المحلي، وفهرس القرآن الكامل في وضع الطفل.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('وضع الحفظ', () {
    test('قرار الإخفاء: مخفي حتى الكشف', () {
      expect(isAyahMasked(hifz: false, revealed: {}, ayahId: 1), isFalse);
      expect(isAyahMasked(hifz: true, revealed: {}, ayahId: 1), isTrue);
      expect(isAyahMasked(hifz: true, revealed: {1}, ayahId: 1), isFalse);
      expect(isAyahMasked(hifz: true, revealed: {1}, ayahId: 2), isTrue);
    });

    test('التشغيل يُحفظ محلياً ويُسترجع', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(hifzModeProvider), isFalse);
      await container.read(hifzModeProvider.notifier).toggle();
      expect(container.read(hifzModeProvider), isTrue);
      expect(prefs.getBool(hifzModeKey), isTrue);

      final second = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(second.dispose);
      expect(second.read(hifzModeProvider), isTrue);
    });
  });

  group('فهرس القرآن للطفل', () {
    late ContentDb content;

    setUpAll(() {
      content = ContentDb.openFile(
        File('assets/db/content.sqlite').absolute.path,
      );
    });

    tearDownAll(() => content.dispose());

    testWidgets('يعرض كل السور ويُصفّي بالجزء', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            contentDbProvider.overrideWith((ref) async => content),
          ],
          child: const MaterialApp(home: KidQuranBrowserScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // «كل السور» تعرض الفاتحة (الجزء 1) والبقرة.
      expect(find.text('الفاتحة'), findsOneWidget);
      expect(find.text('البقرة'), findsOneWidget);

      // اختيار الجزء ٣٠ يعرض سور جزء عمّ فقط.
      await tester.tap(find.widgetWithText(ChoiceChip, '٣٠'));
      await tester.pumpAndSettle();
      // اسم السورة كما في المصدر (Tanzil): «النبإ».
      expect(find.text('النبإ'), findsOneWidget);
      expect(find.text('الفاتحة'), findsNothing);
    });

    testWidgets('زر «اكشف» يظهر الآيات عند غياب محرّك التعرّف', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            contentDbProvider.overrideWith((ref) async => content),
          ],
          child: const MaterialApp(home: KidQuranBrowserScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('الفاتحة'));
      await tester.pumpAndSettle();

      // الوضع الافتراضي «قراءة واستماع»: الآيات ظاهرة.
      expect(find.textContaining('ٱلْحَمْدُ'), findsWidgets);

      // وضع التسميع: الفاتحة مخفية ولا يظهر نصها.
      await tester.tap(find.text('تسميع ⭐'));
      await tester.pumpAndSettle();
      expect(find.textContaining('بِسۡمِ'), findsNothing);
      expect(find.text('اقرأ الآية ثم اضغط 🎤'), findsWidgets);

      // على سطح المكتب لا يوجد محرّك تعرّف → زر «اكشف» متاح.
      await tester.tap(find.byTooltip('اقرأ بصوتك').first);
      await tester.pumpAndSettle();
      expect(find.text('اكشف'), findsOneWidget);

      await tester.tap(find.text('اكشف'));
      await tester.pumpAndSettle();
      expect(find.text('اقرأ الآية ثم اضغط 🎤'), findsNothing);
    });
  });
}
