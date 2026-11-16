import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';

import '../../quran/presentation/quran_player.dart';
import '../data/tuhfa_repository.dart';

const _reciter = 'محمد عبد الرحمن الحوفي';

/// «تحفة الأطفال»: أبواب المتن، ولكل باب أبياته وصوته.
class TuhfaScreen extends ConsumerWidget {
  const TuhfaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sectionsAsync = ref.watch(tuhfaProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('تحفة الأطفال', 'Tuhfat al-Atfal')),
      ),
      body: sectionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (sections) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              context.tr(
                'منظومة في أحكام التجويد للشيخ سليمان الجمزوري — ٦١ بيتاً',
                'A poem on tajweed rules by Sulayman al-Jamzuri — 61 verses',
              ),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            _AudioButton(
              audio: tuhfaAudioFor(0)!,
              label: context.tr(
                'استمع للمتن كاملاً',
                'Listen to the whole poem',
              ),
            ),
            const SizedBox(height: 8),
            for (final section in sections)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(context.digits(section.id)),
                  ),
                  title: Text(
                    section.title,
                    style: const TextStyle(fontFamily: 'Amiri', fontSize: 18),
                  ),
                  subtitle: Text(
                    context.tr(
                      'الأبيات ${context.digits(section.verses.first.number)}–${context.digits(section.verses.last.number)}',
                      'Verses ${section.verses.first.number}–${section.verses.last.number}',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TuhfaSectionScreen(section: section),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                'النص من ويكي مصدر (CC BY-SA). الأداء بصوت $_reciter (archive.org).',
                'Text: Arabic Wikisource (CC BY-SA). Recited by $_reciter (archive.org).',
              ),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// أبيات باب واحد بخط كبير، مع صوته.
class TuhfaSectionScreen extends StatelessWidget {
  const TuhfaSectionScreen({super.key, required this.section});

  final TuhfaSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleLarge?.copyWith(
      fontFamily: 'Amiri',
      height: 1.9,
    );
    final audio = tuhfaAudioFor(section.id);
    return Scaffold(
      appBar: AppBar(title: Text(section.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (audio != null) ...[
            _AudioButton(
              audio: audio,
              label: context.tr('استمع لهذا الباب', 'Listen to this section'),
            ),
            const SizedBox(height: 12),
          ],
          for (final verse in section.verses)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    Text(
                      verse.line1,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: style,
                    ),
                    Text(
                      verse.line2,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: style,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.digits(verse.number),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// زر الصوت: تنزيل (مع الحجم) ← تشغيل ← إيقاف.
class _AudioButton extends ConsumerWidget {
  const _AudioButton({required this.audio, required this.label});

  final TuhfaAudio audio;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded =
        ref.watch(tuhfaDownloadedProvider).value ?? const <int>{};
    final progress = ref.watch(tuhfaDownloadsProvider)[audio.section];
    final playback = ref.watch(quranPlayerProvider);
    final id = 'tuhfa/${audio.section}';
    final playing = playback.clip == id;

    if (progress != null) {
      return FilledButton.tonalIcon(
        onPressed: null,
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            value: progress > 0 ? progress : null,
            strokeWidth: 2.5,
          ),
        ),
        label: Text(context.tr('جارٍ التنزيل…', 'Downloading…')),
      );
    }
    if (!downloaded.contains(audio.section)) {
      final size = (audio.bytes / 1048576).toStringAsFixed(1);
      return FilledButton.tonalIcon(
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final failed = context.tr(
            'تعذّر التنزيل — تحقق من الاتصال',
            'Download failed — check your connection',
          );
          try {
            await ref.read(tuhfaDownloadsProvider.notifier).download(audio);
          } catch (_) {
            messenger.showSnackBar(SnackBar(content: Text(failed)));
          }
        },
        icon: const Icon(Icons.download_outlined),
        label: Text(
          context.tr(
            '$label · تنزيل ${context.digits(size)} م.ب',
            '$label · download $size MB',
          ),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: () async {
        final player = ref.read(quranPlayerProvider.notifier);
        if (playing) {
          await player.stop();
          return;
        }
        final file = await TuhfaAudioStore.fileFor(audio);
        await player.playClip(
          id: id,
          path: file.path,
          title: 'تحفة الأطفال',
          artist: _reciter,
        );
      },
      icon: Icon(playing ? Icons.stop : Icons.play_arrow),
      label: Text(playing ? context.tr('إيقاف', 'Stop') : label),
    );
  }
}
