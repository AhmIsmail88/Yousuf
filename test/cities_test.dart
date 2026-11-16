import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/features/cities/data/cities_repository.dart';
import 'package:yousuf/features/prayer/domain/prayer_times_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CitiesRepository repository;

  setUpAll(() async {
    final raw = await rootBundle.loadString('assets/db/cities.json');
    final cities = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(City.fromJson)
        .toList(growable: false);
    repository = CitiesRepository(cities);
  });

  test('القاعدة تضم 10,000 مدينة', () {
    expect(repository.cities.length, 10000);
  });

  test('البحث العربي يجد القاهرة', () {
    final hits = repository.search('القاهرة');
    expect(hits, isNotEmpty);
    expect(hits.first.countryCode, 'EG');
  });

  test('البحث اللاتيني يعمل أيضاً', () {
    final hits = repository.search('cairo');
    expect(hits, isNotEmpty);
    expect(hits.first.nameAr, isNotEmpty);
  });

  test('أقرب مدينة لإحداثيات الرياض هي الرياض', () {
    final nearest = repository.nearest(24.7136, 46.6753);
    expect(nearest.nameEn.toLowerCase(), contains('riyadh'));
    expect(nearest.timezoneId, 'Asia/Riyadh');
  });

  test('طريقة الحساب الافتراضية حسب الدولة', () {
    expect(defaultMethodForCountry('SA'), CalculationMethod.ummAlQura);
    expect(defaultMethodForCountry('EG'), CalculationMethod.egyptian);
    expect(defaultMethodForCountry('AE'), CalculationMethod.dubai);
    expect(defaultMethodForCountry('PK'), CalculationMethod.karachi);
    expect(defaultMethodForCountry('US'), CalculationMethod.isna);
    expect(defaultMethodForCountry('ZZ'), CalculationMethod.mwl);
  });
}
