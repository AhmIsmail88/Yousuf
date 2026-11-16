import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:yousuf/core/share/share_card.dart';
import 'package:yousuf/core/widgets/ornament.dart';

import '../domain/hadith_library.dart';
import '../domain/hadith_models.dart';
import 'hadith_providers.dart';

/// مكتبة الحديث (SPEC §7.6): الأربعينات مع التطبيق، والكتب التسعة تُنزَّل
/// عند الطلب مرة واحدة ثم تعمل دون إنترنت.
class HadithScreen extends ConsumerWidget {
  const HadithScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bundled = ref.watch(hadithBooksProvider).value ?? const [];
    final downloaded =
        ref.watch(downloadedHadithBooksProvider).value ?? const <String>{};
    final progress = ref.watch(hadithDownloadsProvider);

    Widget header(String title, [String? subtitle]) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          if (subtitle != null)
            Text(subtitle, style: theme.textTheme.labelSmall),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('الحديث', 'Hadith'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        children: [
          header(context.tr('مع التطبيق', 'Included')),
          for (final book in bundled)
            _BookTile(
              title: book.nameAr,
              subtitle: context.tr(
                '${context.digits(book.total)} حديثاً',
                '${book.total} hadith',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BundledBookScreen(book: book),
                ),
              ),
            ),
          header(
            context.tr('مكتبة الحديث', 'Hadith library'),
            context.tr(
              'يُنزَّل الكتاب مرة واحدة ثم يعمل دون إنترنت',
              'Download once, read offline',
            ),
          ),
          for (final book in hadithCatalog)
            _CollectionTile(
              book: book,
              downloaded: downloaded.contains(book.slug),
              progress: progress[book.slug],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
            child: Text(
              context.tr(
                'النصوص من مشروع hadith-api (ملكية عامة). أحاديث السنن والموطأ '
                    'تُعرض بدرجتها عند المحققين كما في المصدر.',
                'Texts from hadith-api (public domain). Sunan and Muwatta '
                    'hadith show their grades as given in the source.',
              ),
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: ListTile(
          onTap: onTap,
          onLongPress: onLongPress,
          leading: Icon(Icons.menu_book_outlined, color: scheme.primary),
          title: Text(
            title,
            style: const TextStyle(fontFamily: 'Amiri', fontSize: 18),
          ),
          subtitle: Text(subtitle),
          trailing: trailing,
        ),
      ),
    );
  }
}

/// كتاب في المكتبة: تنزيل / تقدّم / فتح.
class _CollectionTile extends ConsumerWidget {
  const _CollectionTile({
    required this.book,
    required this.downloaded,
    required this.progress,
  });

  final HadithCollection book;
  final bool downloaded;
  final double? progress;

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr(
      'تعذّر تنزيل «${book.nameAr}» — تحقق من الاتصال وأعد المحاولة',
      'Could not download ${book.nameEn} — check your connection',
    );
    try {
      await ref.read(hadithDownloadsProvider.notifier).download(book);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('حذف الكتاب؟', 'Delete book?')),
        content: Text(
          context.tr(
            'يُحذف «${book.nameAr}» من الجهاز، ويمكن تنزيله لاحقاً.',
            '${book.nameEn} will be removed; you can download it again.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(hadithDownloadsProvider.notifier).delete(book.slug);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = context.tr(
      '${context.digits((book.bytes / 1048576).toStringAsFixed(1))} م.ب',
      '${(book.bytes / 1048576).toStringAsFixed(1)} MB',
    );
    final count = context.tr(
      '${context.digits(book.count)} حديثاً',
      '${book.count} hadith',
    );
    final Widget trailing;
    if (progress != null) {
      trailing = SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          value: progress! > 0 ? progress : null,
          strokeWidth: 3,
        ),
      );
    } else if (downloaded) {
      trailing = const Icon(Icons.chevron_right);
    } else {
      trailing = IconButton(
        tooltip: context.tr('تنزيل', 'Download'),
        icon: const Icon(Icons.download_outlined),
        onPressed: () => _download(context, ref),
      );
    }
    return _BookTile(
      title: book.name(arabic: context.isArabic),
      subtitle: downloaded
          ? count
          : context.tr('$count · للتنزيل $size', '$count · $size download'),
      trailing: trailing,
      onTap: progress != null
          ? null
          : downloaded
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HadithBookScreen(book: book),
              ),
            )
          : () => _download(context, ref),
      onLongPress: downloaded ? () => _confirmDelete(context, ref) : null,
    );
  }
}

