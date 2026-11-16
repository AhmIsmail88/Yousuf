import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/features/prayer/data/prayer_settings_repository.dart';
import 'package:yousuf/features/prayer/domain/prayer_times_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('الافتراضيات عند أول تشغيل: الرياض وأم القرى وشافعي', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await PrayerSettingsRepository.create();

    final settings = repo.load();
    expect(settings.location.latitude, PrayerLocation.riyadh.latitude);
    expect(settings.location.timezoneId, 'Asia/Riyadh');
    expect(settings.method, CalculationMethod.ummAlQura);
    expect(settings.madhab, AsrMadhab.shafi);
    expect(settings.adjustments.isZero, isTrue);
    expect(settings.prePrayerAlertMinutes, 15);
  });

  test('حفظ واسترجاع كل الحقول', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = await PrayerSettingsRepository.create();

    const settings = PrayerSettings(
      location: PrayerLocation(
        latitude: 30.0444,
        longitude: 31.2357,
        timezoneId: 'Africa/Cairo',
        cityName: 'القاهرة',
      ),
      method: CalculationMethod.egyptian,
      madhab: AsrMadhab.hanafi,
      highLatRule: HighLatRule.seventhOfTheNight,
      adjustments: PrayerAdjustments(fajr: 5, isha: -3),
      prePrayerAlertMinutes: 20,
      iqamaReminderMinutes: 10,
      respectSilentMode: false,
    );
    await repo.save(settings);

    final loaded = repo.load();
    expect(loaded.location.latitude, closeTo(30.0444, 1e-9));
    expect(loaded.location.cityName, 'القاهرة');
    expect(loaded.method, CalculationMethod.egyptian);
    expect(loaded.madhab, AsrMadhab.hanafi);
    expect(loaded.highLatRule, HighLatRule.seventhOfTheNight);
    expect(loaded.adjustments.fajr, 5);
    expect(loaded.adjustments.isha, -3);
    expect(loaded.prePrayerAlertMinutes, 20);
    expect(loaded.iqamaReminderMinutes, 10);
    expect(loaded.respectSilentMode, isFalse);
  });

  test(
    'أصوات الأذان تُحفظ لكل صلاة (إصلاح: كانت تُفقد بعد إعادة التشغيل)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = await PrayerSettingsRepository.create();

      final settings = const PrayerSettings().copyWith(
        prayerSounds: const {
          'fajr': PrayerSound(mode: 'takbir', sound: 'makkah'),
          'dhuhr': PrayerSound(mode: 'notification'),
          'asr': PrayerSound(mode: 'off'),
          'maghrib': PrayerSound(sound: 'menshawi'),
          'isha': PrayerSound(),
        },
        hijriOffsetDays: 1,
      );
      await repo.save(settings);

      final loaded = repo.load();
      expect(loaded.soundFor('fajr').mode, 'takbir');
      expect(loaded.soundFor('fajr').sound, 'makkah');
      expect(loaded.soundFor('dhuhr').mode, 'notification');
      expect(loaded.soundFor('asr').mode, 'off');
      expect(loaded.soundFor('maghrib').sound, 'menshawi');
      expect(loaded.hijriOffsetDays, 1);
    },
  );

  test('الإزاحة الهجرية محصورة في −٢..+٢', () async {
    SharedPreferences.setMockInitialValues({
      'prayer.location.lat': 24.7136,
      'prayer.hijri_offset': 9,
    });
    final repo = await PrayerSettingsRepository.create();
    expect(repo.load().hijriOffsetDays, 2);

    SharedPreferences.setMockInitialValues({
      'prayer.location.lat': 24.7136,
      'prayer.hijri_offset': -7,
    });
    final repo2 = await PrayerSettingsRepository.create();
    expect(repo2.load().hijriOffsetDays, -2);
  });

  test('AdhanConfig يطابق عقد CONTRACTS §2', () {
    const settings = PrayerSettings();
    final map = settings.toAdhanConfig().toMap();

    expect(map['method'], 'umm_al_qura');
    expect(map['madhab'], 'shafi');
    expect(map['highLatRule'], 'middle_of_the_night');
    expect(map['timezoneId'], 'Asia/Riyadh');
    expect(map['prePrayerAlertMinutes'], 15);
    expect(map['respectSilentMode'], isTrue);
    expect((map['adjustments'] as Map)['fajr'], 0);
    final sounds = map['prayerSounds'] as Map;
    expect((sounds['fajr'] as Map)['sound'], 'abdelbaset');
    expect((sounds['dhuhr'] as Map)['mode'], 'full');
  });
}
