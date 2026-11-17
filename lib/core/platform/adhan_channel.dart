import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart';

/// إعداد محرك الأذان — يطابق CONTRACTS §2 حرفياً.
class AdhanConfig {
  const AdhanConfig({
    required this.latitude,
    required this.longitude,
    required this.timezoneId,
    required this.method,
    required this.madhab,
    required this.highLatRule,
    required this.adjustments,
    required this.prayerSounds,
    required this.prePrayerAlertMinutes,
    required this.iqamaReminderMinutes,
    required this.respectSilentMode,
  });

  final double latitude;
  final double longitude;
  final String timezoneId;
  final String method;
  final String madhab;
  final String highLatRule;
  final Map<String, int> adjustments;

  /// لكل صلاة: {'mode': full|takbir|notification|off, 'sound': abdelbaset|menshawi|makkah}
  final Map<String, Map<String, String>> prayerSounds;

  final int prePrayerAlertMinutes;
  final int iqamaReminderMinutes;
  final bool respectSilentMode;

  Map<String, Object?> toMap() => {
    'latitude': latitude,
    'longitude': longitude,
    'timezoneId': timezoneId,
    'method': method,
    'madhab': madhab,
    'highLatRule': highLatRule,
    'adjustments': adjustments,
    'prayerSounds': prayerSounds,
    'prePrayerAlertMinutes': prePrayerAlertMinutes,
    'iqamaReminderMinutes': iqamaReminderMinutes,
    'respectSilentMode': respectSilentMode,
  };
}

/// منبّه مجدول يعيده المحرك.
class AdhanAlarm {
  const AdhanAlarm({
    required this.prayer,
    required this.epochMs,
    required this.kind,
  });

  final String prayer;
  final int epochMs;
  final String kind; // adhan | pre_prayer | test

  factory AdhanAlarm.fromMap(Map<Object?, Object?> map) => AdhanAlarm(
    prayer: map['prayer'] as String? ?? '',
    epochMs: (map['epochMs'] as num?)?.toInt() ?? 0,
    kind: map['kind'] as String? ?? 'adhan',
  );
}

/// حالة محرك الأذان (CONTRACTS §1: getStatus).
class AdhanStatus {
  const AdhanStatus({
    required this.exactAlarmAllowed,
    required this.notificationsAllowed,
    required this.batteryOptimized,
    required this.nextAlarms,
    this.playing = false,
    this.availableSounds = const [],
    this.scheduledNextEpochMs = 0,
    this.manufacturer = '',
    this.autostartSettingsAvailable = false,
    this.alarmVolumePercent = 100,
  });

  /// صوت المنبّه في الهاتف (٠–١٠٠) — الأذان يُشغَّل عليه.
  final int alarmVolumePercent;

  /// صوت المنبّه أقل من ٤٠٪: الأذان قد لا يُسمع جيداً.
  bool get alarmVolumeLow => alarmVolumePercent < 40;

  final bool exactAlarmAllowed;
  final bool notificationsAllowed;
  final bool batteryOptimized;
  final List<AdhanAlarm> nextAlarms;

  /// هل الأذان يُشغَّل الآن؟ (لعرض زر إيقاف داخل التطبيق)
  final bool playing;

  /// أصوات المؤذنين الموجودة فعلاً في الحزمة (بلا البديل المؤقت).
  final List<String> availableSounds;

  /// وقت أقرب أذان مجدول فعلاً (0 = لا شيء).
  final int scheduledNextEpochMs;

  /// الشركة المصنّعة (xiaomi، huawei…) — لتنبيه «التشغيل التلقائي».
  final String manufacturer;

  /// هل توجد شاشة «تشغيل تلقائي» خاصة بالشركة؟
  final bool autostartSettingsAvailable;

  /// شركات معروفة بقتل المنبّهات في الخلفية.
  bool get aggressiveOem => const {
    'xiaomi',
    'redmi',
    'poco',
    'huawei',
    'honor',
    'oppo',
    'realme',
    'oneplus',
    'vivo',
    'iqoo',
  }.contains(manufacturer);

  /// حالة محايدة على المنصات غير المدعومة.
  static const unsupported = AdhanStatus(
    exactAlarmAllowed: true,
    notificationsAllowed: true,
    batteryOptimized: false,
    nextAlarms: [],
  );

