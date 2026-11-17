import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/platform/adhan_channel.dart';
import '../domain/adhan_sounds.dart';
import '../domain/prayer_times_models.dart';

/// صوت أذان لصلاة واحدة (CONTRACTS §2).
class PrayerSound {
  const PrayerSound({this.mode = 'full', this.sound = kDefaultAdhanSound});

  /// full | takbir | notification | off
  final String mode;

  /// معرّف من [kAdhanSounds] (makkah، abdelbaset، default…).
  final String sound;

  Map<String, String> toMap() => {'mode': mode, 'sound': sound};

  PrayerSound copyWith({String? mode, String? sound}) =>
      PrayerSound(mode: mode ?? this.mode, sound: sound ?? this.sound);

  /// قيم معروفة فقط؛ أي قيمة غريبة ترجع للافتراضي (كامل، الحرم المكي).
  factory PrayerSound.fromMap(Map<String, dynamic>? map) {
    const modes = {'full', 'takbir', 'notification', 'off'};
    final mode = map?['mode'] as String?;
    final sound = map?['sound'] as String?;
    return PrayerSound(
      mode: modes.contains(mode) ? mode! : 'full',
      sound: kAdhanSoundIds.contains(sound) ? sound! : kDefaultAdhanSound,
    );
  }

  /// الافتراضي حسب SPEC §8: أذان كامل للجميع، والفجر بصوت مختلف.
  static const defaults = <String, PrayerSound>{
    'fajr': PrayerSound(sound: 'abdelbaset'),
    'dhuhr': PrayerSound(sound: 'makkah'),
    'asr': PrayerSound(sound: 'makkah'),
    'maghrib': PrayerSound(sound: 'makkah'),
    'isha': PrayerSound(sound: 'makkah'),
  };
}

/// الصلوات الخمس التي تُجدول — الشروق ليس صلاة.
const scheduledPrayerIds = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

/// إعدادات الحساب والموقع — محلية فقط ولا تُرسل لأي سيرفر (SPEC §10).
class PrayerSettings {
  const PrayerSettings({
    this.location = PrayerLocation.riyadh,
    this.method = CalculationMethod.ummAlQura,
    this.madhab = AsrMadhab.shafi,
    this.highLatRule = HighLatRule.middleOfTheNight,
    this.adjustments = const PrayerAdjustments(),
    this.prayerSounds = PrayerSound.defaults,
    this.prePrayerAlertMinutes = 15,
    this.iqamaReminderMinutes = 0,
    this.respectSilentMode = false,
    this.hijriOffsetDays = 0,
  });

  final PrayerLocation location;
  final CalculationMethod method;
  final AsrMadhab madhab;
  final HighLatRule highLatRule;
  final PrayerAdjustments adjustments;
  final Map<String, PrayerSound> prayerSounds;
  final int prePrayerAlertMinutes;
  final int iqamaReminderMinutes;
  final bool respectSilentMode;

  /// إزاحة الهجري بالأيام (−2..+2) — SPEC §8.
  final int hijriOffsetDays;

  PrayerSettings copyWith({
    PrayerLocation? location,
    CalculationMethod? method,
    AsrMadhab? madhab,
    HighLatRule? highLatRule,
    PrayerAdjustments? adjustments,
    Map<String, PrayerSound>? prayerSounds,
    int? prePrayerAlertMinutes,
    int? iqamaReminderMinutes,
    bool? respectSilentMode,
    int? hijriOffsetDays,
  }) => PrayerSettings(
    location: location ?? this.location,
    method: method ?? this.method,
    madhab: madhab ?? this.madhab,
    highLatRule: highLatRule ?? this.highLatRule,
    adjustments: adjustments ?? this.adjustments,
    prayerSounds: prayerSounds ?? this.prayerSounds,
    prePrayerAlertMinutes: prePrayerAlertMinutes ?? this.prePrayerAlertMinutes,
    iqamaReminderMinutes: iqamaReminderMinutes ?? this.iqamaReminderMinutes,
    respectSilentMode: respectSilentMode ?? this.respectSilentMode,
    hijriOffsetDays: hijriOffsetDays ?? this.hijriOffsetDays,
  );

  /// صوت صلاة واحدة — يرجع الافتراضي إن لم يُعيَّن.
  PrayerSound soundFor(String prayerId) =>
      prayerSounds[prayerId] ??
      PrayerSound.defaults[prayerId] ??
      const PrayerSound();

  /// يبني AdhanConfig المطابق لعقد CONTRACTS §2.
  AdhanConfig toAdhanConfig() => AdhanConfig(
    latitude: location.latitude,
    longitude: location.longitude,
    timezoneId: location.timezoneId,
    method: method.id,
    madhab: madhab.id,
    highLatRule: highLatRule.id,
    adjustments: adjustments.toMap(),
    prayerSounds: prayerSounds.map(
      (key, value) => MapEntry(key, value.toMap()),
    ),
    prePrayerAlertMinutes: prePrayerAlertMinutes,
    iqamaReminderMinutes: iqamaReminderMinutes,
    respectSilentMode: respectSilentMode,
  );
}

/// حفظ واسترجاع إعدادات الصلاة على الجهاز (SPEC §5: shared_preferences).
class PrayerSettingsRepository {
  PrayerSettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  /// يُنشئ المستودع بعد تهيئة التخزين.
  static Future<PrayerSettingsRepository> create() async =>
      PrayerSettingsRepository(await SharedPreferences.getInstance());

