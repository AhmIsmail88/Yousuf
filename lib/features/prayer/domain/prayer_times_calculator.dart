import 'package:adhan_dart/adhan_dart.dart' as adhan;
import 'package:timezone/data/latest_all.dart' as tz_db;
import 'package:timezone/timezone.dart' as tz;

import 'prayer_times_models.dart';

/// حساب المواقيت في Dart — مصدر العرض الوحيد على الجهاز (CONTRACTS §3).
///
/// نفس منطق adhan2 في Kotlin؛ اختبار التطابق في tools/parity يضمن
/// أن الطرفين يتفقان بالدقيقة (SPEC §11).
class PrayerTimesCalculator {
  PrayerTimesCalculator._();

  static bool _timezonesReady = false;

  /// تهيئة قاعدة بيانات المناطق الزمنية — مرة واحدة لكل عملية.
  static void ensureTimezones() {
    if (_timezonesReady) return;
    tz_db.initializeTimeZones();
    _timezonesReady = true;
  }

  /// يحسب مواقيت يوم كامل لموقع بطريقة ومذهب وتعديلات محددة.
  static PrayerTimesDay forDate({
    required PrayerLocation location,
    required DateTime date,
    CalculationMethod method = CalculationMethod.ummAlQura,
    AsrMadhab madhab = AsrMadhab.shafi,
    HighLatRule highLatRule = HighLatRule.middleOfTheNight,
    PrayerAdjustments adjustments = const PrayerAdjustments(),
  }) {
    ensureTimezones();
    final parameters = _parametersFor(method, madhab, highLatRule, adjustments);
    final times = adhan.PrayerTimes(
      date: DateTime(date.year, date.month, date.day),
      coordinates: adhan.Coordinates(location.latitude, location.longitude),
      calculationParameters: parameters,
    );
    final sunnah = adhan.SunnahTimes(times);
    final zone = tz.getLocation(location.timezoneId);

    String format(DateTime utc) => _hhmm(tz.TZDateTime.from(utc, zone));

    final sunriseLocal = tz.TZDateTime.from(times.sunrise, zone);
    return PrayerTimesDay(
      date: DateTime(date.year, date.month, date.day),
      fajr: format(times.fajr),
      sunrise: format(times.sunrise),
      dhuhr: format(times.dhuhr),
      asr: format(times.asr),
      maghrib: format(times.maghrib),
      isha: format(times.isha),
      duha: _hhmm(sunriseLocal.add(const Duration(minutes: 15))),
      middleOfTheNight: format(sunnah.middleOfTheNight),
      lastThirdOfTheNight: format(sunnah.lastThirdOfTheNight),
    );
  }

  /// هل الموقع داخل نطاق حساب آمن؟ (الدوائر القطبية خارج النطاق).
  static bool isSupportedLocation(PrayerLocation location) =>
      location.latitude.abs() < 66.0;

  /// الصلاة القادمة من قائمة أيام محسوبة — للعرض والعد التنازلي.
  static ({PrayerName prayer, String time})? nextPrayer(
    PrayerTimesDay day,
    String nowHhmm,
  ) {
    final now = _minutesOfDay(nowHhmm);
    for (final prayer in PrayerName.values) {
      if (prayer == PrayerName.sunrise) continue; // الشروق ليس صلاة
      final minutes = _minutesOfDay(day.timeFor(prayer));
      if (minutes > now) return (prayer: prayer, time: day.timeFor(prayer));
    }
    return null;
  }

  static adhan.CalculationParameters _parametersFor(
    CalculationMethod method,
    AsrMadhab madhab,
    HighLatRule highLatRule,
    PrayerAdjustments adjustments,
  ) {
    final parameters = switch (method) {
      CalculationMethod.ummAlQura =>
        adhan.CalculationMethodParameters.ummAlQura(),
      CalculationMethod.egyptian =>
        adhan.CalculationMethodParameters.egyptian(),
      CalculationMethod.mwl =>
        adhan.CalculationMethodParameters.muslimWorldLeague(),
      CalculationMethod.isna =>
        adhan.CalculationMethodParameters.northAmerica(),
      CalculationMethod.karachi => adhan.CalculationMethodParameters.karachi(),
      CalculationMethod.kuwait => adhan.CalculationMethodParameters.kuwait(),
      CalculationMethod.qatar => adhan.CalculationMethodParameters.qatar(),
      CalculationMethod.dubai => adhan.CalculationMethodParameters.dubai(),
      CalculationMethod.singapore =>
        adhan.CalculationMethodParameters.singapore(),
      CalculationMethod.turkey => adhan.CalculationMethodParameters.turkiye(),
      // مطابق لـ Kotlin (PrayerCalc.parameters): OTHER بزاويتي ١٧٫٧° و١٤°.
      CalculationMethod.tehran =>
        adhan.CalculationMethodParameters.other()
          ..fajrAngle = 17.7
          ..ishaAngle = 14.0,
    };

    parameters.madhab = madhab == AsrMadhab.hanafi
        ? adhan.Madhab.hanafi
        : adhan.Madhab.shafi;
    parameters.highLatitudeRule = switch (highLatRule) {
      HighLatRule.middleOfTheNight => adhan.HighLatitudeRule.middleOfTheNight,
      HighLatRule.seventhOfTheNight => adhan.HighLatitudeRule.seventhOfTheNight,
      HighLatRule.twilightAngle => adhan.HighLatitudeRule.twilightAngle,
    };
    parameters.adjustments = {
      adhan.Prayer.fajr: adjustments.fajr,
      adhan.Prayer.sunrise: adjustments.sunrise,
      adhan.Prayer.dhuhr: adjustments.dhuhr,
      adhan.Prayer.asr: adjustments.asr,
      adhan.Prayer.maghrib: adjustments.maghrib,
      adhan.Prayer.isha: adjustments.isha,
    };
    return parameters;
  }

  static String _hhmm(DateTime local) =>
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';

  static int _minutesOfDay(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}
