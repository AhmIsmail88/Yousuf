import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:yousuf/core/utils/quran_text.dart';

import '../data/quran_extras_store.dart';
import '../domain/quran_extras.dart';
import '../domain/quran_models.dart';
import 'quran_providers.dart';

// ---------------- المزوّدات ----------------

final ayahStudyRepositoryProvider = FutureProvider<AyahStudyRepository>((
  ref,
) async {
  final content = await ref.watch(contentDbProvider.future);
  return AyahStudyRepository(content);
});

/// المصادر الموجودة على الجهاز.
final downloadedExtrasProvider = FutureProvider<Set<String>>(
  (ref) => QuranExtrasStore.downloaded(),
);

/// تنزيلات جارية: معرّف المصدر ← التقدّم (٠–١).
class QuranExtrasDownloads extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  Future<void> download(QuranExtra extra) async {
    if (state.containsKey(extra.slug)) return;
    state = {...state, extra.slug: 0};
    try {
      await QuranExtrasStore.download(
        extra,
        onProgress: (progress) => state = {...state, extra.slug: progress},
      );
    } finally {
      state = {...state}..remove(extra.slug);
      ref.invalidate(downloadedExtrasProvider);
    }
  }

  Future<void> delete(String slug) async {
    ref.invalidate(quranExtraDbProvider(slug));
    await QuranExtrasStore.delete(slug);
    ref.invalidate(downloadedExtrasProvider);
  }
}

final quranExtrasDownloadsProvider =
    NotifierProvider<QuranExtrasDownloads, Map<String, double>>(
      QuranExtrasDownloads.new,
    );

/// مصدر منزَّل مفتوح للقراءة — يُغلق حين لا يستعمله أحد.
final quranExtraDbProvider = FutureProvider.autoDispose
    .family<QuranExtraDb, String>((ref, slug) async {
      final file = await QuranExtrasStore.fileFor(slug);
      if (!file.existsSync()) throw StateError('المصدر غير منزَّل');
      final db = QuranExtraDb.open(file.path);
      ref.onDispose(db.close);
      return db;
    });

// ---------------- الشاشة ----------------

/// تفسير الآية وترجمتها وسبب نزولها.
class AyahStudyScreen extends ConsumerWidget {
  const AyahStudyScreen({
    super.key,
    required this.ayah,
    required this.surahName,
    this.asbabFirst = false,
  });

  final Ayah ayah;
  final String surahName;