  factory AdhanStatus.fromMap(Map<Object?, Object?> map) => AdhanStatus(
    exactAlarmAllowed: map['exactAlarmAllowed'] as bool? ?? false,
    notificationsAllowed: map['notificationsAllowed'] as bool? ?? false,
    batteryOptimized: map['batteryOptimized'] as bool? ?? false,
    nextAlarms: ((map['nextAlarms'] as List?) ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(AdhanAlarm.fromMap)
        .toList(growable: false),
    playing: map['playing'] as bool? ?? false,
    availableSounds: ((map['availableSounds'] as List?) ?? const [])
        .whereType<String>()
        .toList(growable: false),
    scheduledNextEpochMs: (map['scheduledNextEpochMs'] as num?)?.toInt() ?? 0,
    manufacturer: map['manufacturer'] as String? ?? '',
    autostartSettingsAvailable:
        map['autostartSettingsAvailable'] as bool? ?? false,
    alarmVolumePercent: (map['alarmVolumePercent'] as num?)?.toInt() ?? 100,
  );
}

/// نتيجة الجدولة (CONTRACTS §1: applyConfig / testAdhanIn).
class AdhanSchedule {
  const AdhanSchedule({required this.scheduled, required this.nextEpochMs});

  final int scheduled;
  final int nextEpochMs;

  static const empty = AdhanSchedule(scheduled: 0, nextEpochMs: 0);

  factory AdhanSchedule.fromMap(Map<Object?, Object?>? map) => AdhanSchedule(
    scheduled: (map?['scheduled'] as num?)?.toInt() ?? 0,
    nextEpochMs: (map?['next'] as num?)?.toInt() ?? 0,
  );
}

/// جسر قناة `yousuf/adhan` مع محرك الأذان الأصلي (SPEC §6، CONTRACTS §1).
///
/// أخطاء المنصة تُسجَّل (debugPrint) ثم تُرمى للمستدعي كما هي.
class AdhanChannel {
  AdhanChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('yousuf/adhan');

  final MethodChannel _channel;

  static const EventChannel _events = EventChannel('yousuf/adhan_events');

  /// حالة تشغيل الأذان لحظة تغيّرها (true = يُشغَّل الآن).
  static Stream<bool> playingStream() {
    if (!isSupported) return Stream<bool>.value(false);
    return _events.receiveBroadcastStream().map((event) => event == true);
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      debugPrint('[YousufAdhan] $method فشل: ${error.code} ${error.message}');
      rethrow;
    }
  }

  Future<Map<Object?, Object?>?> _invokeMap(
    String method, [
    Object? arguments,
  ]) async {
    final result = await _invoke<Map<Object?, Object?>>(method, arguments);
    return result;
  }

  /// المحرك متاح على أندرويد فقط (iOS: إشعارات فقط).
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<AdhanSchedule> applyConfig(AdhanConfig config) async {
    if (!isSupported) return AdhanSchedule.empty;
    final result = await _invokeMap('applyConfig', config.toMap());
    return AdhanSchedule.fromMap(result);
  }

  Future<AdhanStatus> status() async {
    if (!isSupported) return AdhanStatus.unsupported;
    final result = await _invokeMap('getStatus');
    return AdhanStatus.fromMap(result ?? const {});
  }

  Future<bool> requestExactAlarm() async {
    if (!isSupported) return false;
    return await _invoke<bool>('requestExactAlarm') ?? false;
  }

  /// يفتح إعدادات الصوت (لرفع صوت المنبّه).
  Future<bool> openSoundSettings() async {
    if (!isSupported) return false;
    return await _invoke<bool>('openSoundSettings') ?? false;
  }

  Future<bool> openBatterySettings() async {
    if (!isSupported) return false;
    return await _invoke<bool>('openBatterySettings') ?? false;
  }

  /// الانحراف المغناطيسي بالدرجات (موجب = شرقاً) لتصحيح البوصلة إلى الشمال
  /// الجغرافي. أندرويد فقط؛ على iOS تعطي البوصلة الشمال الجغرافي أصلاً.
  Future<double> magneticDeclination(double latitude, double longitude) async {
    if (!isSupported) return 0;
    return await _invoke<double>('magneticDeclination', {
          'latitude': latitude,
          'longitude': longitude,
        }) ??
        0;
  }

  /// شاشة «التشغيل التلقائي» (شاومي/هواوي/أوبو/فيفو…).
  Future<bool> openAutostartSettings() async {
    if (!isSupported) return false;
    return await _invoke<bool>('openAutostartSettings') ?? false;
  }

  Future<bool> previewSound(String soundId) async {
    if (!isSupported) return false;
    return await _invoke<bool>('previewSound', {'soundId': soundId}) ?? false;
  }

  Future<bool> stopSound() async {
    if (!isSupported) return false;
    return await _invoke<bool>('stopSound') ?? false;
  }

  /// يوقف الأذان الجاري فوراً (نفس زر الإيقاف في الإشعار).
  Future<bool> stopAdhan() => stopSound();

  Future<AdhanSchedule> testAdhanIn(int seconds) async {
    if (!isSupported) return AdhanSchedule.empty;
    final result = await _invokeMap('testAdhanIn', {'seconds': seconds});
    return AdhanSchedule.fromMap(result);
  }
}
