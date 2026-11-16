import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/core/utils/quran_text.dart';
import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:yousuf/l10n/generated/app_localizations.dart';

import '../domain/quran_models.dart';
import 'mushaf_reader_screen.dart';
import 'quran_providers.dart';

/// فهرس المصحف (SPEC §7.3): بحث، تبويبات السور/الأجزاء/العلامات،
/// و«متابعة القراءة» بآخر موضع.
class QuranScreen extends ConsumerStatefulWidget {
  const QuranScreen({super.key});

  @override
  ConsumerState<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends ConsumerState<QuranScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// يفتح القارئ ملء الشاشة (بلا شريط التنقل)، وعلى آية محددة إن وُجدت:
  /// تُعرض الصفحة وتُظلَّل الآية.
  void _open(int page, {int? ayahId}) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MushafReaderScreen(initialPage: page, highlightAyahId: ayahId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = ref.watch(searchQueryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tabQuran),
        actions: [
          IconButton(
            tooltip: context.tr('متابعة القراءة', 'Continue reading'),
            icon: const Icon(Icons.play_arrow_outlined),
            onPressed: () async {
              final page = await ref.read(lastReadPageProvider.future);
              if (mounted) _open(page);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: context.tr('ابحث في القرآن…', 'Search the Quran…'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(searchQueryProvider.notifier).update('');
                        },
                      ),
                filled: true,
                fillColor: scheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              onChanged: (value) =>
                  ref.read(searchQueryProvider.notifier).update(value),
            ),
          ),
          Expanded(
            child: query.trim().length < 2
                ? _IndexTabs(onOpen: _open)
                : _SearchResults(onOpen: _open),
          ),
        ],
      ),
    );
  }
}

typedef _Opener = void Function(int page, {int? ayahId});

/// تبويبات الفهرس الثلاثة: السور · الأجزاء · العلامات.
class _IndexTabs extends StatelessWidget {
  const _IndexTabs({required this.onOpen});

  final _Opener onOpen;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: context.tr('السور', 'Surahs')),
              Tab(text: context.tr('الأجزاء', 'Juz')),
              Tab(text: context.tr('العلامات', 'Bookmarks')),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _SurahList(onOpen: onOpen),
                _JuzList(onOpen: onOpen),
                _BookmarksList(onOpen: onOpen),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SurahList extends ConsumerWidget {
  const _SurahList({required this.onOpen});

  final _Opener onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surahsAsync = ref.watch(surahsProvider);
    final arabic = context.isArabic;
    return surahsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          context.tr(
            'تعذر فتح المصحف: $error',
            'Could not open the Quran: $error',
          ),
        ),
      ),
      data: (surahs) => ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: surahs.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final surah = surahs[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _NumberBadge(number: surah.id),
            title: Text(
              arabic ? surah.nameAr : '${surah.nameEn} · ${surah.nameAr}',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontFamily: 'Amiri'),
            ),
            subtitle: Text(
              context.tr(
                '${surah.isMakki ? 'مكية' : 'مدنية'} · ${context.digits(surah.ayahCount)} آية',
                '${surah.isMakki ? 'Meccan' : 'Medinan'} · ${surah.ayahCount} ayahs',
              ),
            ),
            trailing: Text(
              context.tr(
                'ص ${context.digits(surah.startPage)}',
                'p. ${surah.startPage}',
              ),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            onTap: () => onOpen(surah.startPage),
          );
        },
      ),
    );
  }
}

class _JuzList extends ConsumerWidget {
  const _JuzList({required this.onOpen});

  final _Opener onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final juzAsync = ref.watch(juzStartsProvider);
    return juzAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (juzStarts) => ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: juzStarts.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final juz = juzStarts[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _NumberBadge(number: juz.juz),
            title: Text(
              context.tr('الجزء ${context.digits(juz.juz)}', 'Juz ${juz.juz}'),
            ),
            subtitle: Text(
              context.tr(
                'يبدأ من صفحة ${context.digits(juz.page)}',
                'Starts on page ${juz.page}',
              ),
            ),
            trailing: const Icon(Icons.chevron_left, size: 18),
            onTap: () => onOpen(juz.page),
          );
        },
      ),
    );
  }
}

