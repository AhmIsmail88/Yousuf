import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/quran/data/quran_audio_repository.dart';
import 'package:yousuf/features/quran/domain/quran_reciter.dart';
import 'package:yousuf/features/quran/presentation/downloads_screen.dart';
import 'package:yousuf/features/quran/presentation/quran_providers.dart';

/// اختبار ودجت لمركز التحميلات: العرض، تغيير القارئ، وتأكيد التحميل.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContentDb content;
  late Directory temp;

  setUpAll(() {
    content = ContentDb.openFile(
      File('assets/db/content.sqlite').absolute.path,
    );
  });

  tearDownAll(() => content.dispose());

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('yousuf_downloads_test');
  });

  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  Future<QuranAudioRepository> pumpScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final audio = QuranAudioRepository(
      reciter: kQuranReciters.first,
      client: MockClient(
        (_) async => http.Response.bytes(List<int>.filled(1024, 1), 200),
      ),
      directoryResolver: () async => temp,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          contentDbProvider.overrideWith((ref) async => content),
          quranAudioRepositoryProvider.overrideWithValue(audio),
        ],
        child: const MaterialApp(home: DownloadsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return audio;
  }

  testWidgets('يعرض القارئ وخيارات التحميل', (tester) async {
    await pumpScreen(tester);
    await _settleIo(tester);

    expect(find.text('التحميلات'), findsOneWidget);
    expect(find.text('محمد صديق المنشاوي'), findsOneWidget);
    expect(find.text('المصحف كاملاً'), findsOneWidget);
    expect(find.text('جزء'), findsOneWidget);
    expect(find.text('سورة'), findsOneWidget);
    expect(find.text('صفحة'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('المحمّل على جهازك'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await _settleIo(tester);
    // محتوى القسم يعتمد على قراءة ملفات حقيقية — يُختبر في اختبارات المستودع.
    expect(find.text('المحمّل على جهازك'), findsOneWidget);
  });

  testWidgets('تأكيد تحميل المصحف يوضّح الحجم ويلغي بلا تنزيل', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('المصحف كاملاً'));
    await tester.pumpAndSettle();

    expect(find.textContaining('٦٢٣٦'), findsWidgets);
    expect(find.textContaining('الحجم التقديري'), findsOneWidget);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(find.textContaining('جارٍ تحميل'), findsNothing);
  });

  testWidgets('تغيير القارئ يحدّث العنوان ويُحفظ', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('تغيير'));
    await tester.pumpAndSettle();

    expect(find.text('ماهر المعيقلي'), findsOneWidget);
    await tester.tap(find.text('ماهر المعيقلي'));
    await tester.pumpAndSettle();

    expect(find.text('ماهر المعيقلي'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('quran.reciter'), 'ar.mahermuaiqly');
  });
}

/// يمنح عمليات الملفات الحقيقية فرصة الاكتمال ثم يُعيد الاستقرار.
Future<void> _settleIo(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await tester.pumpAndSettle();
}
