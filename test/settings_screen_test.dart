import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/prayer/data/prayer_settings_repository.dart';
import 'package:yousuf/features/prayer/presentation/prayer_providers.dart';
import 'package:yousuf/features/settings/presentation/settings_screen.dart';
import 'package:yousuf/l10n/generated/app_localizations.dart';

/// اختبارات شاشة الإعدادات: العرض، وتغيير طريقة الحساب والإزاحة الهجرية
/// مع التحقق من وصول القيمة إلى التخزين المحلي (SPEC §8).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> pumpSettings(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          prayerSettingsProvider.overrideWith(
            (ref) async => const PrayerSettings(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ar'), Locale('en')],
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('كل مجموعات الإعدادات ظاهرة', (tester) async {
    await pumpSettings(tester);

    for (final title in [
      'الموقع',
      'الحساب',
      'الأذان',
      'التقويم',
      'المظهر واللغة',
      'جاهزية الأذان',
      'عن التطبيق',
    ]) {
      final finder = find.text(title);
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(finder, findsOneWidget, reason: title);
    }
  });

  testWidgets('تغيير طريقة الحساب يُحفظ فوراً في التفضيلات', (tester) async {
    final prefs = await pumpSettings(tester);

    final methodTile = find.text('طريقة الحساب');
    await tester.scrollUntilVisible(
      methodTile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(methodTile);
    await tester.pumpAndSettle();

    // القيمة الحالية أم القرى؛ نختار الهيئة المصرية.
    final egyptian = find.text('الهيئة المصرية العامة للمساحة').last;
    await tester.ensureVisible(egyptian);
    await tester.tap(egyptian);
    await tester.pumpAndSettle();

    expect(prefs.getString('prayer.method'), 'egyptian');
    expect(find.text("تم الحفظ"), findsOneWidget);
  });

  testWidgets('زر الإزاحة الهجرية يزيد القيمة ويحفظها', (tester) async {
    final prefs = await pumpSettings(tester);

    final hijriTile = find.text('إزاحة التاريخ الهجري');
    await tester.scrollUntilVisible(
      hijriTile,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    final addButton = find.byIcon(Icons.add_circle_outline).first;
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(prefs.getInt('prayer.hijri_offset'), 1);
  });
}
