import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';

import '../../quran/presentation/mushaf_reader_screen.dart';
import '../../quran/presentation/quran_providers.dart';
import '../domain/khatma_plan.dart';
import 'khatma_providers.dart';

/// الختمة المخططة (SPEC §7.3): «أختم في N يوم» مع ورد يومي يُعاد توزيعه.
///
/// التقدّم من الصفحات المقروءة فعلاً (المكوث على الصفحة في المصحف، أو
/// «قرأت ورد اليوم»)، لا من آخر صفحة فُتحت.
class KhatmaScreen extends ConsumerStatefulWidget {
  const KhatmaScreen({super.key});

  @override
  ConsumerState<KhatmaScreen> createState() => _KhatmaScreenState();
}

class _KhatmaScreenState extends ConsumerState<KhatmaScreen> {
  static const _presets = <int>[7, 30, 60, 90, 180, 365];
  int _days = 30;
  bool _fromBeginning = true;

  Future<void> _start() async {
    final notifier = ref.read(khatmaPlanProvider.notifier);
    if (_fromBeginning) {
      await notifier.restartFromBeginning(days: _days);
    } else {
      await notifier.start(days: _days);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'بدأت ختمة ${context.digits(_days)} يوماً',
            'Started a $_days-day khatma',
          ),
        ),
      ),
    );
  }

  Future<void> _continueReading(int page) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MushafReaderScreen(initialPage: page, khatmaSession: true),
      ),
    );
    ref.invalidate(lastReadPageProvider);
  }

  Future<void> _markToday(KhatmaPlan plan, KhatmaProgress progress) async {
    final pages = nextUnreadPages(
      plan: plan,
      readPages: ref.read(khatmaReadProvider).all,
      count: progress.todayRemaining,
    );
    await ref.read(khatmaReadProvider.notifier).mark(pages);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'سُجّلت ${context.digits(pages.length)} صفحة — بارك الله فيك',
            'Recorded ${pages.length} pages — may Allah bless you',
          ),
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('إنهاء الختمة؟', 'End this khatma?')),
        content: Text(
          context.tr(
            'سيُحذف تقدّم الخطة.',
            'The plan progress will be removed.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('إنهاء', 'End')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(khatmaPlanProvider.notifier).cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(khatmaPlanProvider);
    final progressAsync = ref.watch(khatmaProgressProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('الختمة', 'Khatma'))),
      body: plan == null
          ? _SetupView(
              days: _days,
              fromBeginning: _fromBeginning,
              presets: _presets,
              onDays: (value) => setState(() => _days = value),
              onFromBeginning: (value) =>
                  setState(() => _fromBeginning = value),
              onStart: _start,
            )
          : progressAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('$error')),
              data: (progress) {
                if (progress == null) return const SizedBox.shrink();
                return _PlanView(
                  progress: progress,
                  onContinue: () => _continueReading(progress.nextPage),
                  onMarkToday: progress.todayRemaining > 0
                      ? () => _markToday(plan, progress)
                      : null,
                  onCancel: _cancel,
                );
              },
            ),
    );
  }
}

class _SetupView extends StatelessWidget {
  const _SetupView({
    required this.days,
    required this.fromBeginning,
    required this.presets,
    required this.onDays,
    required this.onFromBeginning,
    required this.onStart,
  });

  final int days;
  final bool fromBeginning;
  final List<int> presets;
  final ValueChanged<int> onDays;
  final ValueChanged<bool> onFromBeginning;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perDay = (604 / days).ceil();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.tr('أختم في كم يوم؟', 'Complete the Quran in how many days?'),
          style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'Amiri'),
        ),
        const SizedBox(height: 6),
        Text(
          context.tr(
            'نوزّع صفحات المصحف على الأيام، ونعيد التوزيع تلقائياً إذا فاتك يوم. '
                'تُحسب الصفحة مقروءة حين تمكث عليها في المصحف.',
            'We split the pages over the days and rebalance if you miss a day. '
                'A page counts as read when you stay on it in the reader.',
          ),
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in presets)
              ChoiceChip(
                label: Text(
                  context.tr('${context.digits(preset)} يوماً', '$preset days'),
                ),
                selected: days == preset,
                onSelected: (_) => onDays(preset),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('مخصص (٧–٦٠٠ يوم)', 'Custom (7–600 days)'),
                style: theme.textTheme.labelSmall,
              ),
            ),
            IconButton(
              onPressed: days > 7 ? () => onDays(days - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 56,
              child: Text(
                context.digits(days),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
            ),
            IconButton(
              onPressed: days < 600 ? () => onDays(days + 1) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        Text(
          context.tr(
            'حوالي ${context.digits(perDay)} صفحة يومياً',
            'About $perDay pages a day',
          ),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('ابدأ من الفاتحة', 'Start from Al-Fatiha')),
          subtitle: Text(
            context.tr(
              'وإلا نبدأ من آخر صفحة وصلت إليها',
              'Otherwise start from your last page',
            ),
          ),
          value: fromBeginning,
          onChanged: onFromBeginning,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.auto_stories_outlined),
          label: Text(
            context.tr(
              'ابدأ ختمة ${context.digits(days)} يوماً',
              'Start a $days-day khatma',
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanView extends StatelessWidget {
  const _PlanView({
    required this.progress,
    required this.onContinue,
    required this.onMarkToday,
    required this.onCancel,
  });

  final KhatmaProgress progress;
  final VoidCallback onContinue;
  final VoidCallback? onMarkToday;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final todayDone = progress.todayRemaining == 0;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CircularProgressIndicator(
                    value: progress.percent.clamp(0.0, 1.0),
                    strokeWidth: 9,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: scheme.primary,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.digits('${(progress.percent * 100).round()}%'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      context.tr('من الختمة', 'complete'),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          context.tr(
            'قرأت ${context.digits(progress.pagesRead)} صفحة من ${context.digits(progress.totalPages)}',
            'Read ${progress.pagesRead} of ${progress.totalPages} pages',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          progress.finished
              ? context.tr(
                  'أتممت الختمة — تقبّل الله',
                  'Khatma complete — may Allah accept it',
                )
              : context.tr(
                  'ورد اليوم: ${context.digits(progress.todayRead)} / ${context.digits(progress.todayTarget)} صفحة · '
                      'متبقي ${context.digits(progress.daysLeft)} يوماً',
                  'Today: ${progress.todayRead} / ${progress.todayTarget} pages · '
                      '${progress.daysLeft} days left',
                ),
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(color: scheme.secondary),
        ),
        if (!progress.finished) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress.todayTarget == 0
                ? 1
                : (progress.todayRead / progress.todayTarget).clamp(0.0, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: progress.finished ? null : onContinue,
          icon: const Icon(Icons.menu_book_outlined),
          label: Text(
            context.tr(
              'أكمل من صفحة ${context.digits(progress.nextPage)}',
              'Continue from page ${progress.nextPage}',
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: onMarkToday,
          icon: Icon(todayDone ? Icons.check_circle : Icons.done_all),
          label: Text(
            todayDone
                ? context.tr('أتممت ورد اليوم', 'Today\'s portion done')
                : context.tr(
                    'قرأت ورد اليوم (${context.digits(progress.todayRemaining)} صفحة)',
                    'I read today\'s portion (${progress.todayRemaining} pages)',
                  ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close, size: 18),
          label: Text(context.tr('إنهاء الخطة', 'End plan')),
        ),
      ],
    );
  }
}