  /// فُتحت من «أسباب النزول» في قائمة الآية: تظهر أولاً ومفتوحة.
  final bool asbabFirst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final study = ref.watch(ayahStudyRepositoryProvider).value;
    final downloaded =
        ref.watch(downloadedExtrasProvider).value ?? const <String>{};
    final muyassar = study?.muyassar(ayah.id);
    final asbab = study?.asbab(ayah.id);
    final arabic = context.isArabic;
    final asbabTitle = context.tr('أسباب النزول', 'Occasions of revelation');
    final asbabSource = context.tr('للواحدي', 'by al-Wahidi');
    // ليس لكل آية سبب نزول: كتاب الواحدي يذكره لـ٥٦٤ آية فقط — نقول ذلك صراحة.
    final Widget wahidiCard = asbab != null
        ? _StudyCard(
            title: asbabTitle,
            subtitle: asbabSource,
            text: asbab,
            rtl: true,
            initiallyExpanded: asbabFirst,
          )
        : Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text(asbabTitle, style: theme.textTheme.titleSmall),
              subtitle: Text(
                context.tr(
                  'لم يُروَ لهذه الآية سبب نزول في كتاب الواحدي.',
                  'No occasion of revelation is narrated for this ayah '
                      'in al-Wahidi.',
                ),
              ),
            ),
          );
    final suyuti = quranExtrasCatalog.firstWhere(
      (e) => e.kind == QuranExtraKind.asbab,
    );
    final Widget asbabCard = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        wahidiCard,
        if (downloaded.contains(suyuti.slug))
          _ExtraCard(
            extra: suyuti,
            ayah: ayah,
            expanded: asbabFirst,
            emptyNote: context.tr(
              'لم يذكر السيوطي سبب نزول لهذه الآية.',
              'Al-Suyuti narrates no occasion for this ayah.',
            ),
          )
        else
          _DownloadTile(extra: suyuti),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(context.tr('التفسير والترجمة', 'Tafsir & translation')),
            Text(
              context.tr(
                'سورة $surahName · آية ${context.digits(ayah.number)}',
                'Surah $surahName · ayah ${ayah.number}',
              ),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            '${quranFontText(displayQuranText(stripLeadingBasmala(ayah.text, surahId: ayah.surahId, number: ayah.number)))}'
            '${ayahMark(ayah.number)}',
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTheme.quranFont,
              fontFamilyFallback: AppTheme.quranFallback,
              fontSize: 24,
              height: 2,
            ),
          ),
          const SizedBox(height: 12),
          if (asbabFirst) asbabCard,
          if (muyassar != null)
            _StudyCard(
              title: context.tr('التفسير الميسر', 'Al-Tafsir al-Muyassar'),
              subtitle: context.tr(
                'مجمع الملك فهد لطباعة المصحف الشريف',
                'King Fahd Complex',
              ),
              text: muyassar,
              rtl: true,
            ),
          if (!asbabFirst) asbabCard,
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
            child: Text(
              context.tr('تفاسير وترجمات للتنزيل', 'More to download'),
              style: theme.textTheme.titleSmall,
            ),
          ),
          for (final extra in quranExtrasCatalog.where(
            (e) => e.kind != QuranExtraKind.asbab,
          ))
            downloaded.contains(extra.slug)
                ? _ExtraCard(extra: extra, ayah: ayah)
                : _DownloadTile(extra: extra),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
            child: Text(
              arabic
                  ? 'التفسير الميسر وأسباب النزول للواحدي وابن كثير والطبري من '
                        'Quranpedia.net، ولباب النقول للسيوطي من المكتبة الشاملة '
                        '(رُبطت رواياته بالآيات آلياً). الترجمات في الملكية العامة.'
                  : 'Muyassar, asbab al-nuzul, Ibn Kathir and al-Tabari from '
                        'Quranpedia.net. Translations are in the public domain.',
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({
    required this.title,
    required this.text,
    required this.rtl,
    this.subtitle,
    this.initiallyExpanded = true,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String text;
  final bool rtl;
  final bool initiallyExpanded;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(title, style: theme.textTheme.titleSmall),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          SelectableText.rich(
            _withNotes(text, theme),
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: rtl ? 'Amiri' : null,
              height: rtl ? 2.0 : 1.6,
            ),
          ),
        ],
      ),
    );
  }

  /// حواشي التحقيق «[[...]]» (في ابن كثير) تُعرض أصغر وأخفت من المتن.
  static TextSpan _withNotes(String text, ThemeData theme) {
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\[\[(.*?)\]\]', dotAll: true);
    var last = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      spans.add(
        TextSpan(
          text: '(${match.group(1)})',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(children: spans);
  }
}

/// مصدر منزَّل: نصه للآية، مع حذفه بضغطة مطوّلة.
class _ExtraCard extends ConsumerWidget {
  const _ExtraCard({
    required this.extra,
    required this.ayah,
    this.expanded = false,
    this.emptyNote,
  });

  final QuranExtra extra;
  final Ayah ayah;
  final bool expanded;

  /// تُعرض إن لم يكن للمصدر نص لهذه الآية (أسباب النزول ليست لكل آية).
  final String? emptyNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbAsync = ref.watch(quranExtraDbProvider(extra.slug));
    final arabic = context.isArabic;
    return dbAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => ListTile(title: Text('$error')),
      data: (db) {
        final text = db.textFor(ayah.surahId, ayah.number) ?? '';
        if (text.isEmpty && emptyNote != null) {
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text(
                extra.name(arabic: arabic),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              subtitle: Text(emptyNote!),
            ),
          );
        }
        final range = extra.kind == QuranExtraKind.tafsir
            ? db.sharedRange(ayah.surahId, ayah.number)
            : (first: ayah.number, last: ayah.number);
        final shared = range.first != range.last
            ? context.tr(
                'تفسير الآيات ${context.digits(range.first)}–${context.digits(range.last)}',
                'Ayat ${range.first}–${range.last}',
              )
            : null;
        return _StudyCard(
          title: extra.name(arabic: arabic),
          subtitle: [?shared, extra.author].join(' · '),
          text: text,
          rtl: extra.rtl,
          initiallyExpanded: expanded,
          trailing: PopupMenuButton<String>(
            onSelected: (_) => ref
                .read(quranExtrasDownloadsProvider.notifier)
                .delete(extra.slug),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'delete',
                child: Text(context.tr('حذف من الجهاز', 'Remove download')),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({required this.extra});

  final QuranExtra extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(quranExtrasDownloadsProvider)[extra.slug];
    final size = (extra.bytes / 1048576).toStringAsFixed(1);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(switch (extra.kind) {
          QuranExtraKind.tafsir => Icons.auto_stories_outlined,
          QuranExtraKind.translation => Icons.translate,
          QuranExtraKind.asbab => Icons.history_edu_outlined,
        }),
        title: Text(extra.name(arabic: context.isArabic)),
        subtitle: Text(
          context.tr(
            '${extra.author} · ${context.digits(size)} م.ب',
            '${extra.author} · $size MB',
          ),
        ),
        trailing: progress != null
            ? SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  value: progress > 0 ? progress : null,
                  strokeWidth: 3,
                ),
              )
            : const Icon(Icons.download_outlined),
        onTap: progress != null
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                final failed = context.tr(
                  'تعذّر التنزيل — تحقق من الاتصال وأعد المحاولة',
                  'Download failed — check your connection',
                );
                try {
                  await ref
                      .read(quranExtrasDownloadsProvider.notifier)
                      .download(extra);
                } catch (_) {
                  messenger.showSnackBar(SnackBar(content: Text(failed)));
                }
              },
      ),
    );
  }
}
