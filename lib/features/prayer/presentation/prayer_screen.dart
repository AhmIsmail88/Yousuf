import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:yousuf/core/time/clock_providers.dart';
import 'package:yousuf/core/utils/time_format.dart';
import 'package:yousuf/l10n/generated/app_localizations.dart';

import '../domain/prayer_times_calculator.dart';
import '../domain/prayer_times_models.dart';
import 'prayer_providers.dart';

const _prayerIcons = <PrayerName, IconData>{
  PrayerName.fajr: Icons.wb_twilight,
  PrayerName.sunrise: Icons.wb_sunny_outlined,
  PrayerName.dhuhr: Icons.light_mode_outlined,
  PrayerName.asr: Icons.wb_sunny_outlined,
  PrayerName.maghrib: Icons.nights_stay_outlined,
  PrayerName.isha: Icons.dark_mode_outlined,
};

/// شاشة مواقيت اليوم — م1 (SPEC §7.5).
///
/// الوقت الحالي بتوقيت المدينة المختارة (`locationNowProvider`) ويُحدَّث كل
/// دقيقة، و«اليوم» يتقدّم تلقائياً بعد منتصف الليل.
class PrayerScreen extends ConsumerWidget {
  const PrayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final selectedDay = ref.watch(selectedDayProvider);
    final timesAsync = ref.watch(prayerTimesProvider);
    final settings = ref.watch(prayerSettingsProvider).value;
    final city =
        settings?.location.displayName(arabic: context.isArabic) ??
        context.tr('الرياض', 'Riyadh');

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabPrayer),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Chip(
              avatar: const Icon(Icons.location_on_outlined, size: 16),
              label: Text(city),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: timesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            context.tr(
              'تعذر حساب المواقيت: $error',
              'Could not calculate prayer times: $error',
            ),
          ),
        ),
        data: (times) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _DateNavigator(selectedDay: selectedDay),
            const SizedBox(height: 12),
            _TimesCard(times: times, selectedDay: selectedDay),
            const SizedBox(height: 12),
            Row(
              children: [
                if (times.duha != null)
                  Expanded(
                    child: _InfoCard(
                      title: context.tr('الضحى', 'Duha'),
                      time: times.duha!,
                      icon: Icons.wb_sunny_outlined,
                    ),
                  ),
                if (times.duha != null) const SizedBox(width: 12),
                if (times.lastThirdOfTheNight != null)
                  Expanded(
                    child: _InfoCard(
                      title: context.tr(
                        'الثلث الأخير من الليل',
                        'Last third of the night',
                      ),
                      time: times.lastThirdOfTheNight!,
                      icon: Icons.dark_mode_outlined,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateNavigator extends ConsumerWidget {
  const _DateNavigator({required this.selectedDay});

  final DateTime selectedDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isToday = ref.watch(selectedDayOffsetProvider) == 0;
    final notifier = ref.read(selectedDayOffsetProvider.notifier);

    return Row(
      children: [
        IconButton(
          onPressed: () => notifier.shift(-1),
          // الأيقونة تنعكس تلقائياً مع اتجاه الواجهة.
          icon: const Icon(Icons.chevron_right),
          tooltip: context.tr('اليوم السابق', 'Previous day'),
        ),
        Expanded(
          child: Text(
            context.formatDate(selectedDay),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          onPressed: () => notifier.shift(1),
          icon: const Icon(Icons.chevron_left),
          tooltip: context.tr('اليوم التالي', 'Next day'),
        ),
        if (!isToday)
          ActionChip(
            label: Text(context.tr('اليوم', 'Today')),
            onPressed: notifier.today,
          ),
      ],
    );
  }
}

class _TimesCard extends ConsumerWidget {
  const _TimesCard({required this.times, required this.selectedDay});

  final PrayerTimesDay times;
  final DateTime selectedDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(locationNowProvider);
    final isToday = ref.watch(selectedDayOffsetProvider) == 0;
    final nowHhmm = isToday
        ? '${now.hour.toString().padLeft(2, '0')}:'
              '${now.minute.toString().padLeft(2, '0')}'
        : null;
    final next = nowHhmm == null
        ? null
        : PrayerTimesCalculator.nextPrayer(times, nowHhmm);

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (final prayer in PrayerName.values)
            _PrayerRow(
              prayer: prayer,
              time: times.timeFor(prayer),
              isNext: next?.prayer == prayer,
              nowHhmm: nowHhmm,
            ),
        ],
      ),
    );
  }
}

class _PrayerRow extends StatelessWidget {
  const _PrayerRow({
    required this.prayer,
    required this.time,
    required this.isNext,
    this.nowHhmm,
  });

  final PrayerName prayer;
  final String time;
  final bool isNext;
  final String? nowHhmm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSunrise = prayer == PrayerName.sunrise;
    final color = isNext
        ? scheme.onPrimaryContainer
        : isSunrise
        ? scheme.onSurfaceVariant
        : scheme.onSurface;

    final remaining = (isNext && nowHhmm != null)
        ? TimeFormat.minutesOfDay(time) - TimeFormat.minutesOfDay(nowHhmm!)
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isNext ? scheme.primaryContainer : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(_prayerIcons[prayer], color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              prayer.label(arabic: context.isArabic),
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
          ),
          if (remaining != null && remaining > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Text(
                context.tr(
                  'بعد ${context.formatDuration(remaining)}',
                  'in ${context.formatDuration(remaining)}',
                ),
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ),
          Text(
            context.formatTime(time),
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: isNext ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.time,
    required this.icon,
  });

  final String title;
  final String time;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelMedium,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.formatTime(time),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
