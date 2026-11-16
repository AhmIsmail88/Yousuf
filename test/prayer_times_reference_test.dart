import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/core/utils/time_format.dart';
import 'package:yousuf/features/prayer/domain/prayer_times_calculator.dart';
import 'package:yousuf/features/prayer/domain/prayer_times_models.dart';

/// القيم المرجعية من CONTRACTS §5 (جُمعت 2026-11-10 من 4 مواقع متوافقة).
const _riyadhReference = {
  'fajr': '04:46',
  'sunrise': '06:05',
  'dhuhr': '11:38',
  'asr': '14:47',
  'maghrib': '17:09',
  'isha': '18:39',
};

const _cairoReference = {
  'fajr': '04:46',
  'sunrise': '06:15',
  'dhuhr': '11:39',
  'asr': '14:41',
  'maghrib': '17:02',
  'isha': '18:21',
};

const _cairo = PrayerLocation(
  latitude: 30.0444,
  longitude: 31.2357,
  timezoneId: 'Africa/Cairo',
  cityName: 'القاهرة',
);

void _expectClose(
  Map<String, String> actual,
  Map<String, String> reference,
  String city,
) {
  reference.forEach((prayer, expected) {
    final value = actual[prayer]!;
    final diff =
        (TimeFormat.minutesOfDay(value) - TimeFormat.minutesOfDay(expected))
            .abs();
    expect(
      diff <= 2,
      isTrue,
      reason:
          '$city / $prayer: المحسوب $value والمرجع $expected '
          '(فرق $diff دقيقة) — راجع الطريقة أو القيم المرجعية',
    );
  });
}

void main() {
  test('الرياض 2026-11-10 — أم القرى — ضمن دقيقتين من المرجع', () {
    final day = PrayerTimesCalculator.forDate(
      location: PrayerLocation.riyadh,
      date: DateTime(2026, 11, 10),
    );
    _expectClose(day.toTimesMap(), _riyadhReference, 'الرياض');
  });

  test('القاهرة 2026-11-10 — الهيئة المصرية — ضمن دقيقتين من المرجع', () {
    final day = PrayerTimesCalculator.forDate(
      location: _cairo,
      date: DateTime(2026, 11, 10),
      method: CalculationMethod.egyptian,
    );
    _expectClose(day.toTimesMap(), _cairoReference, 'القاهرة');
  });

  test('العشاء في أم القرى = المغرب + 90 دقيقة (قاعدة التقويم)', () {
    final day = PrayerTimesCalculator.forDate(
      location: PrayerLocation.riyadh,
      date: DateTime(2027, 3, 15),
    );
    final diff = TimeFormat.minutesBetween(day.maghrib, day.isha);
    expect(diff, 90);
  });

  test('المذهب الحنفي يؤخر العصر عن الجمهور', () {
    final shafi = PrayerTimesCalculator.forDate(
      location: PrayerLocation.riyadh,
      date: DateTime(2026, 11, 10),
    );
    final hanafi = PrayerTimesCalculator.forDate(
      location: PrayerLocation.riyadh,
      date: DateTime(2026, 11, 10),
      madhab: AsrMadhab.hanafi,
    );
    expect(
      TimeFormat.minutesOfDay(hanafi.asr),
      greaterThan(TimeFormat.minutesOfDay(shafi.asr)),
    );
  });

  test('التعديلات بالدقائق تُطبق على الوقت', () {
    final base = PrayerTimesCalculator.forDate(
      location: PrayerLocation.riyadh,
      date: DateTime(2026, 11, 10),
    );
    final adjusted = PrayerTimesCalculator.forDate(
      location: PrayerLocation.riyadh,
      date: DateTime(2026, 11, 10),
      adjustments: const PrayerAdjustments(fajr: 5, isha: -3),
    );
    expect(TimeFormat.minutesBetween(base.fajr, adjusted.fajr), 5);
    expect(TimeFormat.minutesBetween(base.isha, adjusted.isha), -3);
  });

  test('منتصف الليل والثلث الأخير داخل ليل المغرب→الفجر', () {
    final day = PrayerTimesCalculator.forDate(
      location: PrayerLocation.riyadh,
      date: DateTime(2026, 11, 10),
    );
    final maghrib = TimeFormat.minutesOfDay(day.maghrib);
    // الليل يعبر منتصف الليل، فنقيس الإزاحة دورياً من المغرب.
    int nightOffset(int minutes) => (minutes - maghrib) % (24 * 60);
    final middle = nightOffset(TimeFormat.minutesOfDay(day.middleOfTheNight!));
    final lastThird = nightOffset(
      TimeFormat.minutesOfDay(day.lastThirdOfTheNight!),
    );
    expect(middle, greaterThan(0));
    expect(lastThird, greaterThan(middle)); // الثلث الأخير بعد المنتصف
    expect(lastThird, lessThan(12 * 60)); // وما زال داخل الليل
  });

  test('الصلاة القادمة تُحدد صحيحاً من الوقت الحالي', () {
    final day = PrayerTimesCalculator.forDate(
      location: PrayerLocation.riyadh,
      date: DateTime(2026, 11, 10),
    );
    final next = PrayerTimesCalculator.nextPrayer(day, '12:00');
    expect(next?.prayer, PrayerName.asr);
    final none = PrayerTimesCalculator.nextPrayer(day, '23:00');
    expect(none, isNull); // بعد العشاء: الصلاة القادمة فجر الغد
  });

  test('الموقع خارج النطاق الآمن يُرفض', () {
    const arctic = PrayerLocation(
      latitude: 70,
      longitude: 20,
      timezoneId: 'Europe/Oslo',
    );
    expect(PrayerTimesCalculator.isSupportedLocation(arctic), isFalse);
  });
}
