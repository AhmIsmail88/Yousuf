import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/quran/presentation/mushaf_reader_screen.dart';
import 'package:yousuf/features/quran/presentation/quran_providers.dart';

/// في الوضع العادي تظهر الآيات بحبر مرئي، وفي وضع الحفظ تُخفى (شفافة).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentDb content;
  setUpAll(
    () => content = ContentDb.openFile(
      File('assets/db/content.sqlite').absolute.path,
    ),
  );
  tearDownAll(() => content.dispose());

  /// ألوان مقاطع النص التي تحوي «ٱلْحَمْدُ» في صفحة الفاتحة.
  List<Color?> ayahColors(WidgetTester tester) {
    final colors = <Color?>[];
    for (final element in find.byType(RichText).evaluate()) {
      final rich = element.widget as RichText;
      rich.text.visitChildren((span) {
        if (span is TextSpan && (span.text ?? '').contains('ٱلْحَمْدُ')) {
          colors.add(span.style?.color);
        }
        return true;
      });
    }
    return colors;
  }

  Future<void> pump(WidgetTester tester, {required bool hifz}) async {
    SharedPreferences.setMockInitialValues({'quran.hifz_mode': hifz});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          contentDbProvider.overrideWith((ref) async => content),
        ],
        child: const MaterialApp(home: MushafReaderScreen(initialPage: 1)),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('الوضع العادي: نص الآيات مرئي', (tester) async {
    await pump(tester, hifz: false);
    final colors = ayahColors(tester);
    expect(colors, isNotEmpty);
    expect(
      colors.every((c) => c != null && c.a > 0.5),
      isTrue,
      reason: '$colors',
    );
  });

  testWidgets('وضع الحفظ: نص الآيات مخفي', (tester) async {
    await pump(tester, hifz: true);
    final colors = ayahColors(tester);
    expect(colors, isNotEmpty);
    expect(
      colors.every((c) => c != null && c.a == 0),
      isTrue,
      reason: '$colors',
    );
  });
}