  static const _kLat = 'prayer.location.lat';
  static const _kLng = 'prayer.location.lng';
  static const _kTz = 'prayer.location.tz';
  static const _kCity = 'prayer.location.city';
  static const _kCityEn = 'prayer.location.city_en';
  static const _kGps = 'prayer.location.gps';
  static const _kMethod = 'prayer.method';
  static const _kMadhab = 'prayer.madhab';
  static const _kHighLat = 'prayer.high_lat';
  static const _kPreAlert = 'prayer.pre_alert_minutes';
  static const _kIqama = 'prayer.iqama_minutes';

  /// «كتم الأذان في الوضع الصامت» — اختياري ومطفأ افتراضياً: الأذان بصوت دائماً.
  /// (المفتاح القديم prayer.respect_silent كان مفعّلاً افتراضياً ويُترك.)
  static const _kSilent = 'prayer.silent_mutes_adhan';
  static const _kHijriOffset = 'prayer.hijri_offset';

  static String _adjKey(String prayer) => 'prayer.adjustment.$prayer';
  static String _soundModeKey(String prayer) => 'prayer.sound.$prayer.mode';
  static String _soundIdKey(String prayer) => 'prayer.sound.$prayer.sound';

  /// يحمّل الإعدادات — افتراضيات الرياض عند أول تشغيل.
  PrayerSettings load() {
    final latitude = _prefs.getDouble(_kLat);
    if (latitude == null) return const PrayerSettings();
    return PrayerSettings(
      location: PrayerLocation(
        latitude: latitude,
        longitude: _prefs.getDouble(_kLng) ?? PrayerLocation.riyadh.longitude,
        timezoneId: _prefs.getString(_kTz) ?? PrayerLocation.riyadh.timezoneId,
        cityName: _prefs.getString(_kCity),
        cityNameEn: _prefs.getString(_kCityEn),
        fromGps: _prefs.getBool(_kGps) ?? false,
      ),
      method: CalculationMethod.fromId(_prefs.getString(_kMethod)),
      madhab: AsrMadhab.fromId(_prefs.getString(_kMadhab)),
      highLatRule: HighLatRule.fromId(_prefs.getString(_kHighLat)),
      adjustments: PrayerAdjustments(
        fajr: _prefs.getInt(_adjKey('fajr')) ?? 0,
        sunrise: _prefs.getInt(_adjKey('sunrise')) ?? 0,
        dhuhr: _prefs.getInt(_adjKey('dhuhr')) ?? 0,
        asr: _prefs.getInt(_adjKey('asr')) ?? 0,
        maghrib: _prefs.getInt(_adjKey('maghrib')) ?? 0,
        isha: _prefs.getInt(_adjKey('isha')) ?? 0,
      ),
      prayerSounds: {
        for (final prayer in scheduledPrayerIds)
          prayer: PrayerSound(
            mode:
                _prefs.getString(_soundModeKey(prayer)) ??
                PrayerSound.defaults[prayer]!.mode,
            sound:
                _prefs.getString(_soundIdKey(prayer)) ??
                PrayerSound.defaults[prayer]!.sound,
          ),
      },
      prePrayerAlertMinutes: _prefs.getInt(_kPreAlert) ?? 15,
      iqamaReminderMinutes: _prefs.getInt(_kIqama) ?? 0,
      respectSilentMode: _prefs.getBool(_kSilent) ?? false,
      hijriOffsetDays: (_prefs.getInt(_kHijriOffset) ?? 0).clamp(-2, 2),
    );
  }

  /// يحفظ الإعدادات محلياً.
  Future<void> save(PrayerSettings settings) async {
    await _prefs.setDouble(_kLat, settings.location.latitude);
    await _prefs.setDouble(_kLng, settings.location.longitude);
    await _prefs.setString(_kTz, settings.location.timezoneId);
    // اسم المدينة يُكتب أو يُمسح — لا يبقى اسم مدينة سابقة مع موقع جديد.
    await _setOrRemove(_kCity, settings.location.cityName);
    await _setOrRemove(_kCityEn, settings.location.cityNameEn);
    await _prefs.setBool(_kGps, settings.location.fromGps);
    await _prefs.setString(_kMethod, settings.method.id);
    await _prefs.setString(_kMadhab, settings.madhab.id);
    await _prefs.setString(_kHighLat, settings.highLatRule.id);
    await _prefs.setInt(_kPreAlert, settings.prePrayerAlertMinutes);
    await _prefs.setInt(_kIqama, settings.iqamaReminderMinutes);
    await _prefs.setBool(_kSilent, settings.respectSilentMode);
    await _prefs.setInt(_kHijriOffset, settings.hijriOffsetDays.clamp(-2, 2));
    for (final prayer in scheduledPrayerIds) {
      final sound = settings.soundFor(prayer);
      await _prefs.setString(_soundModeKey(prayer), sound.mode);
      await _prefs.setString(_soundIdKey(prayer), sound.sound);
    }
    final adjustments = settings.adjustments;
    await _prefs.setInt(_adjKey('fajr'), adjustments.fajr);
    await _prefs.setInt(_adjKey('sunrise'), adjustments.sunrise);
    await _prefs.setInt(_adjKey('dhuhr'), adjustments.dhuhr);
    await _prefs.setInt(_adjKey('asr'), adjustments.asr);
    await _prefs.setInt(_adjKey('maghrib'), adjustments.maghrib);
    await _prefs.setInt(_adjKey('isha'), adjustments.isha);
  }

  Future<void> _setOrRemove(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
  }

  /// يرسل الإعدادات لمحرك الأذان ويعيد حالته (أندرويد فقط).
  Future<AdhanStatus?> applyToEngine(
    PrayerSettings settings, {
    AdhanChannel? channel,
  }) async {
    if (!AdhanChannel.isSupported) return null;
    final bridge = channel ?? AdhanChannel();
    await bridge.applyConfig(settings.toAdhanConfig());
    return bridge.status();
  }
}
