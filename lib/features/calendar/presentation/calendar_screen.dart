import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hijri/hijri_calendar.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:yousuf/core/time/clock_providers.dart';
import 'package:yousuf/core/utils/arabic_dates.dart';

import '../../prayer/domain/prayer_times_models.dart';
import '../../prayer/presentation/prayer_providers.dart';
import '../domain/islamic_occasions.dart';

/// التقويم (SPEC §7.7): شهر هجري أو ميلادي، كل يوم بتاريخيه، مع المناسبات
/// والأيام البيض وصيام الإثنين والخميس، وتفاصيل اليوم ومواقيته عند الضغط.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

enum _Mode { hijri, gregorian }

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  _Mode _mode = _Mode.hijri;

  /// إزاحة الشهر المعروض عن الشهر الحالي.
  int _monthOffset = 0;

  int get _hijriOffset =>
      ref.read(prayerSettingsProvider).value?.hijriOffsetDays ?? 0;

  /// أيام الشهر المعروض (ميلادية) ومعلومات عرضه.
  ({List<DateTime> days, String title}) _monthDays(
    BuildContext context,
    DateTime today,
  ) {
    if (_mode == _Mode.gregorian) {
      final first = DateTime(today.year, today.month + _monthOffset, 1);
      final count = DateTime(first.year, first.month + 1, 0).day;
      return (
        days: [
          for (var d = 0; d < count; d++)
            DateTime(first.year, first.month, 1 + d),
        ],
        title:
            '${context.monthName(first.month)} ${context.digits(first.year)}',
      );
    }
    // الشهر الهجري: نبدأ من شهر اليوم الهجري ثم نتحرّك بالإزاحة.
    final todayHijri = hijriDay(today, offsetDays: _hijriOffset);
    if (todayHijri == null) return (days: const [], title: '');
    var year = todayHijri.year;
    var month = todayHijri.month + _monthOffset;
    while (month > 12) {
      month -= 12;
      year++;
    }
    while (month < 1) {
      month += 12;
      year--;
    }
    final calendar = HijriCalendar();
    try {
      final length = calendar.getDaysInMonth(year, month);
      // التحويل بأم القرى ثم عكس إزاحة المستخدم.
      final start = calendar.hijriToGregorian(year, month, 1);
      final first = DateTime(start.year, start.month, start.day - _hijriOffset);
      return (
        days: [
          for (var d = 0; d < length; d++)
            DateTime(first.year, first.month, first.day + d),
        ],
        title: context.isArabic
            ? '${context.hijriMonthName(month)} ${context.digits(year)}هـ'
            : '${context.hijriMonthName(month)} $year AH',
      );
    } catch (_) {
      return (days: const [], title: '');
    }
  }

  void _showDay(DateTime day) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _DaySheet(day: day, hijriOffset: _hijriOffset),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    ref.watch(prayerSettingsProvider);
    final theme = Theme.of(context);
    final month = _monthDays(context, today);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('التقويم', 'Calendar'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          SegmentedButton<_Mode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _Mode.hijri,
                label: Text(context.tr('هجري', 'Hijri')),
              ),
              ButtonSegment(
                value: _Mode.gregorian,
                label: Text(context.tr('ميلادي', 'Gregorian')),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (value) => setState(() {
              _mode = value.first;
              _monthOffset = 0;
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: context.tr('الشهر السابق', 'Previous month'),
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() => _monthOffset--),
              ),
              Expanded(
                child: Text(
                  month.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'Amiri',
                  ),
                ),
              ),
              IconButton(
                tooltip: context.tr('الشهر التالي', 'Next month'),
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _monthOffset++),
              ),
            ],
          ),
          if (_monthOffset != 0)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _monthOffset = 0),
                child: Text(context.tr('الشهر الحالي', 'This month')),
              ),
            ),
          _MonthGrid(
            days: month.days,
            today: today,
            mode: _mode,
            hijriOffset: _hijriOffset,
            onTap: _showDay,
          ),
          const SizedBox(height: 12),
          const _Legend(),
          const SizedBox(height: 16),
          _UpcomingOccasions(today: today, hijriOffset: _hijriOffset),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.days,
    required this.today,
    required this.mode,
    required this.hijriOffset,
    required this.onTap,
  });

  final List<DateTime> days;
  final DateTime today;
  final _Mode mode;
  final int hijriOffset;
  final ValueChanged<DateTime> onTap;

  /// الأسبوع يبدأ السبت (العُرف العربي).
  static const _weekStart = DateTime.saturday;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final leading = (days.first.weekday - _weekStart + 7) % 7;
    final headers = [
      for (var i = 0; i < 7; i++)
        context.weekdayName(DateTime(2024, 1, 6 + i)), // ٦ يناير ٢٠٢٤ سبت
    ];

    return Column(
      children: [
        Row(
          children: [
            for (final header in headers)
              Expanded(
                child: Center(
                  child: Text(
                    context.isArabic ? header : header.substring(0, 3),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.78,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: [
            for (var i = 0; i < leading; i++) const SizedBox.shrink(),
            for (final day in days)
              _DayCell(
                day: day,
                isToday: day == today,
                mode: mode,
                hijri: hijriDay(day, offsetDays: hijriOffset),
                onTap: () => onTap(day),
              ),
          ],
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.mode,
    required this.hijri,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final _Mode mode;
  final HijriDay? hijri;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final occasions = hijri == null
        ? const <IslamicOccasion>[]
        : occasionsOn(hijri!.month, hijri!.day);
    final feast = occasions.any((o) => o.kind == OccasionKind.feast);
    final fasting =
        occasions.any((o) => o.kind == OccasionKind.fasting) ||
        (hijri?.isWhiteDay ?? false);
    final season = occasions.any((o) => o.kind == OccasionKind.season);
    final friday = isFriday(day);

    final primary = mode == _Mode.hijri ? (hijri?.day ?? day.day) : day.day;
    final secondary = mode == _Mode.hijri ? day.day : hijri?.day;

    Color? background;
    Color foreground = scheme.onSurface;
    if (isToday) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
    } else if (feast) {
      background = scheme.tertiaryContainer;
      foreground = scheme.onTertiaryContainer;
    } else if (friday) {
      background = scheme.surfaceContainerHigh;
    }

    return Material(
      color: background ?? scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                context.digits(primary),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (secondary != null)
                Text(
                  context.digits(secondary),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: foreground.withValues(alpha: 0.7),
                    fontSize: 9,
                  ),
                ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fasting)
                    _Dot(color: isToday ? scheme.onPrimary : scheme.secondary),
                  if (season)
                    _Dot(color: isToday ? scheme.onPrimary : scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 5,
    height: 5,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall;
    Widget item(Widget mark, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 4),
        Text(label, style: style),
      ],
    );
    Widget box(Color color) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        item(box(scheme.tertiaryContainer), context.tr('عيد', 'Eid')),
        item(
          _Dot(color: scheme.secondary),
          context.tr('صيام مستحب', 'Recommended fast'),
        ),
        item(
          _Dot(color: scheme.primary),
          context.tr('موسم عبادة', 'Season of worship'),
        ),
        item(box(scheme.surfaceContainerHigh), context.tr('الجمعة', 'Friday')),
      ],
    );
  }
}

class _UpcomingOccasions extends StatelessWidget {
  const _UpcomingOccasions({required this.today, required this.hijriOffset});

  final DateTime today;
  final int hijriOffset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final arabic = context.isArabic;
    final upcoming = <(DateTime, IslamicOccasion)>[];
    for (var d = 0; d <= 370 && upcoming.length < 6; d++) {
      final day = DateTime(today.year, today.month, today.day + d);
      final hijri = hijriDay(day, offsetDays: hijriOffset);
      if (hijri == null) continue;
      for (final occasion in occasionsOn(hijri.month, hijri.day)) {
        final duplicate = upcoming.any((e) => e.$2.titleAr == occasion.titleAr);
        if (!duplicate) upcoming.add((day, occasion));
      }
    }

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                context.tr('المناسبات القادمة', 'Upcoming occasions'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final (day, occasion) in upcoming)
              ListTile(
                dense: true,
                leading: Icon(switch (occasion.kind) {
                  OccasionKind.feast => Icons.celebration_outlined,
                  OccasionKind.fasting => Icons.nightlight_outlined,
                  OccasionKind.season => Icons.star_outline,
                }, color: scheme.primary),
                title: Text(occasion.title(arabic: arabic)),
                subtitle: Text(context.formatDate(day)),
                trailing: Text(
                  _daysLeft(context, day.difference(today).inDays),
                  style: theme.textTheme.labelSmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                context.tr(
                  'التواريخ بتقويم أم القرى مع إزاحتك — العبرة برؤية الهلال في بلدك.',
                  'Dates follow Umm al-Qura with your offset — local moon sighting prevails.',
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _daysLeft(BuildContext context, int days) {
    if (days == 0) return context.tr('اليوم', 'Today');
    if (days == 1) return context.tr('غداً', 'Tomorrow');
    return context.tr('بعد ${context.digits(days)} يوم', 'in $days days');
  }
}

class _DaySheet extends ConsumerWidget {
  const _DaySheet({required this.day, required this.hijriOffset});

  final DateTime day;
  final int hijriOffset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final arabic = context.isArabic;
    final hijri = hijriDay(day, offsetDays: hijriOffset);
    final settings = ref.watch(prayerSettingsProvider).value;
    final times = settings == null ? null : timesFor(settings, day);
    final occasions = hijri == null
        ? const <IslamicOccasion>[]
        : occasionsOn(hijri.month, hijri.day);
    final notes = <String>[
      for (final o in occasions)
        o.note(arabic: arabic) == null
            ? o.title(arabic: arabic)
            : '${o.title(arabic: arabic)} — ${o.note(arabic: arabic)}',
      if (hijri?.isWhiteDay ?? false)
        context.tr(
          'من الأيام البيض — يُستحب صيامها',
          'One of the White Days — recommended fast',
        ),
      if (day.weekday == DateTime.monday || day.weekday == DateTime.thursday)
        context.tr(
          'يُستحب صيام الإثنين والخميس',
          'Fasting Mondays and Thursdays is recommended',
        ),
      if (isFriday(day))
        context.tr(
          'يوم الجمعة — سورة الكهف والإكثار من الصلاة على النبي ﷺ',
          'Friday — Surah Al-Kahf and abundant salawat',
        ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.formatDate(day), style: theme.textTheme.titleMedium),
            if (hijri != null)
              Text(
                context.formatHijri(hijri),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontFamily: 'Amiri',
                ),
              ),
            const SizedBox(height: 12),
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 8, color: scheme.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(note, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            if (times != null) ...[
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final prayer in PrayerName.values)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${prayer.label(arabic: arabic)} ${context.formatTime(times.timeFor(prayer))}',
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
