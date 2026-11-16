import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/core/utils/arabic_digits.dart';

import '../data/tasbih_repository.dart';
import '../domain/tasbih_models.dart';
import 'tasbih_style.dart';

// TODO(مسبحة): العدّ بزر الصوت (SPEC §7.4) يحتاج استقبال مفاتيح الصوت
// في MainActivity عبر MethodChannel (لا يعترض Flutter أزرار الصوت)، وهو خارج
// نطاق هذه المرحلة — العدّ بالضغط في أي مكان يعمل الآن.

/// شاشة مسبحة — عدّادات متعددة، حلقة تقدّم، عدّ بالضغط في أي مكان،
/// وإحصاء يومي (SPEC §7.4).
class TasbihScreen extends ConsumerStatefulWidget {
  const TasbihScreen({super.key});

  @override
  ConsumerState<TasbihScreen> createState() => _TasbihScreenState();
}

class _TasbihScreenState extends ConsumerState<TasbihScreen> {
  late final TasbihRepository _repository;
  List<TasbihCounter> _counters = const <TasbihCounter>[];
  String? _activeId;
  int _tapsToday = 0;

  @override
  void initState() {
    super.initState();
    _repository = TasbihRepository(ref.read(sharedPreferencesProvider));
    _counters = _repository.loadCounters();
    _activeId = _counters.isEmpty ? null : _counters.first.id;
    _tapsToday = _repository.tapsToday();
  }

  /// العدّاد المختار حالياً (أو الأول إن فُقد الاختيار).
  TasbihCounter? get _active {
    for (final counter in _counters) {
      if (counter.id == _activeId) return counter;
    }
    return _counters.isEmpty ? null : _counters.first;
  }

  /// ضغطة تسبيح: اهتزاز خفيف لكل ضغطة، واهتزاز أقوى عند بلوغ الهدف.
  Future<void> _handleTap() async {
    final counter = _active;
    if (counter == null) return;

    final reachesTarget = counter.count + 1 >= counter.target;
    unawaited(HapticFeedback.selectionClick());
    if (reachesTarget && !counter.isCompleted) {
      unawaited(HapticFeedback.mediumImpact());
    }

    final updated = await _repository.increment(counter.id);
    if (!mounted || updated == null) return;
    setState(() {
      _counters = <TasbihCounter>[
        for (final item in _counters) item.id == updated.id ? updated : item,
      ];
      _tapsToday = _repository.tapsToday();
    });
  }

  /// تصفير العدّاد النشط — الإحصاء اليومي لا يتأثر.
  Future<void> _resetActive() async {
    final counter = _active;
    if (counter == null) return;
    final updated = await _repository.resetCounter(counter.id);
    if (!mounted || updated == null) return;
    setState(() {
      _counters = <TasbihCounter>[
        for (final item in _counters) item.id == updated.id ? updated : item,
      ];
    });
  }

