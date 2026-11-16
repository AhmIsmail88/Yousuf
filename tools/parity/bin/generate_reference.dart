import 'dart:convert';
import 'dart:io';

import 'package:yousuf/features/prayer/domain/prayer_times_calculator.dart';
import 'package:yousuf/features/prayer/domain/prayer_times_models.dart';

/// يولّد ملف مرجع التطابق Dart↔Kotlin (CONTRACTS §4).
///
/// الاستخدام من مجلد `yousuf/`:
///   dart run tools/parity/bin/generate_reference.dart [YYYY-MM-DD] [أيام]
/// الافتراضي: 2026-11-01 و30 يوماً. للإصدار النهائي: 365 يوماً (SPEC §11).
Future<void> main(List<String> args) async {
  final start = DateTime.parse(args.isNotEmpty ? args[0] : '2026-11-01');
  final days = args.length > 1 ? int.parse(args[1]) : 30;

  final citiesFile = File('tools/parity/cities.json');
  final rawCities = jsonDecode(await citiesFile.readAsString()) as List;
  final cities = rawCities.cast<Map<String, dynamic>>();

  final times = <String, Map<String, String>>{};
  for (final city in cities) {
    final location = PrayerLocation(
      latitude: (city['lat'] as num).toDouble(),
      longitude: (city['lng'] as num).toDouble(),
      timezoneId: city['tz'] as String,
      cityName: city['name'] as String?,
    );
    final method = CalculationMethod.fromId(city['method'] as String?);
    final madhab = AsrMadhab.fromId(city['madhab'] as String?);
    for (var i = 0; i < days; i++) {
      final date = DateTime(start.year, start.month, start.day + i);
      final day = PrayerTimesCalculator.forDate(
        location: location,
        date: date,
        method: method,
        madhab: madhab,
      );
      times['${city['id']}|${_dateKey(date)}'] = day.toTimesMap();
    }
  }

  final output = <String, Object>{
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'cities': cities,
    'times': times,
  };

  final outFile = File('tools/parity/reference_times.json');
  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );
  stdout.writeln(
    'تم التوليد: ${outFile.path} — ${cities.length} مدينة × $days يوم '
    '= ${times.length} مدخلاً',
  );
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
