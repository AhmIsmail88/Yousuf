import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/adhkar/presentation/adhkar_screen.dart';
import 'package:yousuf/features/quran/presentation/quran_providers.dart';
import 'package:yousuf/l10n/generated/app_localizations.dart';

/// اختبار شاشة الأذكار على قاعدة مؤقتة صغيرة (سكيمة content.sqlite نفسها):
/// عرض باب، العدّ حتى الاكتمال، وإضافة ذكر من المستخدم.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String dbPath;
  late ContentDb content;

  setUpAll(() {
    dbPath = '${Directory.systemTemp.path}/yousuf_adhkar_screen_test.sqlite';
    if (File(dbPath).existsSync()) File(dbPath).deleteSync();
    final db = sqlite3.open(dbPath);
    db.execute('''
      CREATE TABLE dhikr_category (
        id INTEGER PRIMARY KEY,
        slug TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        sort INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE dhikr (
        id INTEGER PRIMARY KEY,
        category_id INTEGER NOT NULL REFERENCES dhikr_category(id),
        text TEXT NOT NULL,
        repeat_count INTEGER NOT NULL DEFAULT 1,
        source TEXT,
        virtue TEXT,
        audio_ref TEXT
      );
      CREATE TABLE content_version (
        version TEXT NOT NULL,
        built_at TEXT NOT NULL,
        reviewed_by TEXT,
        sources_checksum TEXT NOT NULL
      );
    ''');
    db.execute(
      'INSERT INTO dhikr_category (id, slug, name, sort) VALUES (1, ?, ?, 1)',
      ['morning', 'أذكار الصباح والمساء'],
    );
    db.execute(
      'INSERT INTO dhikr_category (id, slug, name, sort) VALUES (2, ?, ?, 0)',
      ['quranic', 'أدعية من القرآن'],
    );
    db.execute(
      'INSERT INTO dhikr (id, category_id, text, repeat_count, source) '
      'VALUES (1, 1, ?, 1, ?)',
      ['سبحان الله وبحمده', 'رواه مسلم'],
    );
    db.execute(
      'INSERT INTO content_version (version, built_at, reviewed_by, sources_checksum) '
      "VALUES ('test', '2026-11-11', NULL, 'x')",
    );
    db.close();
    content = ContentDb.openFile(dbPath);
  });

  tearDownAll(() {
    content.dispose();
    if (File(dbPath).existsSync()) File(dbPath).deleteSync();
  });

  Future<SharedPreferences> pumpScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          contentDbProvider.overrideWith((ref) async => content),
        ],
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ar'), Locale('en')],
          home: const AdhkarScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  testWidgets('يعرض الباب والعدّ حتى الاكتمال مع حفظ التقدّم', (tester) async {
    final prefs = await pumpScreen(tester);

    // القسم الافتراضي «أدعية القرآن» فارغ في هذه القاعدة الصغيرة.
    final morningChip = find.text('أذكار الصباح والمساء');
    await tester.ensureVisible(morningChip);
    await tester.tap(morningChip);
    await tester.pumpAndSettle();

    // الانتظار المرن: مزوّدات القاعدة قد تتأخر أكثر من إطار.
    await _pumpUntilFound(tester, find.text('سبحان الله وبحمده'));

    expect(find.text('سبحان الله وبحمده'), findsOneWidget);
    expect(find.text('رواه مسلم'), findsOneWidget);
    // المحتوى غير موقّع ⇒ تنبيه المراجعة ظاهر.
    expect(find.textContaining('قيد المراجعة الشرعية'), findsWidgets);

    await _pumpUntilFound(tester, find.text('مرة واحدة'));
    await tester.tap(find.text('مرة واحدة'));
    await _pumpUntilFound(tester, find.text('تم'));

    expect(find.text('تم'), findsWidgets);
    expect(prefs.getString('adhkar.progress.${_todayKey()}'), isNotNull);
  });

  testWidgets('إضافة ذكر من المستخدم تظهر في «أذكاري» وتُحفظ', (tester) async {
    final prefs = await pumpScreen(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('إضافة ذكر'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'نص الذكر').first,
      'اللهم إني أسألك العافية',
    );
    await tester.tap(find.text('إضافة'));
    await tester.pumpAndSettle();

    expect(find.text('اللهم إني أسألك العافية'), findsOneWidget);
    expect(find.text('مضاف منك'), findsOneWidget);
    expect(prefs.getString('adhkar.user'), contains('اللهم إني أسألك العافية'));
  });

  testWidgets('تبويب «كل الأقسام» يعرض الأبواب ويبحث فيها', (tester) async {
    await pumpScreen(tester);

    final allChip = find.text('كل الأقسام');
    await tester.ensureVisible(allChip);
    await tester.tap(allChip);
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(ListTile, 'أذكار الصباح والمساء'),
      findsOneWidget,
    );
    expect(find.widgetWithText(ListTile, 'أدعية من القرآن'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'القرآن');
    await tester.pumpAndSettle();
    // القائمة تُفلتر بينما تبقى شرائح الأقسام.
    expect(find.widgetWithText(ListTile, 'أدعية من القرآن'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'أذكار الصباح والمساء'), findsNothing);
  });
}

/// ينبض حتى يظهر العنصر المطلوب (حد أقصى ~ثانيتان).
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 40,
}) async {
  for (var frame = 0; frame < maxFrames; frame++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _todayKey() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
