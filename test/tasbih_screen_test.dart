import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/tasbih/presentation/tasbih_screen.dart';

/// اختبارات شاشة مسبحة: العدّ بالضغط، التصفير، وإضافة عدّاد.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTasbih(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ar'),
          supportedLocales: const <Locale>[Locale('ar')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const TasbihScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('الضغط على البطاقة يزيد الرقم المعروض', (tester) async {
    await pumpTasbih(tester);

    expect(find.text('٠'), findsOneWidget);
    expect(find.text('من ٣٣'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tasbih.card')));
    await tester.pumpAndSettle();

    expect(find.text('١'), findsOneWidget);
    expect(find.text('اليوم: ١ تسبيحة'), findsOneWidget);
  });

  testWidgets('زر التصفير يرجعه إلى صفر مع بقاء إحصاء اليوم', (tester) async {
    await pumpTasbih(tester);

    for (var tap = 0; tap < 2; tap++) {
      await tester.tap(find.byKey(const Key('tasbih.card')));
      await tester.pumpAndSettle();
    }
    expect(find.text('٢'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tasbih.reset')));
    await tester.pumpAndSettle();

    expect(find.text('٠'), findsOneWidget);
    expect(find.text('اليوم: ٢ تسبيحة'), findsOneWidget);
  });

  testWidgets('إضافة عدّاد تظهر شريحة جديدة', (tester) async {
    await pumpTasbih(tester);

    await tester.tap(find.byTooltip('إضافة عدّاد'));
    await tester.pumpAndSettle();
    expect(find.text('إضافة عدّاد'), findsWidgets);

    await tester.enterText(find.byKey(const Key('tasbih.label')), 'استغفار');
    await tester.tap(find.text('١٠٠'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tasbih.save')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'استغفار'), findsOneWidget);
    expect(find.text('من ١٠٠'), findsOneWidget);
  });

  testWidgets('بلوغ الهدف يظهر شارة «اكتمل» دون تصفير تلقائي', (tester) async {
    await pumpTasbih(tester);

    for (var tap = 0; tap < 33; tap++) {
      await tester.tap(find.byKey(const Key('tasbih.card')));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('اكتمل'), findsOneWidget);
    expect(find.text('٣٣'), findsOneWidget, reason: 'العدد يبقى عند الهدف');
  });

  testWidgets('تعديل العدّاد ثم حذفه مع تأكيد', (tester) async {
    await pumpTasbih(tester);

    await tester.tap(find.byTooltip('تعديل العدّاد'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('tasbih.label')),
      'سبحان الله وبحمده',
    );
    await tester.tap(find.byKey(const Key('tasbih.save')));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(ChoiceChip, 'سبحان الله وبحمده'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('تعديل العدّاد'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tasbih.delete')));
    await tester.pumpAndSettle();
    expect(find.text('حذف العدّاد'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'حذف'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'سبحان الله وبحمده'), findsNothing);
    expect(
      find.text('من ٣٣'),
      findsOneWidget,
      reason: 'العدّاد التالي هو النشط',
    );
  });

  testWidgets('الهدف المخصص والتحقق من نص الذكر', (tester) async {
    await pumpTasbih(tester);

    await tester.tap(find.byTooltip('إضافة عدّاد'));
    await tester.pumpAndSettle();

    // حفظ بلا نص: خطأ ظاهر والحوار لا يُغلق.
    await tester.tap(find.byKey(const Key('tasbih.save')));
    await tester.pumpAndSettle();
    expect(find.text('أدخل نص الذكر'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('tasbih.label')), 'تسبيح مخصص');
    await tester.tap(find.text('مخصص'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tasbih.customTarget')), '250');
    await tester.tap(find.byKey(const Key('tasbih.save')));
    await tester.pumpAndSettle();

    expect(find.text('من ٢٥٠'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'تسبيح مخصص'), findsOneWidget);
  });
}
