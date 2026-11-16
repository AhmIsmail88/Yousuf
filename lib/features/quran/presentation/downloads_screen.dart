import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';

import 'download_manager.dart';
import 'quran_providers.dart';
import 'reciter_picker.dart';

export 'download_manager.dart' show downloadedIdsProvider;

/// عدد الآيات في المصحف — لوصف أحجام التحميل.
const int _totalAyahs = 6236;

/// مركز التحميلات: اختيار القارئ ثم تحميل المصحف/الجزء/السورة/الصفحة.
///
/// التحميل نفسه في [downloadManagerProvider] العام: يستمر بعد مغادرة الشاشة
/// أو قفل الهاتف، ويظهر تقدّمه في إشعار.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  StreamSubscription<DownloadResult>? _results;

  @override
  void initState() {
    super.initState();
    _results = ref.read(downloadManagerProvider.notifier).results.listen((r) {
      if (!mounted) return;
      _snack(switch (r.outcome) {
        DownloadOutcome.completed => context.tr(
          'تم تحميل ${r.label}',
          '${r.label} downloaded',
        ),
        DownloadOutcome.cancelled => context.tr(
          'أُوقف التحميل',
          'Download stopped',
        ),
        DownloadOutcome.failed => context.tr(
          'تعذر إكمال التحميل: ${r.error}',
          'Download incomplete: ${r.error}',
        ),
      });
    });
  }

  @override
  void dispose() {
    _results?.cancel();
    super.dispose();
  }

  Future<void> _startDownload({
    required String label,
    required int first,
    required int last,
  }) async {
    final count = last - first + 1;
    if (count <= 0) {
      _snack(
        context.tr('لا توجد آيات في هذا النطاق', 'No ayahs in this range'),
      );
      return;
    }
    final repository = ref.read(quranAudioRepositoryProvider);
    final reciter = repository.reciter;
    final estimated = _formatSize(repository.estimatedMegabytes(count));
    final arabic = context.isArabic;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('تحميل $label', 'Download $label')),
        content: Text(
          context.tr(
            'القارئ: ${reciter.name(arabic: arabic)} (${reciter.subtitle})\n'
                '${context.digits(count)} آية · الحجم التقديري $estimated\n\n'
                'يُفضّل الاتصال بشبكة Wi-Fi. يستمر التحميل لو خرجت من الشاشة، '
                'ويمكنك إيقافه في أي وقت وما نُزّل يبقى محفوظاً.',
            'Reciter: ${reciter.name(arabic: arabic)} (${reciter.subtitle})\n'
                '$count ayahs · about $estimated\n\n'
                'Wi-Fi recommended. The download continues if you leave this '
                'screen; stop it anytime and finished files are kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('ابدأ التحميل', 'Start download')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    unawaited(
      ref
          .read(downloadManagerProvider.notifier)
          .start(label: label, first: first, last: last),
    );
  }

  Future<void> _pickSurah() async {
    final repository = await ref.read(quranRepositoryProvider.future);
    final surahs = repository.surahs();
    if (!mounted) return;
    final surah = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PickerSheet<int>(
        title: context.tr('اختر السورة', 'Choose a surah'),
        items: [
          for (final item in surahs)
            (
              value: item.id,
              title: context.isArabic
                  ? item.nameAr
                  : '${item.nameEn} · ${item.nameAr}',
              subtitle: context.tr(
                'صفحة ${context.digits(item.startPage)}',
                'page ${item.startPage}',
              ),
            ),
        ],
      ),
    );
    if (surah == null || !mounted) return;
    final range = repository.rangeOfSurah(surah);
    final name = repository.surah(surah)?.nameAr ?? '';
    await _startDownload(
      label: context.tr('سورة $name', 'Surah $name'),
      first: range.first,
      last: range.last,
    );
  }

  Future<void> _pickJuz() async {
    final repository = await ref.read(quranRepositoryProvider.future);
    if (!mounted) return;
    final juz = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _PickerSheet<int>(
        title: context.tr('اختر الجزء', 'Choose a juz'),
        items: [
          for (var index = 1; index <= 30; index++)
            (
              value: index,
              title: context.tr('الجزء ${context.digits(index)}', 'Juz $index'),
              subtitle: null,
            ),
        ],
      ),
    );
    if (juz == null || !mounted) return;
    final range = repository.rangeOfJuz(juz);
    await _startDownload(
      label: context.tr('الجزء ${context.digits(juz)}', 'Juz $juz'),
      first: range.first,
      last: range.last,
    );
  }

  Future<void> _pickPage() async {
    final controller = TextEditingController();
    final page = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('تحميل صفحة', 'Download a page')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.tr('رقم الصفحة (١–٦٠٤)', 'Page number (1–604)'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim().replaceAllMapped(
                RegExp('[٠-٩]'),
                (m) => '${m.group(0)!.codeUnitAt(0) - 0x0660}',
              );
              Navigator.pop(dialogContext, int.tryParse(text));
            },
            child: Text(context.tr('تحميل', 'Download')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (page == null || !mounted) return;
    if (page < 1 || page > 604) {
      _snack(
        context.tr(
          'رقم الصفحة يجب أن يكون بين ١ و٦٠٤',
          'Page must be between 1 and 604',
        ),
      );
      return;
    }
    final repository = await ref.read(quranRepositoryProvider.future);
    final range = repository.rangeOfPage(page);
    if (!mounted) return;
    await _startDownload(
      label: context.tr('الصفحة ${context.digits(page)}', 'Page $page'),
      first: range.first,
      last: range.last,
    );
  }

  Future<void> _deleteAll() async {
    final reciter = ref.read(quranReciterProvider);
    final name = reciter.name(arabic: context.isArabic);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.tr('حذف تحميلات القارئ؟', 'Delete reciter downloads?'),
        ),
        content: Text(
          context.tr(
            'ستُحذف كل ملفات $name من جهازك.',
            'All files of $name will be removed from your device.',
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
    if (confirmed != true || !mounted) return;
    final deleted = context.tr(
      'حُذفت تحميلات $name',
      'Deleted downloads of $name',
    );
    await ref.read(quranAudioRepositoryProvider).deleteAll();
    ref.invalidate(downloadedIdsProvider(reciter.id));
    _snack(deleted);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// «٣٥٠ م.ب» أو «١٫٩ ج.ب» حسب الحجم.
  String _formatSize(double megabytes) {
    if (megabytes >= 1024) {
      final gb = (megabytes / 1024).toStringAsFixed(1);
      return context.tr('${context.digits(gb)} ج.ب', '$gb GB');
    }
    final mb = megabytes.toStringAsFixed(0);
    return context.tr('${context.digits(mb)} م.ب', '$mb MB');
  }

  @override
  Widget build(BuildContext context) {
    final reciter = ref.watch(quranReciterProvider);
    final downloaded = ref.watch(downloadedIdsProvider(reciter.id));
    final job = ref.watch(downloadManagerProvider);
    final busy = job != null;
    final arabic = context.isArabic;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('التحميلات', 'Downloads'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _SectionCard(
            title: context.tr('القارئ', 'Reciter'),
            icon: Icons.record_voice_over_outlined,
            children: [
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(reciter.name(arabic: arabic)),
                subtitle: Text(reciter.subtitle),
                trailing: Text(context.tr('تغيير', 'Change')),
                onTap: busy ? null : () => showReciterPicker(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: context.tr('ماذا تريد أن تحمّل؟', 'What to download?'),
            icon: Icons.download_outlined,
            children: [
              _DownloadTile(
                title: context.tr('المصحف كاملاً', 'Whole Quran'),
                subtitle: context.tr(
                  '${context.digits(_totalAyahs)} آية',
                  '$_totalAyahs ayahs',
                ),
                icon: Icons.menu_book,
                enabled: !busy,
                onTap: () => _startDownload(
                  label: context.tr('المصحف كاملاً', 'Whole Quran'),
                  first: 1,
                  last: _totalAyahs,
                ),
              ),
              _DownloadTile(
                title: context.tr('جزء', 'Juz'),
                subtitle: context.tr('${context.digits(30)} جزءاً', '30 parts'),
                icon: Icons.bookmark_border,
                enabled: !busy,
                onTap: _pickJuz,
              ),
              _DownloadTile(
                title: context.tr('سورة', 'Surah'),
                subtitle: context.tr(
                  '${context.digits(114)} سورة',
                  '114 surahs',
                ),
                icon: Icons.auto_stories_outlined,
                enabled: !busy,
                onTap: _pickSurah,
              ),
              _DownloadTile(
                title: context.tr('صفحة', 'Page'),
                subtitle: context.tr(
                  '${context.digits(604)} صفحات',
                  '604 pages',
                ),
                icon: Icons.description_outlined,
                enabled: !busy,
                onTap: _pickPage,
              ),
            ],
          ),
          if (job != null) ...[
            const SizedBox(height: 12),
            _ProgressCard(
              job: job,
              onCancel: () =>
                  ref.read(downloadManagerProvider.notifier).cancel(),
            ),
          ],
          const SizedBox(height: 12),
          _SectionCard(
            title: context.tr('المحمّل على جهازك', 'On your device'),
            icon: Icons.sd_storage_outlined,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
                child: downloaded.when(
                  loading: () => Text(context.tr('جارٍ الفحص…', 'Checking…')),
                  error: (error, _) => Text('$error'),
                  data: (ids) => Text(
                    ids.isEmpty
                        ? context.tr(
                            'لا توجد تلاوات محمّلة لهذا القارئ.',
                            'No downloads for this reciter.',
                          )
                        : context.tr(
                            '${context.digits(ids.length)} آية محمّلة (≈ ${_formatSize(ref.read(quranAudioRepositoryProvider).estimatedMegabytes(ids.length))})',
                            '${ids.length} ayahs downloaded (≈ ${_formatSize(ref.read(quranAudioRepositoryProvider).estimatedMegabytes(ids.length))})',
                          ),
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _deleteAll,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(
                    context.tr(
                      'حذف تحميلات هذا القارئ',
                      'Delete this reciter\'s downloads',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            context.tr(
              'التحميل اختياري ويعمل بعد ذلك بلا إنترنت. الملفات تُحفظ على جهازك ولا تُرسل لأي سيرفر.',
              'Downloads are optional and then work offline. Files stay on your device.',
            ),
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.secondary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(
        icon,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_left, size: 18),
      onTap: enabled ? onTap : null,
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.job, required this.onCancel});

  final DownloadJob job;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr(
                      'جارٍ تحميل ${job.label}',
                      'Downloading ${job.label}',
                    ),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${context.digits(job.done)} / ${context.digits(job.total)}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: job.progress, minHeight: 6),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: job.cancelled ? null : onCancel,
                icon: const Icon(Icons.close, size: 16),
                label: Text(
                  job.cancelled
                      ? context.tr('جارٍ الإيقاف…', 'Stopping…')
                      : context.tr('إيقاف', 'Stop'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ورقة اختيار عامة (سور/أجزاء).
class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({required this.title, required this.items});

  final String title;
  final List<({T value, String title, String? subtitle})> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.title),
                  subtitle: item.subtitle == null ? null : Text(item.subtitle!),
                  onTap: () => Navigator.pop(context, item.value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
