import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:yousuf/core/platform/quran_recognizer.dart';
import 'package:yousuf/core/platform/speech_channel.dart';
import 'package:yousuf/core/utils/quran_text.dart';

import '../../adhkar/presentation/adhkar_providers.dart';
import '../../quran/domain/encouragement.dart';
import '../../quran/domain/quran_models.dart';
import '../../quran/domain/recitation_matcher.dart';
import '../../quran/presentation/quran_player.dart';
import '../../quran/presentation/quran_providers.dart';
import '../../quran/domain/quran_reciter.dart';
import 'kids_providers.dart';

/// رقم آية بالأرقام المشرقية (عُرف المصاحف).
String _ayahNumber(int n) => '$n'.replaceAllMapped(
  RegExp('[0-9]'),
  (m) => String.fromCharCode(0x0660 + int.parse(m.group(0)!)),
);

/// فهرس القرآن للطفل: كل السور الـ114 موزّعة على ثلاثين جزءاً (جزء عمّ أولاً).
class KidQuranBrowserScreen extends ConsumerStatefulWidget {
  const KidQuranBrowserScreen({super.key});

  @override
  ConsumerState<KidQuranBrowserScreen> createState() =>
      _KidQuranBrowserScreenState();
}

class _KidQuranBrowserScreenState extends ConsumerState<KidQuranBrowserScreen> {
  /// الجزء المختار — null يعني كل السور.
  int? _juz;

