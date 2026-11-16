import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// جسر محرّك التعرّف الصوتي (Android SpeechRecognizer) — وضع الحفظ.
///
/// كل المعالجة على الجهاز: لا يُرسل صوت المستخدم إلى أي خادم تابع للتطبيق.
class SpeechEventKind {
  SpeechEventKind._();

  static const started = 'started';
  static const ready = 'ready';
  static const speechStart = 'speech_start';
  static const speechEnd = 'speech_end';
  static const level = 'level';
  static const partial = 'partial';
  static const finalResult = 'final';
  static const error = 'error';
}

/// حدث واحد من محرّك التعرّف.
class SpeechEvent {
  const SpeechEvent({
    required this.type,
    this.text = '',
    this.code = '',
    this.onDevice = false,
    this.level = 0,
  });

  final String type;
  final String text;
  final String code;
  final bool onDevice;
  final double level;

  bool get isText =>
      type == SpeechEventKind.partial || type == SpeechEventKind.finalResult;

  bool get isError => type == SpeechEventKind.error;

  static SpeechEvent fromMap(Object? raw) {
    if (raw is! Map) return const SpeechEvent(type: 'unknown');
    return SpeechEvent(
      type: (raw['type'] as String?) ?? 'unknown',
      text: (raw['text'] as String?) ?? '',
      code: (raw['code'] as String?) ?? '',
      onDevice: (raw['onDevice'] as bool?) ?? false,
      level: (raw['value'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// إمكانات المحرّك على هذا الجهاز.
class SpeechAvailability {
  const SpeechAvailability({
    required this.available,
    required this.onDevice,
    required this.permission,
    this.reason = 'unsupported',
    this.downloadable = false,
    this.locale = '',
  });

  final bool available;
  final bool onDevice;
  final bool permission;

  /// ok | old_android | no_engine | needs_download | no_arabic | unsupported
  final String reason;

  /// هل يمكن تنزيل النموذج العربي للعمل دون إنترنت؟
  final bool downloadable;

  /// الوسم العربي المثبّت على المحرّك (ar-SA، ar-EG…).
  final String locale;

  static const none = SpeechAvailability(
    available: false,
    onDevice: false,
    permission: false,
  );

  static SpeechAvailability fromMap(Map<Object?, Object?>? map) =>
      SpeechAvailability(
        available: (map?['available'] as bool?) ?? false,
        onDevice: (map?['onDevice'] as bool?) ?? false,
        permission: (map?['permission'] as bool?) ?? false,
        reason: (map?['reason'] as String?) ?? 'unsupported',
        downloadable: (map?['downloadable'] as bool?) ?? false,
        locale: (map?['locale'] as String?) ?? '',
      );
}

class SpeechChannel {
  SpeechChannel();

  static const MethodChannel _methods = MethodChannel('app.yousuf/speech');
  static const EventChannel _events = EventChannel('app.yousuf/speech_events');

  static Stream<SpeechEvent>? _cached;

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  Stream<SpeechEvent> get events =>
      _cached ??= _events.receiveBroadcastStream().map(SpeechEvent.fromMap);

  Future<SpeechAvailability> availability() async {
    if (!isSupported) return SpeechAvailability.none;
    try {
      final map = await _methods.invokeMapMethod<Object?, Object?>(
        'availability',
      );
      return SpeechAvailability.fromMap(map);
    } catch (_) {
      return SpeechAvailability.none;
    }
  }

  /// يطلب تنزيل نموذج التعرّف العربي على الجهاز (أندرويد 13+).
  Future<bool> downloadArabic() async {
    if (!isSupported) return false;
    try {
      return await _methods.invokeMethod<bool>('downloadArabic') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> start({String locale = 'ar-SA'}) async {
    if (!isSupported) return false;
    try {
      return await _methods.invokeMethod<bool>('start', {'locale': locale}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _methods.invokeMethod<void>('stop');
    } catch (_) {
      // تجاهل — المحرك قد يكون متوقفاً.
    }
  }

  Future<void> cancel() async {
    if (!isSupported) return;
    try {
      await _methods.invokeMethod<void>('cancel');
    } catch (_) {
      // تجاهل.
    }
  }
}

/// رسالة واضحة لسبب عدم توفّر التسميع.
({String ar, String en}) speechUnavailableMessage(
  SpeechAvailability a,
) => switch (a.reason) {
  'needs_model' when a.downloadable => (
    ar: 'نموذج التسميع القرآني (≈١٤٨ م.ب) غير موجود بعد — اضغط «تنزيل النموذج»',
    en: 'The Quran recitation model (≈148 MB) is not installed — tap “Download model”',
  ),
  'needs_model' => (
    ar: 'نموذج التسميع القرآني غير متاح في هذه النسخة بعد',
    en: 'The Quran recitation model is not available in this version yet',
  ),
  'needs_download' => (
    ar: 'حزمة التعرّف العربي غير مثبّتة على الهاتف — اضغط «تنزيل العربية» ثم أعد المحاولة',
    en: 'The Arabic recognition pack is not installed — tap “Download Arabic”, then try again',
  ),
  'no_arabic' => (
    ar: 'محرّك التعرّف على هاتفك لا يدعم العربية دون إنترنت — استخدم «اكشف»',
    en: 'Your phone recognizer has no offline Arabic — use “Reveal”',
  ),
  'old_android' => (
    ar: 'التسميع دون إنترنت يحتاج أندرويد ١٢ أو أحدث — استخدم «اكشف»',
    en: 'Offline recitation check needs Android 12+ — use “Reveal”',
  ),
  'no_engine' => (
    ar: 'لا يوجد محرّك تعرّف على الجهاز — ثبّت/حدّث تطبيق Google أو «خدمات التعرّف على الكلام»',
    en: 'No on-device recognizer — install or update Google / Speech Services',
  ),
  _ => (
    ar: 'التسميع غير متاح على هذا الجهاز — استخدم «اكشف»',
    en: 'Recitation check is unavailable on this device — use “Reveal”',
  ),
};
