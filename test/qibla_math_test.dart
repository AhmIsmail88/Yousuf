/// اختبارات ميزة القبلة: حساب الاتجاه وزاوية الشمس (Dart خالص)، ثم اختبارات
/// ودجت للبوصلة والمعايرة وبديل الشمس (SPEC §7.5).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/features/prayer/data/prayer_settings_repository.dart';
import 'package:yousuf/features/prayer/presentation/prayer_providers.dart';
import 'package:yousuf/features/qibla/domain/qibla_math.dart';
import 'package:yousuf/features/qibla/presentation/qibla_screen.dart';

void main() {
  group('qiblaBearing', () {
    const cities = <String, List<double>>{
      'الرياض': [24.7136, 46.6753, 243],
      'القاهرة': [30.0444, 31.2357, 136],
      'إسطنبول': [41.0082, 28.9784, 152],
      'جاكرتا': [-6.2088, 106.8456, 295],
      'نيويورك': [40.7128, -74.0060, 58],
    };

    test('اتجاه القبلة لمدن معروفة ضمن ±1°', () {
      for (final entry in cities.entries) {
        final coords = entry.value;
        final actual = qiblaBearing(coords[0], coords[1]);
        expect(
          shortestDelta(coords[2], actual).abs(),
          lessThanOrEqualTo(1.0),
          reason: '${entry.key}: $actual',
        );
      }
    });

    test('نقطة جنوب الكعبة على خط طولها تتجه شمالاً (0°)', () {
      expect(qiblaBearing(10, kaabaLongitude), closeTo(0, 0.01));
    });

    test('نقطة شمال الكعبة على خط طولها تتجه جنوباً (180°)', () {
      expect(qiblaBearing(40, kaabaLongitude), closeTo(180, 0.01));
    });

    test('عند الكعبة نفسها لا يوجد اتجاه (0°)', () {
      expect(qiblaBearing(kaabaLatitude, kaabaLongitude), 0);
    });

    test('الزاوية دائماً ضمن 0..360', () {
      for (var lat = -85.0; lat <= 85.0; lat += 17.0) {
        for (var lng = -180.0; lng < 180.0; lng += 23.0) {
          final bearing = qiblaBearing(lat, lng);
          expect(bearing, greaterThanOrEqualTo(0.0));
          expect(bearing, lessThan(360.0));
        }
      }
    });
  });

  group('normalizeAngle', () {
    test('يطبع إلى 0..360', () {
      expect(normalizeAngle(0), 0);
      expect(normalizeAngle(360), 0);
      expect(normalizeAngle(725), closeTo(5, 1e-9));
      expect(normalizeAngle(-90), closeTo(270, 1e-9));
      expect(normalizeAngle(-720), 0);
      expect(normalizeAngle(243.8), closeTo(243.8, 1e-9));
    });
  });

  group('shortestDelta', () {
    test('يعبر حد 0/360 بأقصر طريق', () {
      expect(shortestDelta(350, 10), closeTo(20, 1e-9));
      expect(shortestDelta(10, 350), closeTo(-20, 1e-9));
      expect(shortestDelta(0, 180).abs(), closeTo(180, 1e-9));
      expect(shortestDelta(5, 355), closeTo(-10, 1e-9));
      expect(shortestDelta(90, 90), 0);
    });

    test('الباقي دائماً ضمن −180..180', () {
      for (var from = 0.0; from < 360.0; from += 7.0) {
        for (var to = 0.0; to < 360.0; to += 11.0) {
          final delta = shortestDelta(from, to);
          expect(delta, greaterThanOrEqualTo(-180.0));
          expect(delta, lessThanOrEqualTo(180.0));
        }
      }
    });
  });

  group('sunAzimuth', () {
    test('عند الظهيرة الشمسية شمالاً تكون الزاوية 180°', () {
      final moscow = sunAzimuth(
        lat: 55.7558,
        lng: 37.6173,
        utc: DateTime.utc(2026, 6, 21, 9, 31),
      );
      expect(moscow, closeTo(180, 1.0));

      final cairo = sunAzimuth(
        lat: 30.0444,
        lng: 31.2357,
        utc: DateTime.utc(2026, 3, 20, 10, 3),
      );
      expect(cairo, closeTo(180, 1.0));
    });

    test('قبل الظهيرة شرقاً وبعدها غرباً', () {
      final morning = sunAzimuth(
        lat: 30.0444,
        lng: 31.2357,
        utc: DateTime.utc(2026, 3, 20, 8),
      );
      expect(morning, greaterThan(0));
      expect(morning, lessThan(180));

      final afternoon = sunAzimuth(
        lat: 30.0444,
        lng: 31.2357,
        utc: DateTime.utc(2026, 3, 20, 13),
      );
      expect(afternoon, greaterThan(180));
      expect(afternoon, lessThan(360));
    });

    test('نصف الكرة الجنوبي: الشمس شمالاً عند الظهيرة', () {
      final sydney = sunAzimuth(
        lat: -33.8688,
        lng: 151.2093,
        utc: DateTime.utc(2026, 3, 20, 2, 3),
      );
      final distanceFromNorth = math.min(sydney, 360 - sydney);
      expect(distanceFromNorth, lessThanOrEqualTo(1.5));
    });

    test('القيمة دائماً بين 0 و360 ولو تغيّر الموقع والساعة', () {
      for (var hour = 0; hour < 24; hour++) {
        for (final lat in [-80.0, -45.0, 0.0, 24.7, 55.0, 80.0]) {
          final azimuth = sunAzimuth(
            lat: lat,
            lng: 46.6753,
            utc: DateTime.utc(2026, 7, 15, hour),
          );
          expect(azimuth, greaterThanOrEqualTo(0.0));
          expect(azimuth, lessThan(360.0));
          expect(azimuth.isFinite, isTrue);
        }
      }
    });

    test('يقبل توقيتاً محلياً ويحوّله إلى UTC', () {
      final utc = sunAzimuth(
        lat: 24.7136,
        lng: 46.6753,
        utc: DateTime.utc(2026, 7, 15, 9),
      );
      final local = sunAzimuth(
        lat: 24.7136,
        lng: 46.6753,
        utc: DateTime.utc(2026, 7, 15, 9).toLocal(),
      );
      expect(local, closeTo(utc, 1e-6));
    });
  });

  group('شاشة القبلة', () {
    testWidgets('بدون قراءات: تظهر بطاقة بديل الشمس بعد 3 ثوانٍ', (
      tester,
    ) async {
      await _pumpQiblaScreen(tester);

      expect(find.textContaining('زاوية القبلة'), findsOneWidget);
      expect(find.textContaining('جارٍ قراءة البوصلة'), findsOneWidget);
      expect(find.text('بديل الشمس'), findsNothing);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('بديل الشمس'), findsOneWidget);
      expect(find.textContaining('زاوية الشمس الآن'), findsOneWidget);
    });

    testWidgets('قراءة قريبة من القبلة تُظهر «على القبلة»', (tester) async {
      final controller = await _pumpQiblaScreen(tester);
      final bearing = qiblaBearing(24.7136, 46.6753);

      await _emit(tester, controller, bearing + 2);

      expect(find.text('على القبلة'), findsOneWidget);
      expect(find.text('بديل الشمس'), findsNothing);
    });

    testWidgets('القراءة البعيدة تعرض اتجاه التصحيح', (tester) async {
      final controller = await _pumpQiblaScreen(tester);
      final bearing = qiblaBearing(24.7136, 46.6753);

      // أقصر فرق موجب ⇒ «يميناً».
      await _emit(tester, controller, bearing - 40);
      expect(find.textContaining('يميناً'), findsOneWidget);

      // أقصر فرق سالب ⇒ «يساراً».
      await _emit(tester, controller, bearing + 40);
      expect(find.textContaining('يساراً'), findsOneWidget);
    });

    testWidgets('تذبذب القراءات يعرض بطاقة المعايرة (حركة ٨)', (tester) async {
      final controller = await _pumpQiblaScreen(tester);

      await _emit(tester, controller, 10);
      expect(find.textContaining('المعايرة'), findsNothing);

      // فرق 70° خلال أقل من ثانية.
      await _emit(tester, controller, 80);
      expect(find.text('المعايرة: حرّك الهاتف على شكل ٨'), findsOneWidget);
    });

    testWidgets('زر إعادة المحاولة يعيد حالة الانتظار', (tester) async {
      final controller = await _pumpQiblaScreen(tester);

      await _emit(tester, controller, 100);
      expect(find.textContaining('جارٍ قراءة البوصلة'), findsNothing);

      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pump();

      expect(find.textContaining('جارٍ قراءة البوصلة'), findsOneWidget);
    });
  });
}

/// يبني شاشة القبلة بإعدادات الرياض الافتراضية ومجرى بوصلة وهمي.
Future<StreamController<CompassEvent>> _pumpQiblaScreen(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final controller = StreamController<CompassEvent>.broadcast();

  // إزالة الشاشة أولاً (فتُلغى مؤقّتاتها) ثم إغلاق المجرى.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await controller.close();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        prayerSettingsProvider.overrideWith(
          (ref) async => const PrayerSettings(),
        ),
        qiblaCompassStreamProvider.overrideWithValue(controller.stream),
      ],
      child: const MaterialApp(home: QiblaScreen()),
    ),
  );
  await tester.pump(); // إتمام تحميل الإعدادات
  await tester.pump(); // بناء الواجهة بعد وصول البيانات
  return controller;
}

/// يرسل قراءة بوصلة ويمنح المجرى فرصة التسليم (يحتاج إطارين).
Future<void> _emit(
  WidgetTester tester,
  StreamController<CompassEvent> controller,
  double heading,
) async {
  controller.add(CompassEvent.fromList([normalizeAngle(heading), 0, -1]));
  await tester.pump();
  await tester.pump();
}
