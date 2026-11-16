import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../../core/time/clock_providers.dart';
import '../data/prayer_settings_repository.dart';
import '../domain/prayer_times_calculator.dart';
import '../domain/prayer_times_models.dart';

/// مستودع إعدادات الصلاة (تخزين محلي).
final prayerSettingsRepositoryProvider = Provider<PrayerSettingsRepository>(
  (ref) => PrayerSettingsRepository(ref.watch(sharedPreferencesProvider)),
);

/// إعدادات المستخدم الحالية — افتراضيات الرياض عند أول تشغيل.
final prayerSettingsProvider = FutureProvider<PrayerSettings>((ref) async {
  return ref.watch(prayerSettingsRepositoryProvider).load();
});

/// واجهة كتابة الإعدادات: تحفظ محلياً وتُرسل للمحرك فوراً (SPEC §8).
class PrayerSettingsController {
  PrayerSettingsController(this._ref);

  final Ref _ref;

  /// يحفظ الإعدادات، يعيد بناء المعروض منها، ويعيد جدولة الأذان.
  ///
  /// يعيد `false` إن حُفظت الإعدادات لكن تعذر تحديث جدولة الأذان (يُسجَّل
  /// الخطأ ويُعرض للمستخدم بدل ابتلاعه).
  Future<bool> save(PrayerSettings settings) async {
    final repository = _ref.read(prayerSettingsRepositoryProvider);
    await repository.save(settings);
    _ref.invalidate(prayerSettingsProvider);
    try {
      await repository.applyToEngine(settings);
      return true;
    } catch (error) {
      debugPrint('[YousufAdhan] تعذر إرسال الإعدادات للمحرك: $error');
      return false;
    }
  }
}

final prayerSettingsControllerProvider = Provider<PrayerSettingsController>(
  PrayerSettingsController.new,
);

/// إزاحة اليوم المعروض في شاشة المواقيت عن اليوم الحالي (٠ = اليوم).
///
/// نخزّن الإزاحة لا التاريخ، فيبقى «اليوم» صحيحاً بعد منتصف الليل.
class SelectedDayOffsetNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void shift(int days) => state += days;

  void today() => state = 0;
}

final selectedDayOffsetProvider =
    NotifierProvider<SelectedDayOffsetNotifier, int>(
      SelectedDayOffsetNotifier.new,
    );

/// اليوم المعروض في شاشة المواقيت.
final selectedDayProvider = Provider<DateTime>((ref) {
  final today = ref.watch(todayProvider);
  final offset = ref.watch(selectedDayOffsetProvider);
  return DateTime(today.year, today.month, today.day + offset);
});

/// مواقيت اليوم المحدد — تُحسب من الإعدادات المحفوظة.
final prayerTimesProvider = FutureProvider<PrayerTimesDay>((ref) async {
  final settings = await ref.watch(prayerSettingsProvider.future);
  final day = ref.watch(selectedDayProvider);
  return timesFor(settings, day);
});

/// مواقيت يوم لإعدادات معيّنة.
PrayerTimesDay timesFor(PrayerSettings settings, DateTime day) =>
    PrayerTimesCalculator.forDate(
      location: settings.location,
      date: day,
      method: settings.method,
      madhab: settings.madhab,
      highLatRule: settings.highLatRule,
      adjustments: settings.adjustments,
    );
