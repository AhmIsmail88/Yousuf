import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yousuf/core/utils/quran_text.dart';
import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/app/theme/app_colors.dart';
import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:yousuf/core/share/share_card.dart';
import 'package:yousuf/core/time/clock_providers.dart';
import 'package:yousuf/core/utils/arabic_dates.dart';
import 'package:yousuf/core/utils/time_format.dart';

import '../../adhkar/presentation/adhkar_providers.dart';
import '../../khatma/presentation/khatma_providers.dart';
import '../../prayer/domain/prayer_times_calculator.dart';
import '../../prayer/domain/prayer_times_models.dart';
import '../../quran/presentation/mushaf_reader_screen.dart';
import '../../quran/presentation/quran_providers.dart';
import 'home_providers.dart';

/// اختصارات الرئيسية (٤×٢). باقي الأقسام في «المزيد».
class _Shortcut {
  const _Shortcut(this.icon, this.ar, this.en, this.route, {this.tab = false});

  final IconData icon;
  final String ar;
  final String en;
  final String route;

  /// تبويب سفلي (go) أم شاشة فوقه (push)؟
  final bool tab;
}

const _shortcuts = <_Shortcut>[
  _Shortcut(Icons.menu_book_outlined, 'المصحف', 'Quran', '/quran', tab: true),
  _Shortcut(
    Icons.auto_awesome_outlined,
    'الأذكار',
    'Adhkar',
    '/adhkar',
    tab: true,
  ),
  _Shortcut(Icons.explore_outlined, 'القبلة', 'Qibla', '/qibla'),
  _Shortcut(Icons.radio_button_checked, 'المسبحة', 'Tasbih', '/tasbih'),
  _Shortcut(Icons.auto_stories_outlined, 'الختمة', 'Khatma', '/khatma'),
  _Shortcut(Icons.calendar_month_outlined, 'التقويم', 'Calendar', '/calendar'),
  _Shortcut(Icons.child_care_outlined, 'الأطفال', 'Kids', '/kids'),
  _Shortcut(Icons.grid_view_outlined, 'المزيد', 'More', '/more'),
];

