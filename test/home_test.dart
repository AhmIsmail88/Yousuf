import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/app/app.dart';
import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/core/utils/arabic_dates.dart';
import 'package:yousuf/core/utils/arabic_digits.dart';
import 'package:yousuf/core/utils/time_format.dart';
import 'package:yousuf/features/prayer/data/prayer_settings_repository.dart';
import 'package:yousuf/features/prayer/domain/prayer_times_calculator.dart';
import 'package:yousuf/features/prayer/presentation/prayer_providers.dart';
import 'package:yousuf/features/quran/presentation/quran_providers.dart';

/// اختبارات الرئيسية بعد إضافة التاريخ الهجري والبطاقة الذكية (SPEC §7.2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('الرئيسية تعرض التاريخ الهجري وبطاقة حسب الوقت', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          splashEnabledProvider.overrideWithValue(false),
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

    final now = DateTime.now();
    final hijri = hijriDay(now)!;
    expect(
      find.text(toHindiDigits(hijri.formatted)),
      findsOneWidget,
      reason: 'التاريخ الهجري في بطاقة الصلاة القادمة',
    );

    // البطاقة الذكية المتوقعة حسب الوقت/اليوم — نفس منطق الشاشة.
    const settings = PrayerSettings();
    final times = PrayerTimesCalculator.forDate(
      location: settings.location,
      date: now,
    );
    final nowMinutes = now.hour * 60 + now.minute;
    final String expected;
    if (isFriday(now)) {
      expected = 'سورة الكهف';
    } else if (hijri.isWhiteDay) {
      expected = 'الأيام البيض';
    } else if (nowMinutes >= TimeFormat.minutesOfDay(times.fajr) &&
        nowMinutes < TimeFormat.minutesOfDay(times.dhuhr)) {
      expected = 'أذكار الصباح';
    } else if (nowMinutes >= TimeFormat.minutesOfDay(times.asr) &&
        nowMinutes < TimeFormat.minutesOfDay(times.isha)) {
      expected = 'أذكار المساء';
    } else {
      expected = 'وردك من القرآن';
    }

    final smartCard = find.text(expected);
    await tester.scrollUntilVisible(
      smartCard,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(smartCard, findsOneWidget);

    // بطاقة الورد أسفل الصفحة.
    final reading = find.text('متابعة القراءة');
    await tester.scrollUntilVisible(
      reading,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(reading, findsOneWidget);
  });
}
