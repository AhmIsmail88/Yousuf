import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock_providers.dart';
import '../../../core/utils/quran_text.dart';
import '../../prayer/data/prayer_settings_repository.dart';
import '../../prayer/domain/prayer_times_models.dart';
import '../../prayer/presentation/prayer_providers.dart';
import '../../quran/presentation/quran_providers.dart';

/// بيانات بطاقة الرئيسية: مواقيت اليوم + فجر الغد.
///
/// تعتمد على [todayProvider] (تاريخ اليوم بتوقيت المدينة)، فتُعاد حساباً
/// تلقائياً بعد منتصف الليل حتى لو بقي التطبيق مفتوحاً.
class HomeData {
  const HomeData({
    required this.settings,
    required this.date,
    required this.today,
    required this.tomorrowFajr,
  });

  final PrayerSettings settings;

  /// تاريخ اليوم بتوقيت الموقع.
  final DateTime date;
  final PrayerTimesDay today;
  final String tomorrowFajr;

  PrayerLocation get location => settings.location;

  /// إزاحة الهجري المختارة (−2..+2).
  int get hijriOffsetDays => settings.hijriOffsetDays;
}

final homeDataProvider = FutureProvider<HomeData>((ref) async {
  final settings = await ref.watch(prayerSettingsProvider.future);
  final today = ref.watch(todayProvider);
  return HomeData(
    settings: settings,
    date: today,
    today: timesFor(settings, today),
    tomorrowFajr: timesFor(
      settings,
      DateTime(today.year, today.month, today.day + 1),
    ).fajr,
  );
});

/// آية اليوم — قائمة منتقاة مبدئية (TODO: 365 آية بعد اعتماد القائمة، SPEC §7.2).
const _verseOfDay = <(int, int)>[
  (2, 286),
  (2, 152),
  (3, 139),
  (13, 28),
  (39, 53),
  (40, 60),
  (65, 3),
  (94, 5),
  (2, 216),
  (3, 200),
];

typedef VerseOfDay = ({int surahId, int number, String text, String surahName});

final verseOfDayProvider = FutureProvider<VerseOfDay?>((ref) async {
  final repository = await ref.watch(quranRepositoryProvider.future);
  final today = ref.watch(todayProvider);
  final dayOfYear = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(today.year)).inDays;
  final pick = _verseOfDay[dayOfYear % _verseOfDay.length];
  final ayah = repository.ayahOf(pick.$1, pick.$2);
  if (ayah == null) return null;
  final surah = repository.surah(pick.$1);
  return (
    surahId: pick.$1,
    number: pick.$2,
    text: displayQuranText(
      ayahTextForSharing(ayah.text, surahId: pick.$1, number: pick.$2),
    ),
    surahName: surah?.nameAr ?? '',
  );
});
