import 'package:flutter/material.dart';
import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/core/utils/quran_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:yousuf/l10n/generated/app_localizations.dart';

import '../domain/adhkar_models.dart';
import '../domain/user_dhikr.dart';
import 'adhkar_editor.dart';
import 'adhkar_providers.dart';

/// شاشة الأذكار — م1 (SPEC §7.4): أقسام حصن المسلم، بطاقة الذكر بعدّاد،
/// وأذكار يضيفها المستخدم بنفسه.
///
/// نصوص الأذكار تبقى عربية في الواجهتين؛ ما حولها يُترجم.
class AdhkarScreen extends ConsumerStatefulWidget {
  const AdhkarScreen({super.key});

  @override
  ConsumerState<AdhkarScreen> createState() => _AdhkarScreenState();
}

class _AdhkarScreenState extends ConsumerState<AdhkarScreen> {
  final TextEditingController _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addDhikr() async {
    final created = await showDialog<UserDhikr>(
      context: context,
      builder: (_) => const DhikrEditorDialog(),
    );
    if (created == null) return;
    await ref.read(userAdhkarProvider.notifier).add(created);
    ref
        .read(adhkarSelectionProvider.notifier)
        .select(AdhkarSelection.userSource);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            'أُضيف إلى «أذكاري» — يمكنك تعديله أو حذفه',
            'Added to “My adhkar” — you can edit or delete it',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final categoriesAsync = ref.watch(adhkarCategoriesProvider);
    final selection = ref.watch(adhkarSelectionProvider);
    final progress = ref.watch(adhkarProgressProvider);
    final reviewedBy = ref.watch(contentReviewedByProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabAdhkar),
        actions: [
          IconButton(
            tooltip: context.tr('إضافة ذكر', 'Add dhikr'),
            icon: const Icon(Icons.add),
            onPressed: _addDhikr,
          ),
          IconButton(
            tooltip: context.tr(
              'تصفير عدّادات اليوم',
              'Reset today\'s counters',
            ),
            icon: const Icon(Icons.restart_alt),
            onPressed: progress.isEmpty
                ? null
                : () => ref.read(adhkarProgressProvider.notifier).resetAll(),
          ),
        ],
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (categories) {
          if (categories.isEmpty) return const _PendingContent();
          final featured =
              ref.watch(featuredAdhkarCategoriesProvider).value ??
              const <DhikrCategory>[];
          return Column(
            children: [
              if (reviewedBy == null) const _ReviewBanner(),
              _ChipsRow(
                featured: featured,
                selection: selection,
                onSelect: (value) =>
                    ref.read(adhkarSelectionProvider.notifier).select(value),
              ),
              Expanded(
                child: switch (selection) {
                  AdhkarSelection.allSources => _ChaptersBrowser(
                    categories: categories,
                    search: _search,
                    searching: _searching,
                    onSearching: (value) => setState(() => _searching = value),
                  ),
                  AdhkarSelection.userSource => const _UserDhikrList(),
                  _ => _ChapterView(slug: selection, categories: categories),
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// تنبيه أن المحتوى لم يُعتمد بعد (reviewed_by فارغ).
class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.verified_outlined,
            size: 16,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr(
                'المحتوى منقول من «حصن المسلم» — قيد المراجعة الشرعية.',
                'Content from Hisn al-Muslim — under scholarly review.',
              ),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipsRow extends StatelessWidget {
  const _ChipsRow({
    required this.featured,
    required this.selection,
    required this.onSelect,
  });

  final List<DhikrCategory> featured;
  final String selection;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            _chip(
              context,
              label: context.tr('أذكاري', 'My adhkar'),
              value: AdhkarSelection.userSource,
              icon: Icons.person_outline,
            ),
            const SizedBox(width: 8),
            for (final category in featured) ...[
              _chip(context, label: category.nameAr, value: category.slug),
              const SizedBox(width: 8),
            ],
            _chip(
              context,
              label: context.tr('كل الأقسام', 'All sections'),
              value: AdhkarSelection.allSources,
              icon: Icons.list_alt,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required String value,
    IconData? icon,
  }) {
    return ChoiceChip(
      avatar: icon == null ? null : Icon(icon, size: 16),
      label: Text(label),
      selected: selection == value,
      onSelected: (_) => onSelect(value),
    );
  }
}

/// صفحة قسم: قائمة أذكار الباب.
class _ChapterView extends ConsumerWidget {
  const _ChapterView({required this.slug, required this.categories});

  final String slug;
  final List<DhikrCategory> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // قواعد قديمة بلا باب «المساء» المنفصل تعود لباب الصباح.
    final wanted =
        slug == 'evening' && !categories.any((item) => item.slug == 'evening')
        ? 'morning'
        : slug;
    final category = categories.firstWhere(
      (item) => item.slug == wanted,
      orElse: () => categories.firstWhere(
        (item) => item.slug == 'quranic',
        orElse: () => categories.first,
      ),
    );
    final dhikrAsync = ref.watch(adhkarOfCategoryProvider(category.id));
    return dhikrAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Text(
              context.tr(
                'لا توجد أذكار في هذا القسم بعد',
                'No adhkar in this section yet',
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: list.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  category.nameAr,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontFamily: 'Amiri'),
                ),
              );
            }
            final dhikr = list[index - 1];
            return DhikrCard(
              text: dhikr.text,
              repeat: dhikr.repeatCount,
              source: dhikr.source,
              virtue: dhikr.virtue,
              instruction: dhikr.instruction,
              progressKey: dhikrProgressKey(dhikr.id),
            );
          },
        );
      },
    );
  }
}