// ---------------- الأربعينات (مع التطبيق) ----------------

class BundledBookScreen extends ConsumerWidget {
  const BundledBookScreen({super.key, required this.book});

  final HadithBook book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hadithAsync = ref.watch(bundledHadithProvider(book.id));
    return Scaffold(
      appBar: AppBar(title: Text(book.nameAr)),
      body: hadithAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (hadiths) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: hadiths.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final hadith = hadiths[index];
            return _HadithTile(
              number: '${hadith.number}',
              text: hadith.text,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => HadithDetailScreen(
                    number: '${hadith.number}',
                    text: hadith.text,
                    bookName: book.nameAr,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------- الكتب المنزَّلة ----------------

/// أبواب كتاب منزَّل، مع البحث في نصه.
class HadithBookScreen extends ConsumerWidget {
  const HadithBookScreen({super.key, required this.book});

  final HadithCollection book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sectionsAsync = ref.watch(hadithSectionsProvider(book.slug));
    return Scaffold(
      appBar: AppBar(
        title: Text(book.name(arabic: context.isArabic)),
        actions: [
          IconButton(
            tooltip: context.tr('بحث في الكتاب', 'Search this book'),
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HadithSearchScreen(book: book),
              ),
            ),
          ),
        ],
      ),
      body: sectionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (sections) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: sections.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final section = sections[index];
            final range = section.first != null && section.last != null
                ? context.tr(
                    'الأحاديث ${context.digits(_num(section.first!))}–${context.digits(_num(section.last!))}',
                    'Hadith ${_num(section.first!)}–${_num(section.last!)}',
                  )
                : context.tr(
                    '${context.digits(section.total)} حديثاً',
                    '${section.total} hadith',
                  );
            return ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  context.digits(section.id),
                  style: theme.textTheme.labelMedium,
                ),
              ),
              title: Text(
                context.tr(
                  'الكتاب ${context.digits(section.id)}',
                  'Book ${section.id}',
                ),
              ),
              // اسم الباب في المصدر بالإنجليزية فقط — يُعرض كما هو.
              subtitle: Text(
                section.nameEn.isEmpty ? range : '$range\n${section.nameEn}',
              ),
              isThreeLine: section.nameEn.isNotEmpty,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      HadithSectionScreen(book: book, section: section),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _num(num value) =>
    value == value.roundToDouble() ? '${value.toInt()}' : '$value';

/// أحاديث باب واحد.
class HadithSectionScreen extends ConsumerWidget {
  const HadithSectionScreen({
    super.key,
    required this.book,
    required this.section,
  });

  final HadithCollection book;
  final HadithSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hadithAsync = ref.watch(
      hadithSectionProvider((slug: book.slug, section: section.id)),
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(book.name(arabic: context.isArabic)),
            Text(
              context.tr(
                'الكتاب ${context.digits(section.id)}',
                'Book ${section.id}',
              ),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      body: hadithAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (hadiths) => _BookHadithList(book: book, hadiths: hadiths),
      ),
    );
  }
}

class _BookHadithList extends StatelessWidget {
  const _BookHadithList({required this.book, required this.hadiths});

  final HadithCollection book;
  final List<BookHadith> hadiths;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    itemCount: hadiths.length,
    separatorBuilder: (_, _) => const SizedBox(height: 8),
    itemBuilder: (context, index) {
      final hadith = hadiths[index];
      return _HadithTile(
        number: hadith.number,
        text: hadith.text,
        grade: _primaryGrade(hadith.grades),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => HadithDetailScreen(
              number: hadith.number,
              text: hadith.text,
              bookName: book.nameAr,
              grades: hadith.grades,
            ),
          ),
        ),
      );
    },
  );
}

/// الدرجة المعروضة في القائمة: حكم الألباني إن وُجد، وإلا الأول.
HadithGrade? _primaryGrade(List<HadithGrade> grades) {
  if (grades.isEmpty) return null;
  return grades.firstWhere(
    (grade) => grade.grader == 'الألباني',
    orElse: () => grades.first,
  );
}