  /// حوار إضافة عدّاد ([counter] فارغ) أو تعديله/حذفه.
  Future<void> _openEditor(TasbihCounter? counter) async {
    final draft = await showDialog<_CounterDraft>(
      context: context,
      builder: (context) => _CounterEditorDialog(counter: counter),
    );
    if (draft == null) return;

    if (draft.deleted) {
      final target = counter;
      if (target == null) return;
      await _repository.deleteCounter(target.id);
      if (!mounted) return;
      _syncCounters();
      return;
    }

    if (counter == null) {
      final created = await _repository.addCounter(draft.label, draft.target);
      if (!mounted) return;
      _syncCounters(preferActive: created.id);
    } else {
      await _repository.updateCounter(
        counter.copyWith(
          label: draft.label,
          target: draft.target,
          updatedAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      _syncCounters(preferActive: counter.id);
    }
  }

  /// يزامن الحالة مع المستودع بعد إضافة/تعديل/حذف.
  void _syncCounters({String? preferActive}) {
    final counters = _repository.loadCounters();
    String? next;
    if (preferActive != null && counters.any((c) => c.id == preferActive)) {
      next = preferActive;
    } else if (_activeId != null && counters.any((c) => c.id == _activeId)) {
      next = _activeId;
    } else if (counters.isNotEmpty) {
      next = counters.first.id;
    }
    setState(() {
      _counters = counters;
      _activeId = next;
      _tapsToday = _repository.tapsToday();
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('مسبحة', 'Tasbih')),
        actions: [
          IconButton(
            tooltip: ref.watch(tasbihStyleProvider) == TasbihStyle.classic
                ? context.tr('الشكل الإلكتروني', 'Digital style')
                : context.tr('الشكل الكلاسيكي', 'Classic beads'),
            icon: Icon(
              ref.watch(tasbihStyleProvider) == TasbihStyle.classic
                  ? Icons.grid_on
                  : Icons.circle_outlined,
            ),
            onPressed: () => ref.read(tasbihStyleProvider.notifier).toggle(),
          ),
          IconButton(
            onPressed: active == null ? null : () => _openEditor(active),
            icon: const Icon(Icons.edit_outlined),
            tooltip: context.tr('تعديل العدّاد', 'Edit counter'),
          ),
          IconButton(
            onPressed: () => _openEditor(null),
            icon: const Icon(Icons.add),
            tooltip: context.tr('إضافة عدّاد', 'Add counter'),
          ),
        ],
      ),
      body: SafeArea(
        child: active == null
            ? _EmptyState(onAdd: () => _openEditor(null))
            : Column(
                children: [
                  const SizedBox(height: 4),
                  _CounterChips(
                    counters: _counters,
                    activeId: active.id,
                    onSelected: (id) => setState(() => _activeId = id),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child:
                          ref.watch(tasbihStyleProvider) == TasbihStyle.classic
                          ? _ClassicCard(counter: active, onTap: _handleTap)
                          : _CounterCard(counter: active, onTap: _handleTap),
                    ),
                  ),
                  _TodayBar(
                    tapsToday: _tapsToday,
                    onReset: active.count == 0 ? null : _resetActive,
                  ),
                ],
              ),
      ),
    );
  }
}

/// شرائح اختيار العدّاد النشط (قابلة للتمرير أفقياً).
class _CounterChips extends StatelessWidget {
  const _CounterChips({
    required this.counters,
    required this.activeId,
    required this.onSelected,
  });

  final List<TasbihCounter> counters;
  final String activeId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: counters.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final counter = counters[index];
          return Center(
            child: ChoiceChip(
              label: Text(counter.label),
              selected: counter.id == activeId,
              showCheckmark: false,
              onSelected: (_) => onSelected(counter.id),
            ),
          );
        },
      ),
    );
  }
}

/// بطاقة العدّاد: كل مساحتها منطقة ضغط للتسبيح.
class _CounterCard extends StatelessWidget {
  const _CounterCard({required this.counter, required this.onTap});

  final TasbihCounter counter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = counter.isCompleted;

