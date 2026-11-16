import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';

import '../data/books_repository.dart';
import '../data/library_store.dart';
import '../domain/library_catalog.dart';

/// المكتبة: كتب السيرة والتاريخ. يُنزَّل الكتاب مرة ثم يُقرأ دون إنترنت،
/// صفحةً صفحة مع فهرس فصوله وحفظ آخر موضع.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final downloaded =
        ref.watch(downloadedLibraryProvider).value ?? const <String>{};
    final progress = ref.watch(libraryDownloadsProvider);
    final categories = <String>[];
    for (final book in libraryCatalog) {
      if (!categories.contains(book.category)) categories.add(book.category);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('السيرة والتاريخ', 'Seerah & history')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              context.tr(
                'يُنزَّل الكتاب مرة واحدة ثم يُقرأ دون إنترنت',
                'Download once, read offline',
              ),
              style: theme.textTheme.labelSmall,
            ),
          ),
          for (final category in categories) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
              child: Text(category, style: theme.textTheme.titleSmall),
            ),
            for (final book in libraryCatalog.where(
              (b) => b.category == category,
            ))
              _LibraryTile(
                book: book,
                downloaded: downloaded.contains(book.slug),
                progress: progress[book.slug],
              ),
          ],
        ],
      ),
    );
  }
}

class _LibraryTile extends ConsumerWidget {
  const _LibraryTile({
    required this.book,
    required this.downloaded,
    required this.progress,
  });

  final LibraryBook book;
  final bool downloaded;
  final double? progress;

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr(
      'تعذّر تنزيل «${book.title}» — تحقق من الاتصال وأعد المحاولة',
      'Could not download — check your connection',
    );
    try {
      await ref.read(libraryDownloadsProvider.notifier).download(book);
    } catch (error) {
      debugPrint('[YousufLibrary] تعذّر تنزيل ${book.slug}: $error');
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
            'يُحذف «${book.title}» من الجهاز، ويمكن تنزيله لاحقاً.',
            '${book.title} will be removed; you can download it again.',
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
      await ref.read(libraryDownloadsProvider.notifier).delete(book.slug);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final size = context.digits((book.bytes / 1048576).toStringAsFixed(1));
    final pages = context.tr(
      '${context.digits(book.pages)} صفحة',
      '${book.pages} pages',
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
      trailing = const Icon(Icons.download_outlined);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Icon(
            downloaded ? Icons.menu_book : Icons.menu_book_outlined,
            color: scheme.primary,
            size: 30,
          ),
          title: Text(
            book.title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontFamily: 'Amiri'),
          ),
          subtitle: Text(
            downloaded
                ? '${book.author} · $pages'
                : context.tr(
                    '${book.author} · $pages · للتنزيل $size م.ب',
                    '${book.author} · $pages · $size MB',
                  ),
          ),
          trailing: trailing,
          onTap: progress != null
              ? null
              : downloaded
              ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LibraryBookScreen(book: book),
                  ),
                )
              : () => _download(context, ref),
          onLongPress: downloaded ? () => _confirmDelete(context, ref) : null,
        ),
      ),
    );
  }
}

/// فهرس الكتاب: «تابع القراءة» ثم الفصول.
class LibraryBookScreen extends ConsumerWidget {
  const LibraryBookScreen({super.key, required this.book});

  final LibraryBook book;

  void _open(BuildContext context, WidgetRef ref, int page) {
    ref.read(bookPositionProvider.notifier).save(book.slug, page);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryReader(book: book, initialPage: page),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(libraryBookDbProvider(book.slug));
    final last = ref.watch(bookPositionProvider)[book.slug];
    return Scaffold(
      appBar: AppBar(title: Text(book.title)),
      body: dbAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (db) {
          final chapters = db.chapters();
          final license = db.meta('license');
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: chapters.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton.icon(
                    onPressed: () => _open(context, ref, last ?? 1),
                    icon: const Icon(Icons.chrome_reader_mode_outlined),
                    label: Text(
                      last != null && last > 1
                          ? context.tr(
                              'تابع القراءة — صفحة ${context.digits(last)}',
                              'Continue — page $last',
                            )
                          : context.tr('ابدأ القراءة', 'Start reading'),
                    ),
                  ),
                );
              }
              if (i == chapters.length + 1) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    license,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              }
              final chapter = chapters[i - 1];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  chapter.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: chapter.volume == null
                    ? null
                    : Text(
                        context.tr(
                          'الجزء ${context.digits(chapter.volume!)}',
                          'Volume ${chapter.volume}',
                        ),
                      ),
                trailing: Text(context.digits(chapter.firstPage)),
                onTap: () => _open(context, ref, chapter.firstPage),
              );
            },
          );
        },
      ),
    );
  }
}

/// قارئ الكتاب صفحةً صفحة مع حفظ آخر صفحة. اتجاه التقليب يتبع الواجهة
/// العربية (السحب من اليسار إلى اليمين يقلّب للصفحة التالية) كالمصحف.
class LibraryReader extends ConsumerStatefulWidget {
  const LibraryReader({
    super.key,
    required this.book,
    required this.initialPage,
  });

  final LibraryBook book;

  /// تبدأ من ١.
  final int initialPage;

  @override
  ConsumerState<LibraryReader> createState() => _LibraryReaderState();
}

class _LibraryReaderState extends ConsumerState<LibraryReader> {
  late final PageController _controller = PageController(
    initialPage: widget.initialPage - 1,
  );
  double _fontSize = 20;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dbAsync = ref.watch(libraryBookDbProvider(widget.book.slug));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          IconButton(
            tooltip: context.tr('تصغير الخط', 'Smaller text'),
            icon: const Icon(Icons.text_decrease),
            onPressed: () =>
                setState(() => _fontSize = (_fontSize - 1).clamp(14, 34)),
          ),
          IconButton(
            tooltip: context.tr('تكبير الخط', 'Larger text'),
            icon: const Icon(Icons.text_increase),
            onPressed: () =>
                setState(() => _fontSize = (_fontSize + 1).clamp(14, 34)),
          ),
        ],
      ),
      body: dbAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (db) => PageView.builder(
          controller: _controller,
          itemCount: db.pageCount,
          onPageChanged: (index) => ref
              .read(bookPositionProvider.notifier)
              .save(widget.book.slug, index + 1),
          itemBuilder: (context, index) {
            final page = db.page(index + 1);
            if (page == null) return const SizedBox.shrink();
            final printed = [
              if (page.volume != null)
                context.tr(
                  'الجزء ${context.digits(page.volume!)}',
                  'Vol. ${page.volume}',
                ),
              if (page.pageNum != null)
                context.tr(
                  'ص ${context.digits(page.pageNum!)}',
                  'p. ${page.pageNum}',
                ),
            ].join(' · ');
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    page.chapter,
                    textDirection: TextDirection.rtl,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontFamily: 'Amiri',
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    page.text,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.justify,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFamily: 'Amiri',
                      fontSize: _fontSize,
                      height: 1.9,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    [
                      context.tr(
                        '${context.digits(page.index)} / ${context.digits(db.pageCount)}',
                        '${page.index} / ${db.pageCount}',
                      ),
                      if (printed.isNotEmpty) printed,
                    ].join('   ·   '),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