/// فهرس كل الأبواب مع بحث.
class _ChaptersBrowser extends ConsumerWidget {
  const _ChaptersBrowser({
    required this.categories,
    required this.search,
    required this.searching,
    required this.onSearching,
  });

  final List<DhikrCategory> categories;
  final TextEditingController search;
  final bool searching;
  final ValueChanged<bool> onSearching;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(adhkarCategoryCountsProvider).value ?? const {};
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: search,
            onTap: () => onSearching(true),
            decoration: InputDecoration(
              hintText: context.tr(
                'ابحث عن باب… (مثال: النوم، السفر)',
                'Search a section (Arabic, e.g. النوم)',
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        search.clear();
                        onSearching(false);
                      },
                    )
                  : null,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: search,
            builder: (context, value, _) {
              final query = _normalize(value.text);
              final filtered = query.isEmpty
                  ? categories
                  : categories
                        .where(
                          (item) => _normalize(item.nameAr).contains(query),
                        )
                        .toList(growable: false);
              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    context.tr('لا يوجد باب بهذا الاسم', 'No matching section'),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final category = filtered[index];
                  final total = counts[category.id] ?? 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(category.nameAr),
                    subtitle: Text(
                      total == 0
                          ? context.tr('لا أذكار بعد', 'No adhkar yet')
                          : context.tr(
                              '${context.digits(total)} ذكراً',
                              '$total adhkar',
                            ),
                    ),
                    trailing: const Icon(Icons.chevron_left, size: 18),
                    onTap: () => ref
                        .read(adhkarSelectionProvider.notifier)
                        .select(category.slug),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  static String _normalize(String input) {
    const diacritics = 'ؐ-ًؚ-ٰٟۖ-ۭ';
    return input
        .replaceAll(RegExp('[$diacritics]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .trim();
  }
}

/// أذكار المستخدم: إضافة وتعديل وحذف.
class _UserDhikrList extends ConsumerWidget {
  const _UserDhikrList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(userAdhkarProvider);
    if (items.isEmpty) return const _UserEmptyState();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return DhikrCard(
          text: item.text,
          repeat: item.repeat,
          source: item.source,
          progressKey: userDhikrProgressKey(item.id),
          badge: context.tr('مضاف منك', 'Yours'),
          onEdit: () => _edit(context, ref, item),
          onDelete: () => _delete(context, ref, item),
        );
      },
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    UserDhikr item,
  ) async {
    final updated = await showDialog<UserDhikr>(
      context: context,
      builder: (_) => DhikrEditorDialog(existing: item),
    );
    if (updated == null) return;
    await ref.read(userAdhkarProvider.notifier).update(updated);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    UserDhikr item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('حذف الذكر؟', 'Delete this dhikr?')),
        content: Text(
          context.tr(
            'سيُحذف هذا الذكر من جهازك نهائياً.',
            'It will be permanently removed from your device.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(userAdhkarProvider.notifier).remove(item.id);
  }
}

class _UserEmptyState extends ConsumerWidget {
  const _UserEmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.edit_note, size: 44, color: theme.colorScheme.secondary),
            const SizedBox(height: 12),
            Text(
              context.tr('أذكارك الخاصة', 'Your own adhkar'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'أضف أي ذكر أو دعاء تحفظه، فيصبح بطاقة بعدّاد مثل بقية الأذكار — ويبقى على جهازك فقط.',
                'Add any dhikr or dua; it becomes a counter card like the others and stays on your device.',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.7),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final created = await showDialog<UserDhikr>(
                  context: context,
                  builder: (_) => const DhikrEditorDialog(),
                );
                if (created == null) return;
                await ref.read(userAdhkarProvider.notifier).add(created);
              },
              icon: const Icon(Icons.add),
              label: Text(context.tr('أضف ذكراً', 'Add dhikr')),
            ),
          ],
        ),
      ),
    );
  }
}

