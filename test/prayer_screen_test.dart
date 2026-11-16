import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/app/app.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('شاشة صلاتي تعرض المواقيت الستة والضحى والثلث الأخير', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          splashEnabledProvider.overrideWithValue(false),
        ],
        child: const YousufApp(),
      ),
    );
    await tester.pumpAndSettle();

    // الانتقال إلى تبويب صلاتي (العربية افتراضية).
    await tester.tap(find.text('صلاتي'));
    await tester.pumpAndSettle();

    for (final label in [
      'الفجر',
      'الشروق',
      'الظهر',
      'العصر',
      'المغرب',
      'العشاء',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'الصلاة $label');
    }

    expect(find.text('الضحى'), findsOneWidget);
    expect(find.text('الثلث الأخير من الليل'), findsOneWidget);
  });
}
