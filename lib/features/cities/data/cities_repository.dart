/// مدينة من قاعدة GeoNames المدمجة (SPEC §7.1).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../features/prayer/domain/prayer_times_models.dart';

import 'dart:convert';
import 'dart:math' as math;

/// مدينة أوفلاين: اسم عربي/لاتيني + إحداثيات + منطقة زمنية.
class City {
  const City({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    required this.timezoneId,
    required this.population,
  });

  final int id;
  final String nameAr;
  final String nameEn;
  final String countryCode;
  final double latitude;
  final double longitude;
  final String timezoneId;
  final int population;

  factory City.fromJson(Map<String, dynamic> json) => City(
    id: (json['id'] as num).toInt(),
    nameAr: json['ar'] as String,
    nameEn: json['en'] as String,
    countryCode: json['cc'] as String,
    latitude: (json['lat'] as num).toDouble(),
    longitude: (json['lng'] as num).toDouble(),
    timezoneId: json['tz'] as String,
    population: (json['pop'] as num).toInt(),
  );

  /// اسم المدينة بلغة الواجهة.
  String name({required bool arabic}) => arabic ? nameAr : nameEn;

  PrayerLocation toPrayerLocation() => PrayerLocation(
    latitude: latitude,
    longitude: longitude,
    timezoneId: timezoneId,
    cityName: nameAr,
    cityNameEn: nameEn,
  );

  /// موقع بإحداثيات الجهاز الفعلية، مع اسم ومنطقة زمنية أقرب مدينة.
  ///
  /// المواقيت تُحسب من الإحداثيات نفسها لا من مركز المدينة — مهم للقرى
  /// والمناطق البعيدة عن أقرب مدينة في القاعدة.
  PrayerLocation atCoordinates(double lat, double lng) => PrayerLocation(
    latitude: lat,
    longitude: lng,
    timezoneId: timezoneId,
    cityName: nameAr,
    cityNameEn: nameEn,
    fromGps: true,
  );
}

/// مستودع المدن: بحث عربي/لاتيني وأقرب مدينة لإحداثيات.
class CitiesRepository {
  CitiesRepository(this.cities);

  final List<City> cities;

  /// بحث بالاسم (عربي أو لاتيني) — يتجاهل التشكيل ويرتب بالسكان.
  List<City> search(String query, {int limit = 60}) {
    final normalized = _normalize(query);
    if (normalized.isEmpty) {
      return cities.take(limit).toList(growable: false);
    }
    return cities
        .where(
          (city) =>
              _normalize(city.nameAr).contains(normalized) ||
              city.nameEn.toLowerCase().contains(normalized),
        )
        .take(limit)
        .toList(growable: false);
  }

  /// أقرب مدينة لإحداثيات (Great-circle تقريبي للاختيار).
  City nearest(double latitude, double longitude) {
    var best = cities.first;
    var bestDistance = double.infinity;
    for (final city in cities) {
      final dLat = (city.latitude - latitude) * 111.0;
      final dLng =
          (city.longitude - longitude) *
          111.0 *
          math.cos((city.latitude + latitude) / 2 * math.pi / 180.0);
      final distance = dLat * dLat + dLng * dLng;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = city;
      }
    }
    return best;
  }
}

String _normalize(String input) {
  const diacritics = '\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED';
  return input
      .replaceAll(RegExp('[$diacritics]'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .toLowerCase()
      .trim();
}

/// يختار طريقة الحساب الافتراضية حسب دولة المدينة (SPEC §7.1).
CalculationMethod defaultMethodForCountry(String countryCode) {
  switch (countryCode) {
    case 'SA':
    case 'BH':
    case 'YE':
      return CalculationMethod.ummAlQura;
    case 'EG':
    case 'PS':
      return CalculationMethod.egyptian;
    case 'AE':
      return CalculationMethod.dubai;
    case 'QA':
      return CalculationMethod.qatar;
    case 'KW':
      return CalculationMethod.kuwait;
    case 'TR':
      return CalculationMethod.turkey;
    case 'IR':
      return CalculationMethod.tehran;
    case 'SG':
    case 'MY':
    case 'ID':
      return CalculationMethod.singapore;
    case 'PK':
    case 'IN':
    case 'BD':
    case 'AF':
      return CalculationMethod.karachi;
    case 'US':
    case 'CA':
      return CalculationMethod.isna;
    default:
      return CalculationMethod.mwl;
  }
}

/// كل المدن (10 آلاف) — تُحمَّل مرة واحدة.
final citiesRepositoryProvider = FutureProvider<CitiesRepository>((ref) async {
  final raw = await rootBundle.loadString('assets/db/cities.json');
  final list = (jsonDecode(raw) as List)
      .cast<Map<String, dynamic>>()
      .map(City.fromJson)
      .toList(growable: false);
  return CitiesRepository(list);
});
