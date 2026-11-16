import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../features/prayer/domain/prayer_times_calculator.dart';
import '../../features/prayer/presentation/prayer_providers.dart';

/// نبضة الساعة: الوقت الآن، يُحدَّث على رأس كل دقيقة.
///
/// تُتجاوز في الاختبارات بقيمة ثابتة.
final clockProvider = StreamProvider<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  Timer? timer;

  void tick() {
    final now = DateTime.now();
    controller.add(now);
    // المزامنة مع بداية الدقيقة التالية (+٢٠٠ مللي ثانية هامش).
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    timer = Timer(
      next.difference(now) + const Duration(milliseconds: 200),
      tick,
    );
  }

  tick();
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// الوقت الحالي بتوقيت **المدينة المختارة** (لا الجهاز).
///
/// المواقيت تُحسب بتوقيت الموقع، فالعدّاد والمقارنة يجب أن يكونا بالتوقيت نفسه
/// (مهم عند اختيار مدينة في منطقة زمنية غير منطقة الجهاز).
final locationNowProvider = Provider<DateTime>((ref) {
  final device = ref.watch(clockProvider).value ?? DateTime.now();
  final settings = ref.watch(prayerSettingsProvider).value;
  if (settings == null) return device;
  PrayerTimesCalculator.ensureTimezones();
  try {
    final zone = tz.getLocation(settings.location.timezoneId);
    final local = tz.TZDateTime.from(device, zone);
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
  } catch (_) {
    return device;
  }
});

/// تاريخ اليوم بتوقيت الموقع — يتغيّر عند منتصف الليل فقط، فيعيد حساب
/// كل ما يعتمد على اليوم (المواقيت، التاريخ الهجري، تقدّم الأذكار).
final todayProvider = Provider<DateTime>((ref) {
  final now = ref.watch(locationNowProvider);
  return DateTime(now.year, now.month, now.day);
});
