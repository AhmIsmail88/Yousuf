import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/features/quran/data/quran_audio_repository.dart';
import 'package:yousuf/features/quran/data/quran_repository.dart';
import 'package:yousuf/features/quran/domain/quran_reciter.dart';

/// اختبارات القرّاء ومدى الآيات وتنزيل التلاوات (بلا شبكة).
void main() {
  group('القرّاء', () {
    test('القائمة سليمة والمعرّفات فريدة', () {
      expect(kQuranReciters.length, greaterThanOrEqualTo(12));
      expect(kQuranReciters.first.id, 'ar.minshawi');
      final ids = kQuranReciters.map((reciter) => reciter.id).toSet();
      expect(ids.length, kQuranReciters.length);
      for (final reciter in kQuranReciters) {
        expect(reciter.nameAr, isNotEmpty);
        expect(reciter.nameEn, isNotEmpty);
        expect([32, 64, 128], contains(reciter.bitrate));
        if (reciter.teacher) {
          // المصحف المعلّم من EveryAyah (قسم الأطفال).
          expect(reciter.source, ReciterSource.everyAyah);
          expect(reciter.folder, isNotEmpty);
          expect(reciter.style, 'معلّم');
        } else {
          expect(reciter.id, startsWith('ar.'));
          expect(['مرتل', 'مجود'], contains(reciter.style));
        }
      }
      expect(kTeacherReciters.length, 2);
    });

    test('رابط EveryAyah بالسورة والآية بثلاث خانات', () {
      final teacher = kTeacherReciters.first;
      // الآية العامة ٨ = البقرة ١.
      expect(
        teacher.urlFor(8).toString(),
        'https://everyayah.com/data/Husary_Muallim_128kbps/002001.mp3',
      );
      expect(teacher.urlFor(6236).toString(), endsWith('/114006.mp3'));
    });

    test('غير المعروف يرجع للقارئ الأول', () {
      expect(reciterById('ar.unknown').id, 'ar.minshawi');
      expect(reciterById(null).id, 'ar.minshawi');
      expect(reciterById('ar.husary').nameAr, 'محمود خليل الحصري');
    });
  });

  group('مدى الآيات', () {
    late ContentDb content;
    late QuranRepository repository;

    setUpAll(() {
      content = ContentDb.openFile(
        File('assets/db/content.sqlite').absolute.path,
      );
      repository = QuranRepository(content);
    });

    tearDownAll(() => content.dispose());

    test('سورة الفاتحة: ١..٧', () {
      final range = repository.rangeOfSurah(1);
      expect(range.first, 1);
      expect(range.last, 7);
    });

    test('سورة البقرة تبدأ من ٨', () {
      expect(repository.rangeOfSurah(2).first, 8);
    });

    test('الجزء ٣٠ ينتهي بالآية ٦٢٣٦', () {
      final range = repository.rangeOfJuz(30);
      expect(range.last, 6236);
      expect(range.first, greaterThan(5000));
    });

    test('كل الأجزاء متصلة وتغطي المصحف', () {
      var expected = 1;
      for (var juz = 1; juz <= 30; juz++) {
        final range = repository.rangeOfJuz(juz);
        expect(range.first, expected, reason: 'الجزء $juz');
        expected = range.last + 1;
      }
      expect(expected, 6237);
    });

    test('الصفحة الأولى والشاملة', () {
      final page = repository.rangeOfPage(1);
      expect(page.first, 1);
      expect(page.last, 7);
      final whole = repository.wholeMushaf();
      expect(whole.first, 1);
      expect(whole.last, 6236);
    });
  });

  group('تنزيل التلاوات', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('yousuf_audio_test');
    });

    tearDown(() async {
      if (temp.existsSync()) await temp.delete(recursive: true);
    });

    QuranAudioRepository buildRepository(
      http.Client client,
      QuranReciter reciter,
    ) => QuranAudioRepository(
      reciter: reciter,
      client: client,
      directoryResolver: () async => temp,
      concurrency: 2,
    );

    test('رابط الآية يحمل الجودة ومعرّف القارئ', () {
      final repository = buildRepository(
        MockClient((_) async => http.Response('', 200)),
        kQuranReciters[1],
      );
      expect(
        repository.urlFor(42).toString(),
        'https://cdn.islamic.network/quran/audio/64/'
        '${kQuranReciters[1].id}/42.mp3',
      );
    });

    test('ينزّل الملف ويتخطاه في المرة الثانية', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response.bytes(List<int>.filled(4096, 7), 200);
      });
      final repository = buildRepository(client, kQuranReciters.first);

      final file = await repository.downloadAyah(1);
      expect(file.existsSync(), isTrue);
      expect(await file.length(), 4096);
      expect(await repository.isDownloaded(1), isTrue);
      expect(await repository.cachedCount([1, 2]), 1);

      await repository.downloadAyah(1);
      expect(calls, 1, reason: 'الملف الموجود لا يُنزَّل مرة أخرى');
    });

    test('فشل الشبكة يرمي استثناء', () async {
      final repository = buildRepository(
        MockClient((_) async => http.Response('not found', 404)),
        kQuranReciters.first,
      );
      expect(() => repository.downloadAyah(5), throwsA(isA<HttpException>()));
    });

    test('تحميل مدى كامل مع تقدّم', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(List<int>.filled(2048, 1), 200),
      );
      final repository = buildRepository(client, kQuranReciters.first);
      final progress = <int>[];

      final done = await repository.downloadRange(
        1,
        4,
        onProgress: (done, total) => progress.add(done),
      );

      expect(done, 4);
      expect(progress.last, 4);
      expect((await repository.downloadedIds()).length, 4);
    });

    test('الإلغاء يوقف بعد الآيات الجارية', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response.bytes(List<int>.filled(1024, 1), 200);
      });
      final repository = buildRepository(client, kQuranReciters.first);

      final done = await repository.downloadRange(
        1,
        20,
        isCancelled: () => calls >= 3,
      );

      expect(done, lessThan(20));
      expect(calls, greaterThanOrEqualTo(3));
      expect(calls, lessThan(20));
    });

    test('حذف التحميلات يفرّغ المجلد', () async {
      final client = MockClient(
        (_) async => http.Response.bytes(List<int>.filled(1024, 1), 200),
      );
      final repository = buildRepository(client, kQuranReciters.first);
      await repository.downloadRange(1, 2);
      expect((await repository.downloadedIds()).isNotEmpty, isTrue);

      await repository.deleteAll();
      expect(await repository.downloadedIds(), isEmpty);
    });

    test('تقدير الحجم يتناسب مع الجودة وعدد الآيات', () {
      final high = buildRepository(
        MockClient((_) async => http.Response('', 200)),
        kQuranReciters.first,
      );
      final low = buildRepository(
        MockClient((_) async => http.Response('', 200)),
        reciterById('ar.ibrahimakhbar'), // ٣٢ ك.ب/ث
      );
      expect(high.estimatedMegabytes(100), greaterThan(20));
      expect(
        low.estimatedMegabytes(100),
        lessThan(high.estimatedMegabytes(100)),
      );
    });
  });
}