/// الرئيسية — م1 (SPEC §7.2): التاريخ الهجري والميلادي، الصلاة القادمة بعدّاد
/// حي، شريط المواقيت الستة، اختصارات، بطاقة ذكية حسب الوقت، آية اليوم، والورد.
///
/// الوقت بتوقيت المدينة المختارة ويُحدَّث كل دقيقة، والمواقيت تتجدد بعد
/// منتصف الليل تلقائياً.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(homeDataProvider);
    final now = ref.watch(locationNowProvider);

    return Scaffold(
      body: SafeArea(
        child: homeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(
              context.tr(
                'تعذر تحميل الرئيسية: $error',
                'Could not load home: $error',
              ),
            ),
          ),
          data: (data) {
            final nowHhmm =
                '${now.hour.toString().padLeft(2, '0')}:'
                '${now.minute.toString().padLeft(2, '0')}';
            final next = PrayerTimesCalculator.nextPrayer(data.today, nowHhmm);
            final arabic = context.isArabic;
            final nextName =
                next?.prayer.label(arabic: arabic) ??
                context.tr('الفجر (غداً)', 'Fajr (tomorrow)');
            final nextTime = next?.time ?? data.tomorrowFajr;
            final nowMinutes = TimeFormat.minutesOfDay(nowHhmm);
            final remaining = next == null
                ? (24 * 60 - nowMinutes) + TimeFormat.minutesOfDay(nextTime)
                : TimeFormat.minutesOfDay(nextTime) - nowMinutes;
            final hijri = hijriDay(data.date, offsetDays: data.hijriOffsetDays);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: context.tr('الإعدادات', 'Settings'),
                      onPressed: () => context.push('/settings'),
                    ),
                  ],
                ),
                _NextPrayerCard(
                  cityName:
                      data.location.displayName(arabic: arabic) ??
                      context.tr('موقعي', 'My location'),
                  date: data.date,
                  hijri: hijri,
                  nextName: nextName,
                  nextTime: nextTime,
                  remainingMinutes: remaining,
                  today: data.today,
                ),
                const SizedBox(height: 16),
                const _ShortcutGrid(),
                const SizedBox(height: 16),
                _SmartCard(today: data.today, now: now, hijri: hijri),
                const SizedBox(height: 16),
                const _VerseCard(),
                const SizedBox(height: 16),
                const _ReadingCard(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NextPrayerCard extends StatelessWidget {
  const _NextPrayerCard({
    required this.cityName,
    required this.date,
    required this.hijri,
    required this.nextName,
    required this.nextTime,
    required this.remainingMinutes,
    required this.today,
  });

  final String cityName;
  final DateTime date;
  final HijriDay? hijri;
  final String nextName;
  final String nextTime;
  final int remainingMinutes;
  final PrayerTimesDay today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arabic = context.isArabic;
    final hijriText = hijri == null ? null : context.formatHijri(hijri!);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.deepTeal, Color(0xFF3F8794)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/brand/logo_white.png',
                height: 34,
                fit: BoxFit.contain,
              ),
              const Spacer(),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            cityName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      context.formatDate(date),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white60,
                        fontSize: 10,
                      ),
                    ),
                    if (hijriText != null)
                      Text(
                        hijriText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('الصلاة القادمة', 'Next prayer'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      nextName,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontFamily: 'Amiri',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      remainingMinutes <= 0
                          ? context.tr('الآن', 'Now')
                          : context.tr(
                              'بعد ${context.formatDuration(remainingMinutes)}',
                              'in ${context.formatDuration(remainingMinutes)}',
                            ),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.sand,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                context.formatTime(nextTime),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontFamily: 'Amiri',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white24),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final prayer in PrayerName.values)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        prayer.label(arabic: arabic),
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.formatTime(
                          today.timeFor(prayer),
                          withPeriod: false,
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShortcutGrid extends StatelessWidget {
  const _ShortcutGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.95,
      children: [
        for (final shortcut in _shortcuts)
          _ShortcutTile(
            icon: shortcut.icon,
            label: context.tr(shortcut.ar, shortcut.en),
            onTap: () => shortcut.tab
                ? context.go(shortcut.route)
                : context.push(shortcut.route),
          ),
      ],
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: scheme.primary, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة ذكية حسب الوقت (SPEC §7.2): الجمعة الكهف، الأيام البيض صيام،
/// من الفجر إلى الظهر أذكار الصباح، من العصر إلى العشاء أذكار المساء،
/// وإلا الورد.
class _SmartCard extends ConsumerWidget {
  const _SmartCard({
    required this.today,
    required this.now,
    required this.hijri,
  });

  final PrayerTimesDay today;
  final DateTime now;
  final HijriDay? hijri;

  Future<void> _openReader(BuildContext context, int page) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => MushafReaderScreen(initialPage: page),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nowMinutes = now.hour * 60 + now.minute;
    final fajr = TimeFormat.minutesOfDay(today.fajr);
    final dhuhr = TimeFormat.minutesOfDay(today.dhuhr);
    final asr = TimeFormat.minutesOfDay(today.asr);
    final isha = TimeFormat.minutesOfDay(today.isha);

    late final IconData icon;
    late final String title;
    late final String body;
    late final String action;
    late final Future<void> Function() onTap;

    if (isFriday(now)) {
      icon = Icons.menu_book;
      title = context.tr('سورة الكهف', 'Surah Al-Kahf');
      body = context.tr(
        'يوم الجمعة — نور ما بين الجمعتين.',
        'Friday — a light between the two Fridays.',
      );
      action = context.tr('افتح المصحف', 'Open');
      onTap = () async {
        final repository = await ref.read(quranRepositoryProvider.future);
        final page = repository.startPageOfSurah(18);
        if (!context.mounted) return;
        await _openReader(context, page);
      };
    } else if (hijri?.isWhiteDay ?? false) {
      icon = Icons.nightlight_round;
      title = context.tr('الأيام البيض', 'The White Days');
      body = context.tr(
        'اليوم ${context.digits(hijri!.day)} من الشهر الهجري — من أيام الصيام المستحب.',
        'Day ${hijri!.day} of the Hijri month — a recommended day of fasting.',
      );
      action = context.tr('التقويم', 'Calendar');
      onTap = () async => context.push('/calendar');
    } else if (nowMinutes >= fajr && nowMinutes < dhuhr) {
      icon = Icons.wb_twilight;
      title = context.tr('أذكار الصباح', 'Morning adhkar');
      body = context.tr(
        'بدأ يومك — ابدأ بأذكار الصباح كما وردت.',
        'Your day has begun — start with the morning adhkar.',
      );
      action = context.tr('ابدأ الآن', 'Start');
      onTap = () async {
        ref.read(adhkarSelectionProvider.notifier).select('morning');
        context.go('/adhkar');
      };
    } else if (nowMinutes >= asr && nowMinutes < isha) {
      icon = Icons.nights_stay_outlined;
      title = context.tr('أذكار المساء', 'Evening adhkar');
      body = context.tr(
        'أقبل المساء — أذكار المساء حصنك حتى الصباح.',
        'Evening is here — the evening adhkar protect you until morning.',
      );
      action = context.tr('ابدأ الآن', 'Start');
      onTap = () async {
        ref.read(adhkarSelectionProvider.notifier).select('evening');
        context.go('/adhkar');
      };
    } else {
      icon = Icons.auto_stories_outlined;
      title = context.tr('وردك من القرآن', 'Your Quran portion');
      body = context.tr(
        'صفحات قليلة كل يوم تبلغ بك الختم.',
        'A few pages a day take you to a full completion.',
      );
      action = context.tr('أكمل القراءة', 'Continue');
      onTap = () async {
        final page = await ref.read(lastReadPageProvider.future);
        if (!context.mounted) return;
        await _openReader(context, page);
      };
    }

    return Material(
      color: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: scheme.onPrimary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  Text(
                    action,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.chevron_left
                        : Icons.chevron_right,
                    size: 18,
                    color: scheme.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerseCard extends ConsumerWidget {
  const _VerseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final verse = ref.watch(verseOfDayProvider).value;
    final source = verse == null
        ? ''
        : context.tr(
            'سورة ${verse.surahName} · آية ${context.digits(verse.number)}',
            'Surah ${verse.surahName} · Ayah ${verse.number}',
          );

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  size: 18,
                  color: scheme.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.tr('آية اليوم', 'Verse of the day'),
                  style: theme.textTheme.labelMedium,
                ),
                const Spacer(),
                IconButton(
                  tooltip: context.tr('مشاركة', 'Share'),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  onPressed: verse == null
                      ? null
                      : () => showShareSheet(
                          context,
                          text: verse.text,
                          source: source,
                          title: context.tr('آية اليوم', 'Verse of the day'),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              verse == null ? '…' : quranFontText(verse.text),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontFamily: AppTheme.quranFont,
                fontFamilyFallback: AppTheme.quranFallback,
                height: 2.0,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(source, style: theme.textTheme.labelSmall),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadingCard extends ConsumerWidget {
  const _ReadingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lastPage = ref.watch(lastReadPageProvider).value ?? 1;
    final khatma = ref.watch(khatmaProgressProvider).value;
    final percent = khatma?.percent ?? (lastPage / 604).clamp(0.0, 1.0);

    // بطاقة الختمة تفتح جلسة ختمة على أول صفحة لم تُقرأ؛ وإلا قراءة عادية.
    Future<void> openReader() async {
      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => khatma == null
              ? MushafReaderScreen(initialPage: lastPage)
              : MushafReaderScreen(
                  initialPage: khatma.nextPage,
                  khatmaSession: true,
                ),
        ),
      );
      ref.invalidate(lastReadPageProvider);
      ref.invalidate(khatmaProgressProvider);
    }

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: percent.clamp(0.0, 1.0),
                        strokeWidth: 4,
                        backgroundColor: scheme.surfaceContainerHighest,
                        color: scheme.primary,
                      ),
                      Text(
                        context.digits('${(percent * 100).round()}%'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        khatma == null
                            ? context.tr('متابعة القراءة', 'Continue reading')
                            : context.tr('الختمة', 'Khatma'),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        khatma == null
                            ? context.tr(
                                'آخر موضع: صفحة ${context.digits(lastPage)} من ${context.digits(604)}',
                                'Last position: page $lastPage of 604',
                              )
                            : context.tr(
                                'قرأت ${context.digits(khatma.pagesRead)} صفحة · '
                                    'ورد اليوم ${context.digits(khatma.todayRemaining)} · '
                                    'متبقي ${context.digits(khatma.daysLeft)} يوماً',
                                'Read ${khatma.pagesRead} pages · '
                                    'today ${khatma.todayRemaining} · '
                                    '${khatma.daysLeft} days left',
                              ),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: openReader,
                  child: Text(context.tr('أكمل', 'Continue')),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => context.push('/khatma'),
                icon: const Icon(Icons.auto_stories_outlined, size: 16),
                label: Text(
                  khatma == null
                      ? context.tr('ابدأ ختمة مخططة', 'Start a planned khatma')
                      : context.tr('إدارة الختمة', 'Manage khatma'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