    return Semantics(
      button: true,
      label: 'عدّاد ${counter.label}',
      child: GestureDetector(
        key: const Key('tasbih.card'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: completed
                  ? theme.colorScheme.secondary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: completed ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final ringSize = math.max(
                112.0,
                math.min(
                  240.0,
                  math.min(
                    constraints.maxWidth - 32,
                    constraints.maxHeight - 148,
                  ),
                ),
              );
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: ringSize,
                    child: CustomPaint(
                      painter: _ProgressRingPainter(
                        progress: counter.progress,
                        color: theme.colorScheme.primary,
                        trackColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.55),
                      ),
                      child: Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ringSize * 0.09,
                            vertical: ringSize * 0.05,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.digits(counter.count),
                                style: TextStyle(
                                  fontSize: ringSize * 0.22,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.5,
                                  color: theme.colorScheme.primary,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                context.tr(
                                  'من ${context.digits(counter.target)}',
                                  'of ${counter.target}',
                                ),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      counter.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontFamily: AppTheme.displayFont,
                        fontSize: 28,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    completed
                        ? context.tr(
                            'بلغت الهدف — تقبّل الله',
                            'Target reached — may Allah accept it',
                          )
                        : context.tr(
                            'اضغط في أي مكان للتسبيح',
                            'Tap anywhere to count',
                          ),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (completed)
                    const _CompletedBadge()
                  else
                    const SizedBox(height: 32),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// البطاقة الكلاسيكية: حلقة من حبات المسبحة (٣٣ حبة) تمتلئ مع العدّ.
class _ClassicCard extends StatelessWidget {
  const _ClassicCard({required this.counter, required this.onTap});

  final TasbihCounter counter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = counter.isCompleted;

    return Semantics(
      button: true,
      label: 'مسبحة ${counter.label}',
      child: GestureDetector(
        key: const Key('tasbih.card'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: completed
                  ? theme.colorScheme.secondary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: completed ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final ringSize = math.max(
                140.0,
                math.min(
                  420.0,
                  math.min(
                    constraints.maxWidth - 24,
                    constraints.maxHeight - 140,
                  ),
                ),
              );
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: ringSize,
                    child: CustomPaint(
                      painter: _BeadsPainter(
                        progress: counter.progress,
                        beadColor: Theme.of(context).colorScheme.secondary,
                        pendingColor: Theme.of(context)
                            .colorScheme
                            .outlineVariant,
                        doneColor: theme.colorScheme.primary,
                        stringColor: Theme.of(context).colorScheme.secondary
                            .withValues(alpha: 0.45),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.digits(counter.count),
                              style: TextStyle(
                                fontSize: ringSize * 0.24,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              context.tr(
                                'من ${context.digits(counter.target)}',
                                'of ${counter.target}',
                              ),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    counter.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontFamily: AppTheme.displayFont,
                      fontSize: 26,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    completed
                        ? context.tr(
                            'بلغت الهدف — تقبّل الله',
                            'Target reached — may Allah accept it',
                          )
                        : context.tr(
                            'اضغط في أي مكان للتسبيح',
                            'Tap anywhere to count',
                          ),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (completed)
                    const _CompletedBadge()
                  else
                    const SizedBox(height: 32),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// رسم حلقة الحبات: ٣٣ حبة على محيط دائرة، المكتملة بلون، والباقي باهت.
class _BeadsPainter extends CustomPainter {
  const _BeadsPainter({
    required this.progress,
    required this.beadColor,
    required this.pendingColor,
    required this.doneColor,
    required this.stringColor,
  });

  final double progress;
  final Color beadColor;
  final Color pendingColor;
  final Color doneColor;
  final Color stringColor;

  static const int beads = 33;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final beadRadius = radius * 0.062;

    // خيط المسبحة.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = stringColor,
    );

    final filled = (progress.clamp(0.0, 1.0) * beads).floor();
    for (var index = 0; index < beads; index++) {
      final angle = -math.pi / 2 + index * 2 * math.pi / beads;
      final position = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final isDone = index < filled;
      canvas.drawCircle(
        position,
        beadRadius,
        Paint()
          ..color = isDone ? doneColor : pendingColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        position,
        beadRadius,
        Paint()
          ..color = beadColor.withValues(alpha: isDone ? 0.9 : 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
      // لمعة صغيرة أعلى الحبة.
      canvas.drawCircle(
        position.translate(-beadRadius * 0.3, -beadRadius * 0.3),
        beadRadius * 0.22,
        Paint()..color = Colors.white.withValues(alpha: isDone ? 0.35 : 0.18),
      );
    }

    // حبة الإمام أعلى الحلقة (أكبر قليلاً).
    final imam = Offset(center.dx, center.dy - radius);
    canvas.drawCircle(imam, beadRadius * 1.5, Paint()..color = beadColor);
    canvas.drawCircle(
      imam,
      beadRadius * 0.7,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(_BeadsPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      beadColor != oldDelegate.beadColor ||
      pendingColor != oldDelegate.pendingColor ||
      doneColor != oldDelegate.doneColor;
}

/// شارة «اكتمل» عند بلوغ الهدف — بلا تصفير تلقائي.
class _CompletedBadge extends StatelessWidget {
  const _CompletedBadge();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            context.tr('اكتمل', 'Done'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// شريط إحصاء اليوم + زر التصفير.
class _TodayBar extends StatelessWidget {
  const _TodayBar({required this.tapsToday, required this.onReset});

  final int tapsToday;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        children: [
          Icon(
            Icons.today_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr(
                'اليوم: ${context.digits(tapsToday)} تسبيحة',
                'Today: $tapsToday tasbihs',
              ),
              style: theme.textTheme.titleSmall,
            ),
          ),
          TextButton.icon(
            key: const Key('tasbih.reset'),
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: Text(context.tr('تصفير', 'Reset')),
          ),
        ],
      ),
    );
  }
}

/// حالة عدم وجود أي عدّاد.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.radio_button_unchecked,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('لا توجد عدّادات بعد', 'No counters yet'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(context.tr('إضافة عدّاد', 'Add counter')),
          ),
        ],
      ),
    );
  }
}

/// حلقة التقدّم: مسار خلفي + قوس يمثّل نسبة الإنجاز.
class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * 0.065;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

/// نتيجة حوار التعديل: حفظ (label/target) أو حذف.
class _CounterDraft {
  const _CounterDraft.save({required this.label, required this.target})
    : deleted = false;

  const _CounterDraft.deleted() : label = '', target = 0, deleted = true;

  final String label;
  final int target;
  final bool deleted;
}

/// حوار إضافة عدّاد أو تعديله مع حذف بتأكيد.
class _CounterEditorDialog extends StatefulWidget {
  const _CounterEditorDialog({this.counter});

  final TasbihCounter? counter;

  @override
  State<_CounterEditorDialog> createState() => _CounterEditorDialogState();
}

class _CounterEditorDialogState extends State<_CounterEditorDialog> {
  static const List<int> _presets = <int>[33, 100];

  late final TextEditingController _labelController;
  late final TextEditingController _targetController;
  int _preset = 33;
  String? _labelError;
  String? _targetError;

  bool get _isEditing => widget.counter != null;
  bool get _isCustom => _preset == 0;

  @override
  void initState() {
    super.initState();
    final counter = widget.counter;
    _labelController = TextEditingController(text: counter?.label ?? '');
    final target = counter?.target ?? 33;
    _preset = _presets.contains(target) ? target : 0;
    _targetController = TextEditingController(text: '$target');
  }

  @override
  void dispose() {
    _labelController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _labelController.text.trim();
    final target = _isCustom
        ? int.tryParse(toArabicDigits(_targetController.text.trim()))
        : _preset;
    final labelError = label.isEmpty
        ? context.tr('أدخل نص الذكر', 'Enter the dhikr text')
        : null;
    final targetError = target == null || target < 1
        ? context.tr(
            'أدخل هدفاً أكبر من صفر',
            'Enter a target greater than zero',
          )
        : null;
    setState(() {
      _labelError = labelError;
      _targetError = targetError;
    });
    if (labelError != null || targetError != null || target == null) return;
    Navigator.of(context).pop(_CounterDraft.save(label: label, target: target));
  }

  Future<void> _confirmDelete() async {
    final counter = widget.counter;
    if (counter == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('حذف العدّاد', 'Delete counter')),
        content: Text(
          'سيُحذف «${counter.label}» مع عدّه الحالي. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.tr('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(const _CounterDraft.deleted());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        _isEditing
            ? context.tr('تعديل العدّاد', 'Edit counter')
            : context.tr('إضافة عدّاد', 'Add counter'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('tasbih.label'),
              controller: _labelController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.tr('نص الذكر', 'Dhikr text'),
                errorText: _labelError,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.tr('الهدف', 'Target'),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _presets)
                  ChoiceChip(
                    label: Text(toHindiDigits('$preset')),
                    selected: _preset == preset,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      _preset = preset;
                      _targetError = null;
                    }),
                  ),
                ChoiceChip(
                  label: Text(context.tr('مخصص', 'Custom')),
                  selected: _isCustom,
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    _preset = 0;
                    _targetError = null;
                  }),
                ),
              ],
            ),
            if (_isCustom) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('tasbih.customTarget'),
                controller: _targetController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: context.tr('هدف مخصص', 'Custom target'),
                  errorText: _targetError,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_isEditing)
          TextButton(
            key: const Key('tasbih.delete'),
            onPressed: _confirmDelete,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: Text(context.tr('حذف', 'Delete')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('إلغاء', 'Cancel')),
        ),
        FilledButton(
          key: const Key('tasbih.save'),
          onPressed: _submit,
          child: Text(context.tr('حفظ', 'Save')),
        ),
      ],
    );
  }
}
