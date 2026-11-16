import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/app/app.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('شاشة البداية تظهر أولاً ثم يعقبها الترحيب', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const YousufApp(),
      ),
    );

    // أول إطار: شاشة البداية
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('YOUSUF'), findsOneWidget);
    expect(find.text('رفيقك في الطاعة'), findsOneWidget);
    expect(find.text('صدقة جارية — فكرة يوسف'), findsOneWidget);

    // بعد اكتمال الحركة (٣٫٢ ث): يُعرض الترحيب (أول تشغيل)
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();

    expect(find.text('YOUSUF'), findsNothing);
    expect(find.text('أهلاً بك في يوسف'), findsOneWidget);
  });
}