/// البحث في نص كتاب منزَّل.
class HadithSearchScreen extends ConsumerStatefulWidget {
  const HadithSearchScreen({super.key, required this.book});

  final HadithCollection book;

  @override
  ConsumerState<HadithSearchScreen> createState() => _HadithSearchState();
}

class _HadithSearchState extends ConsumerState<HadithSearchScreen> {
  List<BookHadith>? _results;

  Future<void> _search(String query) async {
    final db = await ref.read(hadithBookDbProvider(widget.book.slug).future);
    if (!mounted) return;
    setState(() => _results = db.search(query));
  }

  @override
  Widget build(BuildContext context) {
    // يُبقي الكتاب مفتوحاً ما دامت الشاشة ظاهرة.
    ref.watch(hadithBookDbProvider(widget.book.slug));
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: context.tr(
              'ابحث في ${widget.book.nameAr}…',
              'Search ${widget.book.nameEn}…',
            ),
          ),
        ),
      ),
      body: results == null
          ? const SizedBox.shrink()
          : results.isEmpty
          ? Center(child: Text(context.tr('لا توجد نتائج', 'No results')))
          : _BookHadithList(book: widget.book, hadiths: results),
    );
  }
}

// ---------------- عناصر مشتركة ----------------

class _HadithTile extends StatelessWidget {
  const _HadithTile({
    required this.number,
    required this.text,
    required this.onTap,
    this.grade,
  });

  final String number;
  final String text;
  final HadithGrade? grade;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 34),
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  context.digits(number),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'Amiri',
                        fontSize: 16,
                        height: 1.9,
                      ),
                    ),
                    if (grade != null) ...[
                      const SizedBox(height: 6),
                      GradeChip(grade: grade!),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// شارة درجة الحديث: لون حسب المرتبة، والنص بالمصطلح.
class GradeChip extends StatelessWidget {
  const GradeChip({super.key, required this.grade, this.showGrader = false});

  final HadithGrade grade;
  final bool showGrader;

  static Color colorOf(String category) => switch (category) {
    'sahih' => const Color(0xFF2E7D4F),
    'hasan' => const Color(0xFF2B6E9E),
    'daif' => const Color(0xFFB26A00),
    'mawdu' => const Color(0xFFB3261E),
    _ => const Color(0xFF6B6B6B),
  };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(grade.category);
    final label = showGrader
        ? '${grade.gradeAr} — ${grade.grader}'
        : grade.gradeAr;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        textDirection: TextDirection.rtl,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, height: 1.4),
      ),
    );
  }
}

/// تفاصيل حديث + درجاته + مشاركة كصورة/نص.
class HadithDetailScreen extends StatelessWidget {
  const HadithDetailScreen({
    super.key,
    required this.number,
    required this.text,
    required this.bookName,
    this.grades = const [],
  });

  final String number;
  final String text;
  final String bookName;
  final List<HadithGrade> grades;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = _primaryGrade(grades);
    final source = [
      '$bookName — الحديث ${context.digits(number)}',
      if (primary != null) '${primary.gradeAr} (${primary.grader})',
    ].join('\n');
    void share() => showShareSheet(
      context,
      text: text,
      source: source,
      title: 'من $bookName',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr('الحديث ${context.digits(number)}', 'Hadith $number'),
        ),
        actions: [
          IconButton(
            tooltip: context.tr('مشاركة', 'Share'),
            icon: const Icon(Icons.share_outlined),
            onPressed: share,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        children: [
          OrnamentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  text,
                  textDirection: TextDirection.rtl,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'Amiri',
                    fontSize: 20,
                    height: 2.1,
                  ),
                ),
                const SizedBox(height: 14),
                const OrnamentDivider(),
                const SizedBox(height: 10),
                Text(
                  '$bookName — ${context.tr('الحديث', 'hadith')} ${context.digits(number)}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          if (grades.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              context.tr('درجة الحديث', 'Grade'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final grade in grades)
                  GradeChip(grade: grade, showGrader: true),
              ],
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: share,
            icon: const Icon(Icons.ios_share, size: 18),
            label: Text(context.tr('مشاركة الحديث', 'Share hadith')),
          ),
        ],
      ),
    );
  }
}