  @override
  Widget build(BuildContext context) {
    final surahsAsync = ref.watch(surahsProvider);
    final startsAsync = ref.watch(surahStartJuzProvider);
    final progress = ref.watch(kidProgressProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('القرآن الكريم', 'The Holy Quran')),
        actions: const [_KidReciterButton()],
      ),
      body: surahsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (surahs) {
          final starts = startsAsync.value ?? const <int, int>{};
          final list = _juz == null
              ? surahs
              : surahs
                    .where((surah) => starts[surah.id] == _juz)
                    .toList(growable: false);
          return Column(
            children: [
              SizedBox(
                height: 54,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _JuzChip(
                      label: context.tr('كل السور', 'All surahs'),
                      selected: _juz == null,
                      onTap: () => setState(() => _juz = null),
                    ),
                    // جزء عمّ أولاً: الأطفال يبدؤون الحفظ من آخر المصحف.
                    for (var juz = 30; juz >= 1; juz--)
                      _JuzChip(
                        label: context.digits(juz),
                        selected: _juz == juz,
                        onTap: () => setState(() => _juz = juz),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Row(
                  children: [
                    Text(
                      _juz == null
                          ? context.tr('كل السور', 'All surahs')
                          : context.tr(
                              'سور الجزء ${context.digits(_juz!)}',
                              'Juz $_juz surahs',
                            ),
                      style: theme.textTheme.titleSmall,
                    ),
                    const Spacer(),
                    Text(
                      context.tr(
                        '${context.digits(list.length)} سورة',
                        '${list.length} surahs',
                      ),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final surah = list[index];
                    final done = progress.isDone(surah.id);
                    return Material(
                      color: scheme.surfaceContainerLow,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: done ? scheme.primary : scheme.outlineVariant,
                        ),
                      ),
                      child: ListTile(
                        leading: Text(
                          done ? '⭐' : '📖',
                          style: const TextStyle(fontSize: 24),
                        ),
                        title: Text(
                          surah.nameAr,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFamily: 'Amiri',
                          ),
                        ),
                        subtitle: Text(
                          context.tr(
                            '${context.digits(surah.ayahCount)} آية · الجزء ${context.digits(starts[surah.id] ?? 1)}',
                            '${surah.ayahCount} ayahs · juz ${starts[surah.id] ?? 1}',
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_left, size: 18),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                KidSurahMemorizeScreen(surah: surah),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _JuzChip extends StatelessWidget {
  const _JuzChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

/// زر اختيار قارئ الأطفال (المصحف المعلّم).
class _KidReciterButton extends ConsumerWidget {
  const _KidReciterButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: context.tr('القارئ المعلّم', 'Teaching reciter'),
      icon: const Icon(Icons.record_voice_over_outlined),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (_) => const KidReciterSheet(),
      ),
    );
  }
}

/// ورقة قارئ الأطفال: الحصري (المصحف المعلّم) أو المنشاوي مع ترديد الأطفال.
class KidReciterSheet extends ConsumerWidget {
  const KidReciterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(kidReciterProvider);
    final arabic = context.isArabic;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              context.tr(
                'اختر القارئ المعلّم — التلاوة تُحمَّل عند الاستماع وتبقى على الجهاز',
                'Choose the teaching reciter — audio downloads as you listen and stays on the device',
              ),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          for (final reciter in kTeacherReciters)
            ListTile(
              leading: Icon(
                current.id == reciter.id
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(reciter.name(arabic: arabic)),
              subtitle: Text(reciter.subtitle),
              onTap: () async {
                await ref.read(kidReciterProvider.notifier).select(reciter);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// التسميع: نص السورة مخفي إلا أرقام الآيات؛ الطفل يقرأ الآية من حفظه
/// فإن صحّت ظهرت وأخذ نجمة ⭐، وإذا سمّع كل آيات السورة نال نجمة الإتمام.
class KidSurahMemorizeScreen extends ConsumerStatefulWidget {
  const KidSurahMemorizeScreen({super.key, required this.surah});

  final Surah surah;

  @override
  ConsumerState<KidSurahMemorizeScreen> createState() =>
      _KidSurahMemorizeScreenState();
}

class _KidSurahMemorizeScreenState
    extends ConsumerState<KidSurahMemorizeScreen> {
  /// وضع التسميع: النص مخفي إلا الأرقام حتى يُقرأ صحيحاً. وإلا وضع القراءة
  /// والاستماع: الآيات ظاهرة.
  bool _reciteMode = false;

  /// يُلتقط مبكراً: لا يجوز استخدام ref داخل dispose.
  late final QuranPlayerNotifier _playerNotifier = ref.read(
    quranPlayerProvider.notifier,
  );

  @override
  void initState() {
    super.initState();
    _playerNotifier; // تهيئة مبكرة
  }

  /// التعرّف على التلاوة بنموذج قرآني على الجهاز (whisper.cpp).
  final QuranRecognizer _speech = QuranRecognizer();

  /// آيات كُشفت في هذه الجلسة (بالتسميع أو «اكشف»).
  final Set<int> _revealed = <int>{};

  StreamSubscription<SpeechEvent>? _speechSub;
  int? _listeningId;
  Ayah? _target;
  bool _speechChecked = false;
  bool _speechAvailable = true;
  bool _speechDownloadable = false;
  String? _banner;
  bool _praise = false;
  int _attempts = 0;
  bool _downloading = false;
  double _downloadProgress = 0;

  @override
  void dispose() {
    _speechSub?.cancel();
    unawaited(_speech.release());
    // الصوت في المشغّل العام؛ نوقفه عند مغادرة الشاشة إن كان يتلو آية الطفل.
    unawaited(_playerNotifier.stopIfSurah(widget.surah.id));
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------- التلاوة (استماع بصوت المعلّم) ----------------

  Future<void> _play(Ayah ayah) async {
    final player = ref.read(quranPlayerProvider.notifier);
    final playback = ref.read(quranPlayerProvider);
    if (playback.ayah?.id == ayah.id && playback.active) {
      await player.togglePause();
      return;
    }
    final failed = context.tr(
      'تعذر تشغيل التلاوة — تحقق من الإنترنت',
      'Could not play — check your connection',
    );
    // مشغّل واحد للتطبيق كله (just_audio_background) بصوت القارئ المعلّم.
    final ok = await player.playSingle(
      ayah,
      ref.read(kidAudioRepositoryProvider),
    );
    if (!ok) _snack(failed);
  }

  /// تحميل السورة كاملة بصوت المعلّم (للاستماع بلا إنترنت).
  Future<void> _downloadSurah(List<Ayah> ayat) async {
    if (_downloading || ayat.isEmpty) return;
    final done = context.tr('حُمّلت السورة ✓', 'Surah downloaded ✓');
    final failed = context.tr(
      'تعذر تحميل بعض الآيات',
      'Some ayahs failed to download',
    );
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });
    try {
      await ref
          .read(kidAudioRepositoryProvider)
          .downloadRange(
            ayat.first.id,
            ayat.last.id,
            onProgress: (completed, total) {
              if (mounted)
                setState(() => _downloadProgress = completed / total);
            },
          );
      _snack(done);
    } catch (_) {
      _snack(failed);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  // ---------------- التسميع ----------------

  Future<void> _ensureSpeech() async {
    if (_speechChecked) return;
    _speechChecked = true;
    final availability = await _speech.availability();
    if (!mounted) return;
    setState(() {
      _speechAvailable = availability.available;
      _speechDownloadable = availability.downloadable;
      if (!availability.available) {
        final message = speechUnavailableMessage(availability);
        _banner = context.tr(message.ar, message.en);
      }
    });
  }

  Future<void> _downloadArabic() async {
    setState(() {
      _speechDownloadable = false;
      _banner = context.tr(
        'جارٍ تنزيل نموذج التسميع…',
        'Downloading the recitation model…',
      );
    });
    final ok = await QuranRecognizer.downloadModel(
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _banner = context.tr(
            'جارٍ تنزيل نموذج التسميع… ${context.digits((progress * 100).round())}%',
            'Downloading the recitation model… ${(progress * 100).round()}%',
          );
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _banner = ok
          ? context.tr('جاهز! اضغط 🎤 واقرأ الآية', 'Ready! Tap 🎤 and recite')
          : context.tr(
              'تعذر التنزيل — اطلب من الكبار التحقق من الإنترنت',
              'Download failed — ask a grown-up to check the internet',
            );
      _speechChecked = false;
      _speechAvailable = ok || _speechAvailable;
      _speechDownloadable = !ok;
    });
  }

  Future<void> _listenFor(Ayah ayah) async {
    if (_listeningId == ayah.id) {
      await _stopListening();
      return;
    }
    await _ensureSpeech();
    if (!mounted || !_speechAvailable) return;
    setState(() {
      _target = ayah;
      _listeningId = ayah.id;
      _praise = false;
      _banner = context.tr(
        'أسمعك… اقرأ الآية ${context.digits(ayah.number)}',
        'Listening… recite ayah ${ayah.number}',
      );
    });
    _speechSub ??= _speech.events.listen(_onSpeechEvent);
    final started = await _speech.start();
    if (!mounted) return;
    if (!started) {
      setState(() {
        _listeningId = null;
        _banner = context.tr(
          'تعذّر تشغيل الميكروفون — حاول مرة أخرى',
          'Could not start the microphone — try again',
        );
      });
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted && _listeningId != null) setState(() => _listeningId = null);
  }

  void _onSpeechEvent(SpeechEvent event) {
    if (!mounted) return;
    if (event.isError) {
      setState(() {
        _listeningId = null;
        _praise = false;
        _banner = switch (event.code) {
          'permission' => context.tr(
            'نحتاج إذن الميكروفون — اسمح به ثم حاول',
            'Microphone permission is needed',
          ),
          'unavailable' => context.tr(
            'محرّك التعرّف غير متاح — استخدم «اكشف»',
            'Recognizer unavailable — use “Reveal”',
          ),
          'language' || 'language_download' => context.tr(
            'نموذج التسميع غير موجود — نزّله أولاً',
            'Recitation model missing — download it first',
          ),
          'no_match' || 'timeout' => pickPhrase(kidRetryPhrases, ++_attempts),
          _ => context.tr(
            'تعذّر الاستماع — حاول مرة أخرى',
            'Could not listen — try again',
          ),
        };
      });
      return;
    }
    if (event.type == SpeechEventKind.speechEnd) {
      setState(() {
        _listeningId = null;
        _banner = context.tr(
          'لحظة… نتحقق من تلاوتك',
          'One moment… checking your recitation',
        );
      });
    }
    if (event.type == SpeechEventKind.finalResult) {
      setState(() => _listeningId = null);
    }
    if (!event.isText) return;
    final target = _target;
    if (target == null) return;

    final result = evaluateRecitation(
      heard: event.text,
      ayahText: target.text,
      threshold: 0.55,
    );
    if (result.passed) {
      unawaited(HapticFeedback.mediumImpact());
      unawaited(_speech.stop());
      unawaited(_onRecited(target));
    } else if (event.type == SpeechEventKind.finalResult) {
      setState(() {
        _praise = false;
        _banner = pickPhrase(kidRetryPhrases, ++_attempts);
      });
    }
  }

  /// آية صحيحة: تظهر + نجمة (أول مرة) + إتمام السورة إن اكتملت.
  Future<void> _onRecited(Ayah ayah) async {
    final newStar = await ref
        .read(kidProgressProvider.notifier)
        .memorize(ayah.id);
    if (!mounted) return;
    setState(() {
      _revealed.add(ayah.id);
      _listeningId = null;
      _praise = true;
      _attempts = 0;
      _banner = newStar
          ? '${pickPhrase(kidPraisePhrases, _revealed.length)} ⭐+${context.digits(1)}'
          : pickPhrase(kidPraisePhrases, _revealed.length);
    });
    await _checkCompletion();
  }

  Future<void> _checkCompletion() async {
    final repository = await ref.read(quranRepositoryProvider.future);
    final ayat = repository.ayatOfSurah(widget.surah.id);
    final progress = ref.read(kidProgressProvider);
    if (!ayat.every((a) => progress.isMemorized(a.id))) return;
    final isNew = await ref
        .read(kidProgressProvider.notifier)
        .completeSurah(widget.surah.id);
    if (!isNew || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('نجمة الإتمام! 🌟', 'Completion star! 🌟')),
        content: Text(
          context.tr(
            'سمّعت سورة ${widget.surah.nameAr} كاملة. بارك الله فيك!',
            'You recited Surah ${widget.surah.nameAr} by heart. May Allah bless you!',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('الحمد لله', 'Alhamdulillah')),
          ),
        ],
      ),
    );
  }

  void _revealAll(List<Ayah> ayat) {
    setState(() {
      _revealed.addAll(ayat.map((ayah) => ayah.id));
      _banner = context.tr(
        'كُشفت السورة — النجوم تُكسب بالتسميع فقط',
        'Surah revealed — stars are earned only by reciting',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final repositoryAsync = ref.watch(quranRepositoryProvider);
    final progress = ref.watch(kidProgressProvider);
    final reciter = ref.watch(kidReciterProvider);
    final playback = ref.watch(quranPlayerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final alreadyDone = progress.isDone(widget.surah.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.surah.nameAr,
          style: const TextStyle(fontFamily: 'Amiri'),
        ),
        bottom: _downloading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  minHeight: 3,
                ),
              )
            : null,
        actions: [
          if (alreadyDone)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 4),
              child: Center(child: Text('🌟', style: TextStyle(fontSize: 20))),
            ),
          const _KidReciterButton(),
        ],
      ),
      body: repositoryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (repository) {
          final ayat = repository.ayatOfSurah(widget.surah.id);
          final memorized = ayat
              .where((a) => progress.isMemorized(a.id))
              .length;
          return Column(
            children: [
              Material(
                color: _praise
                    ? scheme.primaryContainer
                    : scheme.surfaceContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Icon(
                        _praise ? Icons.star : Icons.mic_none,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _banner ??
                              (_reciteMode
                                  ? context.tr(
                                      'الصفحة ممسوحة — اقرأ كل آية من حفظك لتظهر وتأخذ نجمة ⭐',
                                      'The page is hidden — recite each ayah by heart to reveal it and earn a star ⭐',
                                    )
                                  : context.tr(
                                      'استمع للآية ورددها، وحين تحفظها اختر «تسميع» لتأخذ النجوم',
                                      'Listen and repeat; when you know it, switch to “Recite” to earn stars',
                                    )),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: _praise
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (_speechDownloadable)
                        TextButton(
                          onPressed: _downloadArabic,
                          child: Text(
                            context.tr('تنزيل النموذج', 'Download model'),
                          ),
                        ),
                      if (!_speechAvailable)
                        TextButton(
                          onPressed: () => _revealAll(ayat),
                          child: Text(context.tr('اكشف', 'Reveal')),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: Text(context.tr('قراءة واستماع', 'Read & listen')),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.mic_none, size: 18),
                      label: Text(context.tr('تسميع ⭐', 'Recite ⭐')),
                    ),
                  ],
                  selected: {_reciteMode},
                  onSelectionChanged: (value) => setState(() {
                    _reciteMode = value.first;
                    _revealed.clear();
                    _praise = false;
                    _banner = null;
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
                child: Row(
                  children: [
                    Text(
                      context.tr(
                        '⭐ ${context.digits(memorized)} من ${context.digits(ayat.length)}',
                        '⭐ $memorized of ${ayat.length}',
                      ),
                      style: theme.textTheme.titleSmall,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _downloading
                          ? null
                          : () => _downloadSurah(ayat),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(
                        context.tr(
                          'تحميل بصوت ${reciter.nameAr.split(' — ').first}',
                          'Download (${reciter.nameEn})',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: ayat.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final ayah = ayat[index];
                    final star = progress.isMemorized(ayah.id);
                    final playing =
                        playback.ayah?.id == ayah.id && playback.playing;
                    final listening = _listeningId == ayah.id;
                    final revealed =
                        !_reciteMode || _revealed.contains(ayah.id);
                    return Material(
                      color: scheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: star ? scheme.primary : scheme.outlineVariant,
                          width: star ? 1.6 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (revealed)
                              Text(
                                '${quranFontText(displayQuranText(ayah.text))}${ayahMark(ayah.number)}',
                                textDirection: TextDirection.rtl,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontFamily: AppTheme.quranFont,
                                  fontFamilyFallback: AppTheme.quranFallback,
                                  fontSize: 22,
                                  height: 2,
                                ),
                              )
                            else
                              Row(
                                children: [
                                  Text(
                                    '﴿${_ayahNumber(ayah.number)}﴾',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontFamily: 'Amiri',
                                          color: scheme.secondary,
                                        ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      listening
                                          ? context.tr(
                                              'أسمعك… أكمل الآية',
                                              'Listening… keep going',
                                            )
                                          : context.tr(
                                              'اقرأ الآية ثم اضغط 🎤',
                                              'Recite, then press 🎤',
                                            ),
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            Row(
                              children: [
                                IconButton(
                                  tooltip: context.tr('استمع', 'Listen'),
                                  onPressed:
                                      playback.loading &&
                                          playback.ayah?.id == ayah.id
                                      ? null
                                      : () => _play(ayah),
                                  icon: Icon(
                                    playing
                                        ? Icons.pause_circle_outline
                                        : Icons.play_circle_outline,
                                    color: scheme.primary,
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.tr('اقرأ بصوتك', 'Recite'),
                                  onPressed: () => _listenFor(ayah),
                                  icon: Icon(
                                    listening
                                        ? Icons.stop_circle_outlined
                                        : Icons.mic,
                                    color: listening
                                        ? scheme.secondary
                                        : scheme.primary,
                                  ),
                                ),
                                Text(
                                  context.tr(
                                    'آية ${context.digits(ayah.number)}',
                                    'Ayah ${ayah.number}',
                                  ),
                                  style: theme.textTheme.labelSmall,
                                ),
                                const Spacer(),
                                if (star)
                                  const Text(
                                    '⭐',
                                    style: TextStyle(fontSize: 20),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// أذكار الطفل: أذكار الصباح بخط كبير وبطاقات بسيطة.
class KidAdhkarScreen extends ConsumerWidget {
  const KidAdhkarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(adhkarCategoriesProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('أذكار الطفل', 'Kids adhkar'))),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (categories) {
          final morning = categories
              .where((category) => category.slug == 'morning')
              .firstOrNull;
          if (morning == null) {
            return Center(
              child: Text(context.tr('لا توجد أذكار بعد', 'No adhkar yet')),
            );
          }
          final dhikrAsync = ref.watch(adhkarOfCategoryProvider(morning.id));
          return dhikrAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('$error')),
            data: (dhikr) {
              if (dhikr.isEmpty) {
                return Center(
                  child: Text(context.tr('لا توجد أذكار بعد', 'No adhkar yet')),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                itemCount: dhikr.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = dhikr[index];
                  return Material(
                    color: scheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            item.text,
                            textDirection: TextDirection.rtl,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontFamily: AppTheme.quranFont,
                                  fontFamilyFallback: AppTheme.quranFallback,
                                  fontSize: 22,
                                  height: 2,
                                ),
                          ),
                          if (item.instruction != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              item.instruction!,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: scheme.secondary),
                            ),
                          ],
                          if (item.source != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              item.source!,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
