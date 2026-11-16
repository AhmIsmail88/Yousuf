import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/app/app.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/cities/data/cities_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const riyadh = City(
    id: 108410,
    nameAr: 'الرياض',
    nameEn: 'Riyadh',
    countryCode: 'SA',
    latitude: 24.7136,
    longitude: 46.6753,
    timezoneId: 'Asia/Riyadh',
    population: 7641670,
  );

  testWidgets('الترحيب يبدأ باللغة ثم ينتقل لاختيار المدينة', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          splashEnabledProvider.overrideWithValue(false),
          // قائمة صغيرة بدل الأصل الكبير: pumpAndSettle يعمل بزمن وهمي
          // فلا تكتمل قراءة الملفات الحقيقية (التحميل الحقيقي يُختبر في cities_test).
          citiesRepositoryProvider.overrideWith(
            (ref) async => CitiesRepository(const [riyadh]),
          ),
        ],
        child: const YousufApp(),
      ),
    );
    await tester.pumpAndSettle();

    // الخطوة 1: اللغة
    expect(find.text('أهلاً بك في يوسف'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);

    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    // الخطوة 2: المدينة
    expect(find.text('أين أنت؟'), findsOneWidget);
    expect(find.text('الرياض'), findsWidgets);
  });
}