/// العلامات: كل آية معلَّمة تبقى (الإضافة لا تلغي القديم)، والضغط يفتح
/// الصفحة على الآية مظلَّلة، والحذف بالسحب أو بزر الحذف.
class _BookmarksList extends ConsumerWidget {
  const _BookmarksList({required this.onOpen});

  final _Opener onOpen;

  Future<void> _remove(BuildContext context, WidgetRef ref, Ayah ayah) async {
    final messenger = ScaffoldMessenger.of(context);
    final removed = context.tr('حُذفت العلامة', 'Bookmark removed');
    final undo = context.tr('تراجع', 'Undo');
    final notifier = ref.read(quranBookmarksProvider.notifier);
    await notifier.remove(ayah.surahId, ayah.number);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(removed),
        action: SnackBarAction(
          label: undo,
          onPressed: () => notifier.add(ayah.surahId, ayah.number),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(bookmarkedAyahsProvider);
    final scheme = Theme.of(context).colorScheme;
    return bookmarksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (hits) {
        if (hits.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_border,
                    size: 40,
                    color: scheme.secondary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr('لا توجد علامات بعد', 'No bookmarks yet'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(
                      'اضغط على أي آية في المصحف ثم «إضافة علامة».',
                      'Tap any ayah in the reader, then “Add bookmark”.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: hits.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final hit = hits[index];
            final ayah = hit.ayah;
            return Dismissible(
              key: ValueKey('bookmark-${ayah.surahId}:${ayah.number}'),
              background: Container(
                color: scheme.errorContainer,
                alignment: AlignmentDirectional.centerEnd,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Icon(
                  Icons.delete_outline,
                  color: scheme.onErrorContainer,
                ),
              ),
              onDismissed: (_) => _remove(context, ref, ayah),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.bookmark, color: scheme.primary, size: 20),
                title: Text(
                  quranFontText(_snippet(ayah.text)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: AppTheme.quranFont,
                    fontFamilyFallback: AppTheme.quranFallback,
                    height: 1.7,
                  ),
                ),
                subtitle: Text(
                  context.tr(
                    '${hit.surahNameAr} · آية ${context.digits(ayah.number)} · ص ${context.digits(ayah.page)}',
                    '${hit.surahNameAr} · ayah ${ayah.number} · p. ${ayah.page}',
                  ),
                ),
                trailing: IconButton(
                  tooltip: context.tr('حذف العلامة', 'Remove bookmark'),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _remove(context, ref, ayah),
                ),
                onTap: () => onOpen(ayah.page, ayahId: ayah.id),
              ),
            );
          },
        );
      },
    );
  }

  static String _snippet(String text) =>
      text.length > 90 ? '${text.substring(0, 90)}…' : text;
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        context.digits(number),
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: scheme.onPrimaryContainer),
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.onOpen});

  final _Opener onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(searchResultsProvider);
    return resultsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (hits) {
        if (hits.isEmpty) {
          return Center(child: Text(context.tr('لا توجد نتائج', 'No results')));
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: hits.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final hit = hits[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                hit.snippet,
                textDirection: TextDirection.rtl,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontFamily: AppTheme.quranFont,
                  fontFamilyFallback: AppTheme.quranFallback,
                  height: 1.8,
                ),
              ),
              subtitle: Text(
                context.tr(
                  '${hit.surahNameAr} · آية ${context.digits(hit.ayah.number)}',
                  '${hit.surahNameAr} · ayah ${hit.ayah.number}',
                ),
              ),
              onTap: () => onOpen(hit.ayah.page, ayahId: hit.ayah.id),
            );
          },
        );
      },
    );
  }
}
