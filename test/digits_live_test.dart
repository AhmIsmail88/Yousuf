import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/core/utils/arabic_digits.dart';

/// تحديث صيغة الأرقام فوراً عبر الثيم (بلا إعادة تشغيل).
void main() {
  test('الثيم يحمل صيغة الأرقام كامتداد', () {
    final hindi = AppTheme.of(Brightness.light, DigitStyle.hindi);
    final arabic = AppTheme.of(Brightness.light, DigitStyle.arabic);
    expect(hindi.extension<DigitsTheme>()!.style, DigitStyle.hindi);
    expect(arabic.extension<DigitsTheme>()!.style, DigitStyle.arabic);
  });

  test('تغيير الصيغة يؤثر في التنسيق مباشرة', () {
    setDigitStyle(DigitStyle.hindi);
    expect(toHindiDigits('15'), '١٥');
    setDigitStyle(DigitStyle.arabic);
    expect(toHindiDigits('15'), '15');
    addTearDown(() => setDigitStyle(DigitStyle.hindi));
  });

  testWidgets('تغيير الثيم يعيد بناء النص المعروض', (tester) async {
    var style = DigitStyle.hindi;
    setDigitStyle(style);

    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(Brightness.light, style),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(body: Text(toHindiDigits('15')));
          },
        ),
      ),
    );
    expect(find.text('١٥'), findsOneWidget);

    setDigitStyle(DigitStyle.arabic);
    rebuild(() => style = DigitStyle.arabic);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.of(Brightness.light, style),
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(body: Text(toHindiDigits('15')));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('15'), findsOneWidget);
    addTearDown(() => setDigitStyle(DigitStyle.hindi));
  });
}
