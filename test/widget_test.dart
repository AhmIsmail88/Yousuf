import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/app/app.dart';
import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/prayer/data/prayer_settings_repository.dart';
import 'package:yousuf/features/prayer/presentation/prayer_providers.dart';
import 'package:yousuf/features/quran/presentation/quran_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('التطبيق يُبنى مع شريط التنقل السفلي بأربعة تبويبات', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          splashEnabledProvider.overrideWithValue(false),
          // تجنّب plugins غير المتاحة في بيئة الاختبار.
          prayerSettingsProvider.overrideWith(
            (ref) async => const PrayerSettings(),
          ),
          lastReadPageProvider.overrideWith((ref) async => 1),
          contentDbProvider.overrideWith(
            (ref) async => ContentDb.openFile('assets/db/content.sqlite'),
          ),
        ],
        child: const YousufApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    // العربية افتراضية (SPEC §1)
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('القرآن'), findsOneWidget);
    expect(find.text('الأذكار'), findsWidgets); // التبويب + اختصار الرئيسية
    expect(find.text('صلاتي'), findsOneWidget);
  });
}