/// سطر بسملة مستقل (بداية سورة داخل ذكر قرآني).
bool _isBasmalaLine(String line) =>
    line.startsWith('بِسْمِ ٱللَّهِ') && line.trim().length < 45;

/// بطاقة ذكر واحدة: نص + تعليمة + مصدر + عدّاد تقدّم.
class DhikrCard extends ConsumerWidget {
  const DhikrCard({
    super.key,
    required this.text,
    required this.repeat,
    required this.progressKey,
    this.source,
    this.virtue,
    this.instruction,
    this.badge,
    this.onEdit,
    this.onDelete,
  });

  final String text;
  final int repeat;
  final String progressKey;
  final String? source;
  final String? virtue;

  /// تعليمة المصدر («ثلاث مرات»، «إذا أصبح»…) — تُعرض منفصلة عن النص.
  final String? instruction;
  final String? badge;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = ref.watch(adhkarProgressProvider)[progressKey] ?? 0;
    final complete = count >= repeat;
    final progress = repeat == 0 ? 0.0 : count / repeat;

    Widget pill(String label, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: complete ? scheme.primary : scheme.outlineVariant,
          width: complete ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (complete) return;
          HapticFeedback.selectionClick();
          ref
              .read(adhkarProgressProvider.notifier)
              .incrementKey(progressKey, repeat);
          if (count + 1 >= repeat) HapticFeedback.mediumImpact();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (badge != null) ...[
                    pill(
                      badge!,
                      scheme.tertiaryContainer,
                      scheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 6),
                  ],
                  pill(
                    repeat <= 1
                        ? context.tr('مرة واحدة', 'Once')
                        : '×${context.digits(repeat)}',
                    scheme.primaryContainer,
                    scheme.onPrimaryContainer,
                  ),
                  const Spacer(),
                  if (onEdit != null)
                    IconButton(
                      tooltip: context.tr('تعديل', 'Edit'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: onEdit,
                    ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: context.tr('حذف', 'Delete'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: onDelete,
                    ),
                  if (complete)
                    Icon(Icons.check_circle, color: scheme.primary, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              // النص القرآني بنص المصحف نفسه: علامات الوقف ملتصقة بالكلمة،
              // والبسملة في سطر وحدها في المنتصف كالمصحف.
              for (final line in withMushafAyahMarks(
                quranFontText(displayQuranText(text)),
              ).split('\n'))
                if (line.trim().isEmpty)
                  const SizedBox(height: 8)
                else
                  Text(
                    line,
                    textDirection: TextDirection.rtl,
                    textAlign: _isBasmalaLine(line)
                        ? TextAlign.center
                        : TextAlign.justify,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: AppTheme.quranFont,
                      fontFamilyFallback: AppTheme.quranFallback,
                      fontSize: 21,
                      height: 2.0,
                    ),
                  ),
              if (instruction != null && instruction!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 14, color: scheme.secondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        instruction!,
                        textDirection: TextDirection.rtl,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (source != null && source!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(source!, style: theme.textTheme.labelSmall),
                    ),
                  ],
                ),
              ],
              if (virtue != null && virtue!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  virtue!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: complete ? scheme.primary : scheme.secondary,
                ),
              ),
              Row(
                children: [
                  Text(
                    repeat <= 1
                        ? (complete
                              ? context.tr('تم', 'Done')
                              : context.tr('اضغط للعدّ', 'Tap to count'))
                        : context.tr(
                            '${context.digits(count)} من ${context.digits(repeat)}',
                            '$count of $repeat',
                          ),
                    style: theme.textTheme.labelSmall,
                  ),
                  const Spacer(),
                  if (count > 0)
                    TextButton(
                      onPressed: () => ref
                          .read(adhkarProgressProvider.notifier)
                          .resetKey(progressKey),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(context.tr('تصفير', 'Reset')),
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

/// حالة ما قبل استيراد المحتوى.
class _PendingContent extends StatelessWidget {
  const _PendingContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_outlined,
              size: 44,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'المحتوى قيد المراجعة الشرعية',
                'Content under scholarly review',
              ),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
