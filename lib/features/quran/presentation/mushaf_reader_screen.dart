import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:yousuf/core/platform/quran_recognizer.dart';
import 'package:yousuf/core/platform/speech_channel.dart';
import 'package:yousuf/core/share/share_card.dart';
import 'package:yousuf/core/utils/quran_text.dart';

import '../../khatma/presentation/khatma_providers.dart';
import '../domain/encouragement.dart';
import '../domain/quran_models.dart';
import '../domain/recitation_matcher.dart';
import 'download_manager.dart';
import 'hifz_providers.dart';
import 'mushaf_ornate.dart';
import 'mushaf_style.dart';
import 'ayah_study_screen.dart';
import 'quran_player.dart';
import 'quran_providers.dart';
import 'reciter_picker.dart';

/// تخطيط صفحة المصحف — مثل «مصحف التهجد الكبير»: الصفحة نفسها
/// (نفس الكلمات في السطر) لكنها تملأ العرض المتاح والخط يكبر معها.
///
/// المرجع 420 نقطة: عليه حجم الخط 23. كل زيادة في العرض تكبّر الخط
/// بنفس النسبة، فلا تتغيّر كلمات السطر — تبقى الصفحة هي الصفحة.
({double pageWidth, double fontScale}) mushafLayout({
  required double width,
  required double height,
}) {
  const baseWidth = 420.0;
  final scale = (width / baseWidth).clamp(1.0, 2.2);
  return (pageWidth: width, fontScale: scale);
}

/// عدد صفحات المصحف (ثابت: مصحف المدينة 604).
class QuranReaderPageCount {
  QuranReaderPageCount._();

  static const int total = 604;
}

/// أرقام الآيات في المصحف بالأرقام العربية المشرقية (١٢٣) دائماً — عُرف
/// المصاحف — بغض النظر عن إعداد أرقام الواجهة.
String mushafNumber(int n) => '$n'.replaceAllMapped(
  RegExp('[0-9]'),
  (m) => String.fromCharCode(0x0660 + int.parse(m.group(0)!)),
);

/// البسملة بنص المصحف نفسه (الفاتحة ١:١ من Tanzil) — لا نص مكتوب يدوياً.
final _basmalaProvider = FutureProvider<String>((ref) async {
  final repository = await ref.watch(quranRepositoryProvider.future);
  final text = repository.ayahOf(1, 1)?.text.trim();
  return (text == null ? null : displayQuranText(text)) ??
      'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ';
});

/// نص الآية كما يُرسم في الصفحة (بلا البسملة الملحقة بأول السورة) — نفسه
/// يُقسَّم كلمات للتسميع كلمة بكلمة، فيتطابق الكشف مع الرسم.
String mushafAyahText(Ayah ayah) => quranFontText(
  displayQuranText(
    stripLeadingBasmala(ayah.text, surahId: ayah.surahId, number: ayah.number),
  ),
);

/// قارئ المصحف: 604 صفحة بتقليب يمين→يسار (SPEC §7.3).
///
/// - [highlightAyahId]: يفتح على آية (من العلامات أو البحث) مظلَّلة.
/// - التلاوة عبر [quranPlayerProvider] العام: تستمر بعد إغلاق الشاشة.
/// - المكوث على الصفحة [_dwellToCount] يعدّها مقروءة في الختمة.
class MushafReaderScreen extends ConsumerStatefulWidget {
  const MushafReaderScreen({
    super.key,
    required this.initialPage,
    this.highlightAyahId,
    this.khatmaSession = false,
  });

  final int initialPage;
  final int? highlightAyahId;

  /// جلسة ختمة: الصفحات تُحسب في الختمة فقط هنا (فُتح من شاشة الختمة أو
  /// بطاقتها). القراءة العادية لا تؤثر في تقدّم الختمة.
  final bool khatmaSession;

  @override
  ConsumerState<MushafReaderScreen> createState() => _MushafReaderScreenState();
}

class _MushafReaderScreenState extends ConsumerState<MushafReaderScreen> {
  static const Duration _dwellToCount = Duration(seconds: 20);

  late final PageController _controller;
  late int _currentPage;
  int? _highlightAyahId;

  /// متى فُتحت الصفحة الحالية (لحساب المكوث).
  DateTime _pageOpenedAt = DateTime.now();
  Timer? _dwellTimer;

  /// هل يتبع المصحف الآية المتلوّة؟ يتوقف إن قلّب المستخدم بنفسه.
  bool _followPlayback = true;

  // ---------------- وضع الحفظ: الاستماع والتحقق ----------------

  /// التعرّف على التلاوة بنموذج قرآني على الجهاز (whisper.cpp).
  final QuranRecognizer _speech = QuranRecognizer();
  StreamSubscription<SpeechEvent>? _speechSub;
  final Set<int> _revealed = <int>{};
  bool _listening = false;
  bool _speechChecked = false;
  bool _speechAvailable = true;

  /// هل يمكن تنزيل نموذج التسميع القرآني؟
  bool _speechDownloadable = false;
  String? _hifzMessage;
  int _attempts = 0;
  bool _hifzPraise = false;

  /// التسميع كلمة بكلمة: كلمات بقية الصفحة بالترتيب، وموضع التلاوة فيها.
  /// [visible] = عدد كلمات الآية الظاهرة حين تُتلى هذه الكلمة.
  List<({int ayahId, int visible, String word})> _hifzWords = const [];
  int _hifzPos = 0;
  bool _hifzProgressed = false;

  /// الكلمات المكشوفة من آية لم تكتمل بعد: معرّف الآية ← عدد الكلمات.
  final Map<int, int> _revealedWords = <int, int>{};

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage.clamp(1, QuranReaderPageCount.total);
    _highlightAyahId = widget.highlightAyahId;
    // RTL: التطبيق عربي، فالصفحة 1 في أقصى اليمين والتالية إلى اليسار.
    _controller = PageController(initialPage: _currentPage - 1);
    _startDwell();
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    _speechSub?.cancel();
    unawaited(_speech.release());
    _controller.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------- التقليب والختمة ----------------

  void _startDwell() {
    _pageOpenedAt = DateTime.now();
    _dwellTimer?.cancel();
    if (!widget.khatmaSession) return;
    final page = _currentPage;
    _dwellTimer = Timer(_dwellToCount, () {
      if (mounted && _currentPage == page) {
        unawaited(ref.read(khatmaReadProvider.notifier).mark([page]));
      }
    });
  }

  void _onPageChanged(int index) {
    final page = index + 1;
    // قراءة متتابعة للأمام بعد مكوث معقول تُحسب للصفحة السابقة أيضاً.
    final stayed = DateTime.now().difference(_pageOpenedAt);
    if (widget.khatmaSession &&
        page == _currentPage + 1 &&
        stayed >= const Duration(seconds: 8)) {
      unawaited(ref.read(khatmaReadProvider.notifier).mark([_currentPage]));
    }
    setState(() => _currentPage = page);
    _startDwell();
    saveLastReadPage(ref, page);
  }

  void _goTo(int page) {
    final target = page.clamp(1, QuranReaderPageCount.total);
    if (!_controller.hasClients) return;
    _controller.animateToPage(
      target - 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // ---------------- التلاوة ----------------

  Future<void> _playFrom(Ayah ayah) async {
    _followPlayback = true;
    await ref.read(quranPlayerProvider.notifier).playFrom(ayah);
  }

  Future<void> _togglePlay(QuranPage? page) async {
    final playback = ref.read(quranPlayerProvider);
    if (playback.active) {
      await ref.read(quranPlayerProvider.notifier).togglePause();
      return;
    }
    if (page == null || page.ayat.isEmpty) return;
    await _playFrom(page.ayat.first);
  }

  // ---------------- القائمة ----------------

  Future<void> _openMenu(QuranPage? page) async {
    final surahId = page != null && page.ayat.isNotEmpty
        ? page.ayat.first.surahId
        : null;
    final surah = surahId == null
        ? null
        : (await ref.read(quranRepositoryProvider.future)).surah(surahId);
    if (!mounted) return;
    final hasKhatma =
        widget.khatmaSession && ref.read(khatmaPlanProvider) != null;
    final isRead = ref.read(khatmaReadProvider).all.contains(_currentPage);
    final arabic = context.isArabic;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Consumer(
                builder: (context, ref, _) {
                  final hifz = ref.watch(hifzModeProvider);
                  return SwitchListTile(
                    secondary: const Icon(Icons.visibility_off_outlined),
                    title: Text(
                      context.tr('وضع الحفظ والتسميع', 'Memorization mode'),
                    ),
                    subtitle: Text(
                      context.tr(
                        'الصفحة ممسوحة إلا أرقام الآيات، وتظهر الآية حين تقرؤها صحيحة',
                        'Only ayah numbers show; each ayah appears when recited correctly',
                      ),
                    ),
                    value: hifz,
                    onChanged: (_) {
                      Navigator.pop(sheetContext);
                      _toggleHifz();
                    },
                  );
                },
              ),
              if (hasKhatma)
                ListTile(
                  leading: Icon(isRead ? Icons.check_circle : Icons.done),
                  title: Text(
                    isRead
                        ? context.tr(
                            'الصفحة محسوبة في الختمة',
                            'Page counted in khatma',
                          )
                        : context.tr('علّم الصفحة مقروءة', 'Mark page as read'),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    final notifier = ref.read(khatmaReadProvider.notifier);
                    unawaited(
                      isRead
                          ? notifier.unmark(_currentPage)
                          : notifier.mark([_currentPage]),
                    );
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.record_voice_over_outlined),
                title: Text(
                  ref.read(quranReciterProvider).name(arabic: arabic),
                ),
                subtitle: Text(context.tr('تغيير القارئ', 'Change reciter')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showReciterPicker(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(context.tr('تحميل السورة', 'Download surah')),
                subtitle: Text(surah?.nameAr ?? ''),
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (surahId != null) _downloadSurah(surahId, surah?.nameAr);
                },
              ),
              ListTile(
                leading: const Icon(Icons.audio_file_outlined),
                title: Text(
                  context.tr('تحميل هذه الصفحة', 'Download this page'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _downloadPage(_currentPage);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined),
                title: Text(context.tr('مركز التحميلات', 'Downloads')),
                subtitle: Text(
                  context.tr('المصحف كاملاً أو أجزاء', 'Whole Quran or parts'),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/downloads');
                },
              ),
              Consumer(
                builder: (context, ref, _) => SwitchListTile(
                  secondary: const Icon(Icons.save_alt),
                  title: Text(
                    context.tr('الحفظ أثناء التلاوة', 'Save while playing'),
                  ),
                  subtitle: Text(
                    context.tr(
                      'يبثّ الآية فوراً ويحفظها على الجهاز',
                      'Streams the ayah and saves it on the device',
                    ),
                  ),
                  value: ref.watch(cacheWhilePlayingProvider),
                  onChanged: (value) =>
                      ref.read(cacheWhilePlayingProvider.notifier).set(value),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: Text(context.tr('شكل الصفحة', 'Page style')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openStylePicker();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openStylePicker() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // الورقة قد تطول عن الشاشة (خاصة مع خط النظام الكبير) ⇒ تُمرَّر.
    isScrollControlled: true,
    builder: (_) => const _StylePickerSheet(),
  );

  // ---------------- التحميل ----------------

  Future<void> _downloadSurah(int surahId, String? name) async {
    final repository = await ref.read(quranRepositoryProvider.future);
    final range = repository.rangeOfSurah(surahId);
    if (!mounted) return;
    await _downloadRange(
      label: context.tr('سورة ${name ?? ''}', 'Surah ${name ?? ''}'),
      first: range.first,
      last: range.last,
    );
  }

  Future<void> _downloadPage(int pageNumber) async {
    final repository = await ref.read(quranRepositoryProvider.future);
    final range = repository.rangeOfPage(pageNumber);
    if (!mounted) return;
    await _downloadRange(
      label: context.tr(
        'صفحة ${context.digits(pageNumber)}',
        'Page $pageNumber',
      ),
      first: range.first,
      last: range.last,
    );
  }

  Future<void> _downloadRange({
    required String label,
    required int first,
    required int last,
  }) async {
    final count = last - first + 1;
    if (count <= 0 || ref.read(downloadManagerProvider) != null) return;
    final audio = ref.read(quranAudioRepositoryProvider);
    final estimated = audio.estimatedMegabytes(count);
    final size = estimated >= 1024
        ? context.tr(
            '${context.digits((estimated / 1024).toStringAsFixed(1))} ج.ب',
            '${(estimated / 1024).toStringAsFixed(1)} GB',
          )
        : context.tr(
            '${context.digits(estimated.toStringAsFixed(0))} م.ب',
            '${estimated.toStringAsFixed(0)} MB',
          );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('تحميل $label', 'Download $label')),
        content: Text(
          context.tr(
            'القارئ: ${audio.reciter.nameAr}\n${context.digits(count)} آية · الحجم التقديري $size',
            'Reciter: ${audio.reciter.nameEn}\n$count ayahs · about $size',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('تحميل', 'Download')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // التحميل في المدير العام: يستمر بعد إغلاق المصحف (مع إشعار تقدّم).
    unawaited(
      ref
          .read(downloadManagerProvider.notifier)
          .start(label: label, first: first, last: last),
    );
  }

  // ---------------- الواجهة ----------------

  @override
  Widget build(BuildContext context) {
    final pageAsync = ref.watch(quranPageProvider(_currentPage));
    final currentPage = pageAsync.value;
    final hifz = ref.watch(hifzModeProvider);
    final playback = ref.watch(quranPlayerProvider);
    final surahs = ref.watch(surahsProvider).value ?? const <Surah>[];
    final pageAyat = currentPage?.ayat ?? const <Ayah>[];
    final revealedOnPage = pageAyat
        .where((ayah) => _revealed.contains(ayah.id))
        .length;
    final isRead = ref.watch(khatmaReadProvider).all.contains(_currentPage);
    final hasKhatma =
        widget.khatmaSession && ref.watch(khatmaPlanProvider) != null;
    final download = ref.watch(downloadManagerProvider);

    // تتبّع الآية المتلوّة: تقليب الصفحة معها ما لم يقلّب المستخدم بنفسه.
    ref.listen(quranPlayerProvider, (previous, next) {
      final ayah = next.ayah;
      if (ayah == null || ayah.id == previous?.ayah?.id) return;
      if (_followPlayback && ayah.page != _currentPage) _goTo(ayah.page);
      if (next.error != null && next.error != previous?.error) {
        _snack(
          context.tr(next.error!, 'Could not play — check your connection'),
        );
      }
    });

    final surahNames = {
      for (final ayah in pageAyat)
        surahs.where((s) => s.id == ayah.surahId).firstOrNull?.nameAr ?? '',
    }..remove('');
    final juz = pageAyat.firstOrNull?.juz;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              surahNames.isEmpty
                  ? context.tr('المصحف', 'Quran')
                  : surahNames.map((n) => context.tr('سورة $n', n)).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontFamily: 'Amiri'),
            ),
            Text(
              context.tr(
                'الجزء ${context.digits(juz ?? 1)} · صفحة ${context.digits(_currentPage)}',
                'Juz ${juz ?? 1} · page $_currentPage',
              ),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        bottom: download == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: download.total == 0 ? null : download.progress,
                  minHeight: 3,
                ),
              ),
        actions: [
          if (hasKhatma)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 2),
              child: Center(
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  label: Text(
                    context.tr('ختمة', 'Khatma'),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          if (hasKhatma && isRead)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Tooltip(
                message: context.tr('محسوبة في الختمة', 'Counted in khatma'),
                child: Icon(
                  Icons.check_circle,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          IconButton(
            tooltip: playback.playing
                ? context.tr('إيقاف مؤقت', 'Pause')
                : context.tr('استمع', 'Listen'),
            icon: Icon(
              playback.playing
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
            onPressed: currentPage == null
                ? null
                : () => _togglePlay(currentPage),
          ),
          IconButton(
            tooltip: context.tr('خيارات', 'Options'),
            icon: const Icon(Icons.more_vert),
            onPressed: () => _openMenu(currentPage),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: NotificationListener<UserScrollNotification>(
                onNotification: (_) {
                  // تقليب يدوي: لا نسحب المستخدم مع التلاوة.
                  _followPlayback = false;
                  return false;
                },
                child: PageView.builder(
                  controller: _controller,
                  itemCount: QuranReaderPageCount.total,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) => _MushafPage(
                    pageNumber: index + 1,
                    playingAyahId: playback.ayah?.id,
                    highlightAyahId: _highlightAyahId,
                    hifz: hifz,
                    revealed: _revealed,
                    revealedWords: _revealedWords,
                    onAyahTap: _showAyahSheet,
                    onMaskedTap: _hintMic,
                  ),
                ),
              ),
            ),
            if (hifz)
              _HifzBar(
                revealed: revealedOnPage,
                total: pageAyat.length,
                listening: _listening,
                success: _hifzPraise,
                message:
                    _hifzMessage ??
                    context.tr(
                      'اضغط «اقرأ» وتلُ من حفظك — تظهر الكلمات أولاً بأول',
                      'Tap “Recite” — words appear as you recite',
                    ),
                speechAvailable: _speechAvailable,
                onDownload: _speechDownloadable ? _downloadArabic : null,
                onMic: _toggleListening,
                onRevealPage: _revealNext,
                onHideAll: _clearRevealed,
              ),
            if (playback.active)
              _NowPlayingBar(
                playback: playback,
                reciter: ref
                    .watch(quranReciterProvider)
                    .name(arabic: context.isArabic),
                onPlayPause: () =>
                    ref.read(quranPlayerProvider.notifier).togglePause(),
                onNext: () => ref.read(quranPlayerProvider.notifier).next(),
                onPrevious: () =>
                    ref.read(quranPlayerProvider.notifier).previous(),
                onStop: () => ref.read(quranPlayerProvider.notifier).stop(),
                onLocate: () {
                  _followPlayback = true;
                  final page = playback.ayah?.page;
                  if (page != null) _goTo(page);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ---------------- وضع الحفظ ----------------

  void _toggleHifz() {
    final turningOn = !ref.read(hifzModeProvider);
    unawaited(_stopListening());
    setState(() {
      _revealed.clear();
      _revealedWords.clear();
      _hifzWords = const [];
      _hifzPos = 0;
      _hifzMessage = null;
      _hifzPraise = false;
      _attempts = 0;
    });
    ref.read(hifzModeProvider.notifier).toggle();
    if (turningOn) unawaited(_ensureSpeech());
  }

  /// يتحقق من توفّر التعرّف العربي **على الجهاز** ويعرض السبب إن غاب.
  Future<void> _ensureSpeech({bool force = false}) async {
    if (_speechChecked && !force) return;
    _speechChecked = true;
    final availability = await _speech.availability();
    debugPrint(
      '[YousufSpeech] ${availability.reason} locale=${availability.locale}',
    );
    if (!mounted) return;
    setState(() {
      _speechAvailable = availability.available;
      _speechDownloadable = availability.downloadable;
      if (!availability.available) {
        final message = speechUnavailableMessage(availability);
        _hifzMessage = context.tr(message.ar, message.en);
      } else if (force) {
        _hifzMessage = null;
      }
    });
  }

  /// ينزّل نموذج التسميع القرآني (مرة واحدة) مع عرض التقدّم.
  Future<void> _downloadArabic() async {
    setState(() {
      _speechDownloadable = false;
      _hifzMessage = context.tr(
        'جارٍ تنزيل نموذج التسميع…',
        'Downloading the recitation model…',
      );
    });
    final ok = await QuranRecognizer.downloadModel(
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _hifzMessage = context.tr(
            'جارٍ تنزيل نموذج التسميع… ${context.digits((progress * 100).round())}%',
            'Downloading the recitation model… ${(progress * 100).round()}%',
          );
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _hifzMessage = ok
          ? context.tr(
              'اكتمل التنزيل — اضغط «اقرأ» وابدأ التلاوة',
              'Download complete — tap “Recite” and start',
            )
          : context.tr(
              'تعذر تنزيل النموذج — تحقق من الاتصال وأعد المحاولة',
              'Could not download the model — check your connection',
            );
      _speechDownloadable = !ok;
    });
    _speechChecked = false;
    if (ok) _speechAvailable = true;
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stopListening();
      return;
    }
    await _ensureSpeech(force: !_speechAvailable);
    if (!mounted) return;
    // لا تعرّف عربي على الجهاز: الرسالة تشرح السبب، ولا داعي لطلب الميكروفون.
    if (!_speechAvailable) return;
    final page = ref.read(quranPageProvider(_currentPage)).value;
    if (page == null) return;
    final pending = page.ayat
        .where((ayah) => !_revealed.contains(ayah.id))
        .toList();
    final target = pending.firstOrNull;
    if (target == null) {
      _snack(
        context.tr(
          'أتممت هذه الصفحة — اقلب الصفحة أو أعد الإخفاء',
          'Page complete — turn the page or hide again',
        ),
      );
      return;
    }
    // كلمات بقية الصفحة بالترتيب؛ نبدأ بعد ما كُشف من الآية الجارية.
    final words = [
      for (final ayah in pending)
        for (final (index, word) in recitationTokens(
          mushafAyahText(ayah),
        ).indexed)
          (ayahId: ayah.id, visible: index + 1, word: word),
    ];
    var position = 0;
    while (position < words.length &&
        words[position].visible <=
            (_revealedWords[words[position].ayahId] ?? 0)) {
      position++;
    }
    setState(() {
      _hifzWords = words;
      _hifzPos = position;
      _hifzProgressed = false;
      _hifzPraise = false;
      _hifzMessage = context.tr(
        'أستمع إليك… اقرأ من الآية ${context.digits(target.number)} وتظهر الكلمات أولاً بأول',
        'Listening… recite from ayah ${target.number}, words appear as you go',
      );
    });
    _speechSub ??= _speech.events.listen(_onSpeechEvent);
    final started = await _speech.startLive();
    if (!mounted) return;
    setState(() {
      _listening = started;
      if (!started) {
        _hifzMessage = context.tr(
          'تعذّر تشغيل الميكروفون — حاول مرة أخرى',
          'Could not start the microphone — try again',
        );
      }
    });
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (mounted && _listening) setState(() => _listening = false);
  }

  void _onSpeechEvent(SpeechEvent event) {
    if (!mounted) return;
    if (event.isError) {
      setState(() {
        _listening = false;
        switch (event.code) {
          case 'permission':
            _hifzMessage = context.tr(
              'نحتاج إذن الميكروفون — اسمح به ثم أعد المحاولة',
              'Microphone permission is needed',
            );
          case 'unavailable':
            _speechAvailable = false;
            _hifzMessage = context.tr(
              'محرّك التعرّف غير متاح — استخدم «اكشف»',
              'Recognizer unavailable — use “Reveal”',
            );
          case 'language' || 'language_download':
            _speechAvailable = false;
            _hifzMessage = context.tr(
              'نموذج التسميع غير موجود — نزّله أولاً',
              'Recitation model missing — download it first',
            );
          case 'audio':
            _hifzMessage = context.tr(
              'الميكروفون مشغول بتطبيق آخر — أغلقه ثم حاول',
              'The microphone is busy in another app — close it and retry',
            );
          case 'no_match':
          case 'timeout':
            _attempts++;
            _hifzMessage = pickPhrase(adultRetryPhrases, _attempts);
          default:
            _hifzMessage = context.tr(
              'تعذّر الاستماع — حاول مرة أخرى',
              'Could not listen — try again',
            );
        }
      });
      return;
    }
    if (event.type == SpeechEventKind.speechEnd) {
      setState(() {
        _listening = false;
        _hifzMessage = context.tr(
          'جارٍ التحقق من تلاوتك…',
          'Checking your recitation…',
        );
      });
    }
    if (event.type == SpeechEventKind.finalResult) {
      setState(() => _listening = false);
    }
    if (!event.isText || _hifzWords.isEmpty) return;
    final next = followRecitation(
      expected: [for (final word in _hifzWords) word.word],
      position: _hifzPos,
      heard: event.text,
    );
    if (next > _hifzPos) {
      var completed = false;
      setState(() {
        for (var i = _hifzPos; i < next; i++) {
          final word = _hifzWords[i];
          final last =
              i + 1 == _hifzWords.length ||
              _hifzWords[i + 1].ayahId != word.ayahId;
          if (last) {
            _revealed.add(word.ayahId);
            _revealedWords.remove(word.ayahId);
            completed = true;
          } else {
            _revealedWords[word.ayahId] = word.visible;
          }
        }
        _hifzPos = next;
        _hifzProgressed = true;
        _attempts = 0;
        _hifzPraise = completed;
        _hifzMessage = completed
            ? pickPhrase(adultPraisePhrases, _revealed.length)
            : context.tr('أحسنت، تابع…', 'Good, keep going…');
      });
      if (completed) unawaited(HapticFeedback.mediumImpact());
      if (next >= _hifzWords.length) {
        unawaited(_speech.stop());
        setState(() {
          _listening = false;
          _hifzMessage = context.tr(
            'أتممت الصفحة — بارك الله فيك',
            'Page complete — well done',
          );
        });
      }
    } else if (event.type == SpeechEventKind.finalResult) {
      setState(() {
        _hifzPraise = false;
        if (_hifzProgressed) {
          _hifzMessage = context.tr(
            'توقف الاستماع — اضغط «اقرأ» لتكمل من حيث وقفت',
            'Stopped — tap “Recite” to continue where you left off',
          );
        } else {
          _attempts++;
          _hifzMessage = pickPhrase(adultRetryPhrases, _attempts);
        }
      });
    }
  }

  /// كشف يدوي للآية التالية (عند غياب محرّك التعرّف).
  void _revealNext() {
    final page = ref.read(quranPageProvider(_currentPage)).value;
    if (page == null) return;
    final next = page.ayat.where((a) => !_revealed.contains(a.id)).firstOrNull;
    if (next == null) return;
    setState(() {
      _revealed.add(next.id);
      _revealedWords.remove(next.id);
      while (_hifzPos < _hifzWords.length &&
          _revealed.contains(_hifzWords[_hifzPos].ayahId)) {
        _hifzPos++;
      }
    });
  }

  void _clearRevealed() {
    unawaited(_stopListening());
    setState(() {
      _revealed.clear();
      _revealedWords.clear();
      _hifzWords = const [];
      _hifzPos = 0;
      _hifzMessage = null;
      _hifzPraise = false;
    });
  }

  void _hintMic() => _snack(
    context.tr(
      'اقرأ الآية بصوتك ثم اضغط زر الميكروفون لتظهر',
      'Recite the ayah, then press the microphone button',
    ),
  );

  /// هل لهذه الآية رواية في «لباب النقول» (إن كان منزَّلاً)؟
  Future<bool> _suyutiHas(Ayah ayah) async {
    if (!(await ref.read(downloadedExtrasProvider.future))
        .contains('asbab_suyuti')) {
      return false;
    }
    final db = await ref.read(quranExtraDbProvider('asbab_suyuti').future);
    return db.textFor(ayah.surahId, ayah.number) != null;
  }

  Future<void> _showAyahSheet(Ayah ayah, String surahName) async {
    final isMarked = ref
        .read(quranBookmarksProvider)
        .contains('${ayah.surahId}:${ayah.number}');
    final reciter = ref.read(quranReciterProvider);
    final arabic = context.isArabic;
    final reference = context.tr(
      'سورة $surahName · آية ${context.digits(ayah.number)}',
      'Surah $surahName · ayah ${ayah.number}',
    );
    // أسباب النزول مضمَّنة (٥٦٤ آية): السطر مفعَّل إن وُجد سبب لهذه الآية.
    final hasAsbab =
        (await ref.read(ayahStudyRepositoryProvider.future)).asbab(ayah.id) !=
            null ||
        await _suyutiHas(ayah);
    if (!mounted) return;
    setState(() => _highlightAyahId = ayah.id);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(reference),
                subtitle: Text(
                  context.tr(
                    'الجزء ${context.digits(ayah.juz ?? 1)} · الصفحة ${context.digits(ayah.page)}',
                    'Juz ${ayah.juz ?? 1} · page ${ayah.page}',
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.auto_stories_outlined),
                title: Text(
                  context.tr('التفسير والترجمة', 'Tafsir & translation'),
                ),
                subtitle: Text(
                  context.tr(
                    'التفسير الميسر وابن كثير والطبري والترجمات',
                    'Muyassar, Ibn Kathir, al-Tabari, translations',
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AyahStudyScreen(ayah: ayah, surahName: surahName),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.history_edu_outlined),
                title: Text(
                  context.tr('أسباب النزول', 'Occasions of revelation'),
                ),
                subtitle: Text(
                  hasAsbab
                      ? context.tr('الواحدي والسيوطي', 'al-Wahidi, al-Suyuti')
                      : context.tr(
                          'لم يُروَ لهذه الآية سبب نزول',
                          'None narrated for this ayah',
                        ),
                ),
                enabled: hasAsbab,
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AyahStudyScreen(
                        ayah: ayah,
                        surahName: surahName,
                        asbabFirst: true,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(
                  context.tr('استمع من هذه الآية', 'Play from this ayah'),
                ),
                subtitle: Text(
                  '${reciter.name(arabic: arabic)} (${reciter.style})',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _playFrom(ayah);
                },
              ),
              ListTile(
                leading: Icon(
                  isMarked
                      ? Icons.bookmark_remove
                      : Icons.bookmark_add_outlined,
                ),
                title: Text(
                  isMarked
                      ? context.tr('إزالة العلامة', 'Remove bookmark')
                      : context.tr('إضافة علامة', 'Add bookmark'),
                ),
                onTap: () async {
                  final notifier = ref.read(quranBookmarksProvider.notifier);
                  if (isMarked) {
                    await notifier.remove(ayah.surahId, ayah.number);
                  } else {
                    await notifier.add(ayah.surahId, ayah.number);
                  }
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: Text(context.tr('مشاركة كصورة', 'Share as image')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  showShareSheet(
                    context,
                    text: displayQuranText(
                      ayahTextForSharing(
                        ayah.text,
                        surahId: ayah.surahId,
                        number: ayah.number,
                      ),
                    ),
                    source: reference,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(context.tr('نسخ الآية', 'Copy ayah')),
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text:
                          '${ayahTextForSharing(ayah.text, surahId: ayah.surahId, number: ayah.number)}'
                          '\n[$reference]',
                    ),
                  );
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(
                  context.tr('تحميل هذه الآية', 'Download this ayah'),
                ),
                subtitle: Text(reciter.name(arabic: arabic)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _downloadRange(
                    label: context.tr(
                      'الآية ${context.digits(ayah.number)}',
                      'Ayah ${ayah.number}',
                    ),
                    first: ayah.id,
                    last: ayah.id,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted &&
        _highlightAyahId == ayah.id &&
        widget.highlightAyahId != ayah.id) {
      setState(() => _highlightAyahId = widget.highlightAyahId);
    }
  }
}

class _MushafPage extends ConsumerStatefulWidget {
  const _MushafPage({
    required this.pageNumber,
    required this.onAyahTap,
    required this.hifz,
    required this.revealed,
    required this.onMaskedTap,
    this.revealedWords = const {},
    this.playingAyahId,
    this.highlightAyahId,
  });

  final int pageNumber;
  final void Function(Ayah ayah, String surahName) onAyahTap;
  final int? playingAyahId;

  /// آية مظلَّلة (من العلامات/البحث أو الآية المضغوطة).
  final int? highlightAyahId;

  /// وضع الحفظ: هل النص ممسوح؟ وأي الآيات كُشفت بعد تلاوة صحيحة.
  final bool hifz;
  final Set<int> revealed;

  /// كلمات مكشوفة من آية لم تكتمل بعد (التسميع كلمة بكلمة).
  final Map<int, int> revealedWords;
  final VoidCallback onMaskedTap;

  @override
  ConsumerState<_MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends ConsumerState<_MushafPage> {
  /// مُعرِّفات اللمس تُنشأ مرة لكل آية وتُحرَّر مع الصفحة.
  final Map<int, TapGestureRecognizer> _recognizers = {};
  final ScrollController _scroll = ScrollController();
  int? _scrolledFor;

  TapGestureRecognizer _recognizerFor(Ayah ayah, String surahName) =>
      _recognizers.putIfAbsent(
        ayah.id,
        () => TapGestureRecognizer()
          ..onTap = () {
            if (isAyahMasked(
              hifz: widget.hifz,
              revealed: widget.revealed,
              ayahId: ayah.id,
            )) {
              widget.onMaskedTap();
              return;
            }
            widget.onAyahTap(ayah, surahName);
          },
      );

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  /// يمرّر الصفحة تقريبياً إلى الآية المظلَّلة/المتلوّة إن كانت أسفلها.
  void _scrollTo(QuranPage page, int? ayahId) {
    if (ayahId == null || ayahId == _scrolledFor) return;
    final index = page.ayat.indexWhere((a) => a.id == ayahId);
    if (index < 0) return;
    _scrolledFor = ayahId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) return;
      final fraction = index / page.ayat.length;
      _scroll.animateTo(
        (max * fraction).clamp(0, max),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  /// مضاعف حجم الخط الذي يملأ الصفحة دون تجاوزها — مخبّأ لكل (صفحة، مقاس).
  final Map<String, double> _fitCache = {};

  /// تباعد الأسطر الذي يملأ الصفحة حتى أسفلها (كالمصحف المطبوع).
  final Map<String, double> _lineCache = {};

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final fontScale = mushafLayout(
      width: media.width,
      height: media.height,
    ).fontScale;
    // الوضع الأفقي: الخط يكبر مع عرض الصفحة (كتكبير الصفحة) والقراءة بالتمرير،
    // بدل حشر الصفحة كاملة في ارتفاع الشاشة القصير.
    final landscape = media.width > media.height;
    // حجم الترويسة والهوامش لا يتضخم في الأفقي كما يتضخم نص الآيات.
    final chrome = landscape ? 1.2 : fontScale;
    final pageAsync = ref.watch(quranPageProvider(widget.pageNumber));
    final surahs = ref.watch(surahsProvider).value ?? const <Surah>[];
    final basmala = ref.watch(_basmalaProvider).value ?? '';
    final appearance = ref.watch(mushafAppearanceProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final paper = dark ? scheme.surfaceContainerLow : appearance.paper.color;
    final ink = dark ? scheme.onSurface : const Color(0xFF1B1B1B);
    final framed = appearance.frame != MushafFrameStyle.none;
    final ornate = appearance.frame == MushafFrameStyle.ornate;
    // أرقام الآيات زرقاء كمصحف المدينة المطبوع في النمط المزخرف.
    final numberColor = dark
        ? const Color(0xFFC9B394)
        : ornate
        ? const Color(0xFF1F6FA3)
        : const Color(0xFF876A44);

    return pageAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (page) {
        Surah? surahOf(int id) => surahs.where((s) => s.id == id).firstOrNull;
        String surahName(int id) => surahOf(id)?.nameAr ?? '';

        _scrollTo(page, widget.highlightAyahId ?? widget.playingAyahId);

        // تقسيم الصفحة إلى مقاطع: كل سورة تبدأ داخل الصفحة لها فاصلها.
        final segments = <List<Ayah>>[];
        var current = <Ayah>[];
        for (final ayah in page.ayat) {
          if (ayah.number == 1 && current.isNotEmpty) {
            segments.add(current);
            current = [];
          }
          current.add(ayah);
        }
        if (current.isNotEmpty) segments.add(current);

        // البسملة تُرسم مستقلة لكل سورة، فنزيلها من نص أول آية للعرض،
        // وعلامات الوقف تُلصق بالكلمة السابقة (بلا فراغ زائد) — للعرض فقط.
        String ayahDisplay(Ayah ayah) => mushafAyahText(ayah);
        bool hasBasmala(Ayah first) =>
            first.number == 1 &&
            first.surahId != 1 &&
            first.surahId != 9 &&
            basmala.isNotEmpty;

        // ترويسة الصفحة كمصحف المدينة: الجزء والحزب يميناً، واسم السورة يساراً.
        final firstAyah = page.ayat.isEmpty ? null : page.ayat.first;
        final juz = firstAyah?.juz;
        final quarter = firstAyah?.hizbQuarter;
        final headerText = [
          if (juz != null) 'الجزء ${mushafNumber(juz)}',
          if (quarter != null) hizbQuarterLabel(quarter, mushafNumber),
        ].join('، ');
        final headerStyle = TextStyle(
          fontFamily: 'Amiri',
          fontSize: 13.5 * chrome,
          height: 1.3,
          color: numberColor,
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            // هوامش رفيعة: كل نقطة عرض تذهب لحجم الخط.
            const outer = EdgeInsets.fromLTRB(4, 4, 4, 4);
            final inner = ornate
                ? EdgeInsets.fromLTRB(
                    4 * chrome,
                    2 * chrome,
                    4 * chrome,
                    2 * chrome,
                  )
                : EdgeInsets.fromLTRB(
                    (framed ? 14 : 10) * chrome,
                    (framed ? 10 : 6) * chrome,
                    (framed ? 14 : 10) * chrome,
                    (framed ? 10 : 6) * chrome,
                  );
            final decoInset = switch (appearance.frame) {
              MushafFrameStyle.geometric || MushafFrameStyle.floral => 20.0,
              MushafFrameStyle.ornate => MadinahOrnament.inset * 2,
              _ => 0.0,
            };
            final pageHeight = constraints.maxHeight - outer.vertical;
            final textWidth =
                constraints.maxWidth -
                outer.horizontal -
                inner.horizontal -
                decoInset -
                4;
            // حجم خط النظام (مثلاً ١١٥٪ في إعدادات الهاتف) يكبّر كل Text فعلياً،
            // فيدخل في كل قياس هنا وإلا فاض النص عن الصفحة.
            final scaler = MediaQuery.textScalerOf(context);
            final headerHeight =
                scaler.scale(headerStyle.fontSize!) * 1.3 +
                10 * chrome +
                (ornate ? 8 : 0);
            final footerHeight =
                scaler.scale(14 * chrome) * 1.4 + 8 + (ornate ? 6 : 0);
            final bodyHeight =
                pageHeight -
                inner.vertical -
                decoInset -
                headerHeight -
                footerHeight -
                6;

            const base = 23.0;
            // تباعد أدنى؛ ثم يُمدّ حتى تمتلئ الصفحة (انظر [line] أدناه).
            const baseLine = 1.7;
            // صفحة تُمرَّر: تباعد مريح للقراءة.
            const scrollLine = 2.0;
            TextStyle ayahStyleFor(double m, [double line = baseLine]) =>
                TextStyle(
                  fontFamily: AppTheme.quranFont,
                  fontFamilyFallback: AppTheme.quranFallback,
                  fontSize: base * fontScale * m,
                  height: line,
                  color: ink,
                );
            TextStyle numberStyleFor(double m, [double line = baseLine]) =>
                TextStyle(
                  fontFamily: AppTheme.quranFont,
                  fontFamilyFallback: AppTheme.quranFallback,
                  fontSize: base * fontScale * m,
                  height: line,
                  color: numberColor,
                );
            double bannerHeightFor(double m) => base * fontScale * m * 2.0;
            TextStyle basmalaStyleFor(double m) => TextStyle(
              fontFamily: AppTheme.quranFont,
              fontFamilyFallback: AppTheme.quranFallback,
              fontSize: base * 0.92 * fontScale * m,
              height: 1.8,
              color: widget.hifz ? Colors.transparent : ink,
            );

            // ارتفاع محتوى الصفحة لمضاعف [m] — قياس فعلي للنص.
            double measure(double m, [double line = baseLine]) {
              var total = 0.0;
              for (var i = 0; i < segments.length; i++) {
                final ayat = segments[i];
                if (ayat.first.number == 1) {
                  total += bannerHeightFor(m) + 8 * fontScale * m;
                  if (i > 0) total += 6;
                  if (hasBasmala(ayat.first)) {
                    final painter = TextPainter(
                      text: TextSpan(text: basmala, style: basmalaStyleFor(m)),
                      textDirection: TextDirection.rtl,
                      textScaler: scaler,
                    )..layout(maxWidth: textWidth);
                    total += painter.height + 2;
                    painter.dispose();
                  }
                }
                final painter = TextPainter(
                  text: TextSpan(
                    children: [
                      for (final ayah in ayat) ...[
                        TextSpan(
                          text: ayahDisplay(ayah),
                          style: ayahStyleFor(m, line),
                        ),
                        TextSpan(
                          text: '${ayahMark(ayah.number)} ',
                          style: numberStyleFor(m, line),
                        ),
                      ],
                    ],
                  ),
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.justify,
                  textScaler: scaler,
                )..layout(maxWidth: textWidth);
                total += painter.height;
                painter.dispose();
              }
              return total;
            }

            final key =
                '${widget.pageNumber}:${textWidth.round()}x${bodyHeight.round()}'
                ':${basmala.isNotEmpty}:${scaler.scale(100).round()}';
            // أصغر خط مسموح حسب «حجم الخط»: إن لم تتسع الصفحة به تُمرَّر
            // بدل تصغير الخط إلى حدّ يُتعب القارئ.
            final minM = math.max(
              0.62,
              appearance.textSize.minPoints / (base * fontScale),
            );
            final maxM = math.max(1.22, minM);
            final m = landscape
                ? math.max(0.95, minM)
                : _fitCache['$key:$minM'] ??= () {
                    if (bodyHeight <= 0 || textWidth <= 0) return 1.0;
                    if (measure(maxM) <= bodyHeight) return maxM;
                    if (measure(minM) > bodyHeight) return minM;
                    var lo = minM;
                    var hi = maxM;
                    for (var i = 0; i < 10; i++) {
                      final mid = (lo + hi) / 2;
                      if (measure(mid) <= bodyHeight) {
                        lo = mid;
                      } else {
                        hi = mid;
                      }
                    }
                    return lo;
                  }();
            final fits =
                !landscape && bodyHeight > 0 && measure(m) <= bodyHeight + 1;

            // يبقى بعد الملاءمة فراغ تحت النص (لا يتسع لسطر كامل)، فيُوزَّع على
            // تباعد الأسطر حتى تمتلئ الصفحة إلى البرواز كالمصحف المطبوع.
            final line = !fits
                ? scrollLine
                : widget.pageNumber <= 2
                ? baseLine
                : _lineCache[key] ??= () {
                    const maxLine = 3.2;
                    if (measure(m, maxLine) <= bodyHeight) return maxLine;
                    var lo = baseLine;
                    var hi = maxLine;
                    for (var i = 0; i < 12; i++) {
                      final mid = (lo + hi) / 2;
                      if (measure(m, mid) <= bodyHeight) {
                        lo = mid;
                      } else {
                        hi = mid;
                      }
                    }
                    return lo;
                  }();
            final ayahStyle = ayahStyleFor(m, line);
            final numberStyle = numberStyleFor(m, line);
            final playingTint = scheme.tertiaryContainer.withValues(
              alpha: 0.75,
            );
            final highlightTint = scheme.primaryContainer.withValues(
              alpha: 0.8,
            );

            Widget buildSegment(List<Ayah> ayat, int index) {
              final spans = <InlineSpan>[];
              for (final ayah in ayat) {
                final masked = isAyahMasked(
                  hifz: widget.hifz,
                  revealed: widget.revealed,
                  ayahId: ayah.id,
                );
                final TextStyle spanStyle;
                if (masked) {
                  // «الصفحة ممسوحة»: نُخفي الحبر فقط، فيبقى التخطيط ولا يظهر إلا الرقم.
                  spanStyle = ayahStyle.copyWith(color: Colors.transparent);
                } else if (ayah.id == widget.playingAyahId) {
                  spanStyle = ayahStyle.copyWith(backgroundColor: playingTint);
                } else if (ayah.id == widget.highlightAyahId) {
                  spanStyle = ayahStyle.copyWith(
                    backgroundColor: highlightTint,
                  );
                } else if (widget.hifz) {
                  spanStyle = ayahStyle.copyWith(
                    backgroundColor: scheme.secondaryContainer.withValues(
                      alpha: 0.5,
                    ),
                  );
                } else {
                  spanStyle = ayahStyle;
                }
                final shown = masked ? widget.revealedWords[ayah.id] ?? 0 : 0;
                if (shown > 0) {
                  // التسميع كلمة بكلمة: أول [shown] كلمات ظاهرة والباقي ممسوح،
                  // والنص نفسه لم يتغير فيبقى التخطيط ثابتاً.
                  final words = ayahDisplay(ayah).split(' ');
                  spans.add(
                    TextSpan(
                      text: words.take(shown).join(' '),
                      style: ayahStyle.copyWith(
                        backgroundColor: scheme.secondaryContainer.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  );
                  if (shown < words.length) {
                    spans.add(
                      TextSpan(
                        text: ' ${words.skip(shown).join(' ')}',
                        style: spanStyle,
                        recognizer: _recognizerFor(
                          ayah,
                          surahName(ayah.surahId),
                        ),
                      ),
                    );
                  }
                } else {
                  spans.add(
                    TextSpan(
                      text: ayahDisplay(ayah),
                      style: spanStyle,
                      recognizer: _recognizerFor(ayah, surahName(ayah.surahId)),
                    ),
                  );
                }
                spans.add(
                  TextSpan(
                    text: '${ayahMark(ayah.number)} ',
                    style: ayah.id == widget.playingAyahId
                        ? numberStyle.copyWith(fontWeight: FontWeight.w700)
                        : numberStyle,
                  ),
                );
              }

              final first = ayat.first;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (first.number == 1) ...[
                    if (index > 0) const SizedBox(height: 6),
                    Padding(
                      padding: EdgeInsets.only(bottom: 8 * fontScale * m),
                      child: MadinahSurahBanner(
                        name: surahName(first.surahId),
                        height: bannerHeightFor(m),
                      ),
                    ),
                    if (hasBasmala(first))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          basmala,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.center,
                          style: basmalaStyleFor(m),
                        ),
                      ),
                  ],
                  Text.rich(
                    TextSpan(children: spans),
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.justify,
                  ),
                ],
              );
            }

            final header = SizedBox(
              height: headerHeight,
              child: Row(
                textDirection: TextDirection.rtl,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: ornate
                    ? [
                        // ترويسة مصحف المدينة: خرطوشة الجزء يميناً والسورة يساراً.
                        Flexible(
                          flex: 6,
                          child: MadinahCartouche(
                            child: Text(
                              headerText,
                              textDirection: TextDirection.rtl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: headerStyle.copyWith(
                                color: MadinahOrnament.navy,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (firstAyah != null)
                          MadinahCartouche(
                            child: Text(
                              surahName(firstAyah.surahId),
                              textDirection: TextDirection.rtl,
                              style: headerStyle.copyWith(
                                color: MadinahOrnament.navy,
                              ),
                            ),
                          ),
                      ]
                    : [
                        Expanded(
                          child: Text(
                            headerText,
                            textDirection: TextDirection.rtl,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: headerStyle,
                          ),
                        ),
                        Text(
                          firstAyah == null ? '' : surahName(firstAyah.surahId),
                          textDirection: TextDirection.rtl,
                          style: headerStyle,
                        ),
                      ],
              ),
            );
            final footer = SizedBox(
              height: footerHeight,
              child: Center(
                child: ornate
                    ? MadinahCartouche(
                        compact: true,
                        child: Text(
                          mushafNumber(widget.pageNumber),
                          style: TextStyle(
                            fontFamily: 'Amiri',
                            fontSize: 14 * chrome,
                            height: 1.3,
                            color: MadinahOrnament.navy,
                          ),
                        ),
                      )
                    : Text(
                        mushafNumber(widget.pageNumber),
                        style: TextStyle(
                          fontFamily: 'Amiri',
                          fontSize: 14 * chrome,
                          color: numberColor,
                        ),
                      ),
              ),
            );
            final body = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < segments.length; i++)
                  buildSegment(segments[i], i),
              ],
            );

            if (fits) {
              // النص يتسع للصفحة: صفحة ثابتة كالمطبوعة — بلا تمرير.
              return Padding(
                padding: outer,
                child: SizedBox(
                  height: pageHeight,
                  child: MushafPageFrame(
                    style: appearance.frame,
                    paper: paper,
                    padding: inner,
                    child: Column(
                      children: [
                        header,
                        Expanded(
                          // شبكة أمان: إن بقي فرق قياس بسيط تُصغَّر الصفحة قليلاً
                          // بدل أن يفيض النص ويُقصّ آخر الأسطر.
                          child: LayoutBuilder(
                            builder: (context, box) => Align(
                              // الفاتحة وأول البقرة في منتصف الصفحة كالمصحف.
                              alignment: widget.pageNumber <= 2
                                  ? Alignment.center
                                  : Alignment.topCenter,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: box.maxWidth,
                                  child: body,
                                ),
                              ),
                            ),
                          ),
                        ),
                        footer,
                      ],
                    ),
                  ),
                ),
              );
            }

            // شاشة ضيقة جداً: نُبقي أصغر خط مقروء ونسمح بالتمرير.
            return SingleChildScrollView(
              controller: _scroll,
              padding: outer,
              child: MushafPageFrame(
                style: appearance.frame,
                paper: paper,
                minHeight: pageHeight > inner.vertical
                    ? pageHeight - inner.vertical
                    : null,
                padding: inner,
                child: Column(children: [header, body, footer]),
              ),
            );
          },
        );
      },
    );
  }
}

/// شريط اسم السورة على نمط مصحف المدينة: إطار مذهّب، أرضية زرقاء بزخرفة
/// معيّنات، وخرطوشة فاتحة في الوسط فيها اسم السورة.
class MadinahSurahBanner extends StatelessWidget {
  const MadinahSurahBanner({
    super.key,
    required this.name,
    required this.height,
  });

  final String name;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: const _MadinahBannerPainter(),
        child: Center(
          child: Text(
            'سورة $name',
            textDirection: TextDirection.rtl,
            maxLines: 1,
            style: TextStyle(
              fontFamily: 'Amiri',
              fontSize: height * 0.4,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1C3D5A),
            ),
          ),
        ),
      ),
    );
  }
}

class _MadinahBannerPainter extends CustomPainter {
  const _MadinahBannerPainter();

  static const _gold = Color(0xFFB08D4F);
  static const _blue = Color(0xFF3F7CA8);
  static const _blueLight = Color(0xFF9CC3DD);
  static const _cartouche = Color(0xFFF7F1E1);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = _gold;

    // الإطار الخارجي المذهّب ثم الأرضية الزرقاء.
    canvas.drawRect(rect, Paint()..color = _gold);
    final field = rect.deflate(size.height * 0.08);
    canvas.drawRect(field, Paint()..color = _blue);

    // زخرفة معيّنات متكررة على الأرضية.
    final diamond = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = _blueLight.withValues(alpha: 0.85);
    final dot = Paint()..color = _cartouche.withValues(alpha: 0.8);
    final step = field.height / 2;
    canvas.save();
    canvas.clipRect(field);
    for (var x = field.left; x < field.right + step; x += step) {
      for (var y = field.top; y < field.bottom + step; y += step) {
        final path = Path()
          ..moveTo(x, y - step / 2)
          ..lineTo(x + step / 2, y)
          ..lineTo(x, y + step / 2)
          ..lineTo(x - step / 2, y)
          ..close();
        canvas.drawPath(path, diamond);
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
    canvas.restore();

    // خرطوشة الاسم: مستطيل بطرفين مقوّسين.
    final ch = field.height * 0.86;
    final cart = Rect.fromCenter(
      center: rect.center,
      width: size.width * 0.46,
      height: ch,
    );
    final bulge = ch * 0.15;
    final cy = cart.center.dy;
    final cartPath = Path()
      ..moveTo(cart.left + ch * 0.5, cart.top)
      ..lineTo(cart.right - ch * 0.5, cart.top)
      ..quadraticBezierTo(cart.right + bulge, cart.top, cart.right + bulge, cy)
      ..quadraticBezierTo(
        cart.right + bulge,
        cart.bottom,
        cart.right - ch * 0.5,
        cart.bottom,
      )
      ..lineTo(cart.left + ch * 0.5, cart.bottom)
      ..quadraticBezierTo(cart.left - bulge, cart.bottom, cart.left - bulge, cy)
      ..quadraticBezierTo(
        cart.left - bulge,
        cart.top,
        cart.left + ch * 0.5,
        cart.top,
      )
      ..close();
    canvas.drawPath(cartPath, Paint()..color = _cartouche);
    canvas.drawPath(cartPath, stroke..strokeWidth = 1.6);

    // ميداليتان على الطرفين.
    final r = field.height * 0.34;
    for (final dx in [
      field.left + field.height * 0.6,
      field.right - field.height * 0.6,
    ]) {
      final c = Offset(dx, rect.center.dy);
      canvas.drawCircle(c, r, Paint()..color = _cartouche);
      canvas.drawCircle(c, r, stroke..strokeWidth = 1.2);
      canvas.drawCircle(c, r * 0.45, Paint()..color = _gold);
    }

    canvas.drawRect(field, stroke..strokeWidth = 0.8);
  }

  @override
  bool shouldRepaint(_MadinahBannerPainter old) => false;
}

/// شريط التشغيل: الآية الجارية + السابقة/تشغيل/التالية + إيقاف.
class _NowPlayingBar extends StatelessWidget {
  const _NowPlayingBar({
    required this.playback,
    required this.reciter,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onStop,
    required this.onLocate,
  });

  final QuranPlaybackState playback;
  final String reciter;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onStop;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ayah = playback.ayah;
    final fg = scheme.onPrimary;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: Icon(Icons.skip_next, color: fg),
            tooltip: context.tr('الآية السابقة', 'Previous ayah'),
            visualDensity: VisualDensity.compact,
          ),
          if (playback.loading)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              ),
            )
          else
            IconButton(
              onPressed: onPlayPause,
              icon: Icon(
                playback.playing ? Icons.pause : Icons.play_arrow,
                color: fg,
              ),
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: onNext,
            icon: Icon(Icons.skip_previous, color: fg),
            tooltip: context.tr('الآية التالية', 'Next ayah'),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: InkWell(
              onTap: onLocate,
              child: Text(
                ayah == null
                    ? reciter
                    : context.tr(
                        '$reciter · ${playback.surahName} ${context.digits(ayah.number)}',
                        '$reciter · ${playback.surahName} ${ayah.number}',
                      ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(color: fg),
              ),
            ),
          ),
          IconButton(
            onPressed: onStop,
            icon: Icon(Icons.stop, color: fg),
            visualDensity: VisualDensity.compact,
            tooltip: context.tr('إيقاف', 'Stop'),
          ),
        ],
      ),
    );
  }
}

/// شريط وضع الحفظ: يسمع تلاوة المستخدم، فإن صحّت الآية كُشفت.
class _HifzBar extends StatelessWidget {
  const _HifzBar({
    required this.revealed,
    required this.total,
    required this.listening,
    required this.success,
    required this.message,
    required this.speechAvailable,
    required this.onMic,
    required this.onRevealPage,
    required this.onHideAll,
    this.onDownload,
  });

  /// تنزيل نموذج التسميع (يظهر حين يكون متاحاً للتنزيل).
  final VoidCallback? onDownload;

  final int revealed;
  final int total;
  final bool listening;
  final bool success;
  final String message;
  final bool speechAvailable;
  final VoidCallback onMic;
  final VoidCallback onRevealPage;
  final VoidCallback onHideAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
        child: Row(
          children: [
            FilledButton.icon(
              onPressed: speechAvailable || onDownload != null ? onMic : null,
              icon: Icon(
                listening ? Icons.stop_circle_outlined : Icons.mic_none,
                size: 18,
              ),
              label: Text(
                listening
                    ? context.tr('أوقف', 'Stop')
                    : context.tr('اقرأ', 'Recite'),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: success ? scheme.primary : scheme.onSurface,
                      fontWeight: success ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  Text(
                    context.tr(
                      '${context.digits(revealed)} من ${context.digits(total)} آية ظاهرة',
                      '$revealed of $total ayahs shown',
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onDownload != null)
              TextButton(
                onPressed: onDownload,
                child: Text(context.tr('تنزيل النموذج', 'Download model')),
              ),
            if (!speechAvailable)
              TextButton(
                onPressed: onRevealPage,
                child: Text(context.tr('اكشف الآية', 'Reveal ayah')),
              ),
            if (revealed > 0)
              IconButton(
                tooltip: context.tr('إخفاء الكل', 'Hide all'),
                onPressed: onHideAll,
                icon: const Icon(Icons.visibility_off_outlined, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

/// اختيار شكل الصفحة ولون الورق.
class _StylePickerSheet extends ConsumerWidget {
  const _StylePickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(mushafAppearanceProvider);
    final notifier = ref.read(mushafAppearanceProvider.notifier);
    final arabic = context.isArabic;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('إطار الصفحة', 'Page frame'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 128,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final style in MushafFrameStyle.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 10),
                      child: GestureDetector(
                        onTap: () => notifier.setFrame(style),
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: appearance.frame == style
                                      ? scheme.primary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              padding: const EdgeInsets.all(2),
                              child: SizedBox(
                                width: 70,
                                height: 90,
                                child: MushafPageFrame(
                                  style: style,
                                  paper: appearance.paper.color,
                                  padding: const EdgeInsets.all(14),
                                  child: Center(
                                    child: Text(
                                      'بسم الله',
                                      style: TextStyle(
                                        fontFamily: 'Amiri',
                                        fontSize: 11,
                                        color: Colors.black.withValues(
                                          alpha: 0.8,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              style.label(arabic: arabic),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('حجم الخط', 'Text size'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final size in MushafTextSize.values)
                  ChoiceChip(
                    label: Text(size.label(arabic: arabic)),
                    selected: appearance.textSize == size,
                    onSelected: (_) => notifier.setTextSize(size),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.tr(
                  'الأحجام الكبيرة تُمرَّر فيها الصفحة إن لم تتسع للشاشة.',
                  'Larger sizes scroll when the page does not fit.',
                ),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('لون الورق', 'Paper color'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final paper in MushafPaper.values)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: paper.color,
                      radius: 8,
                    ),
                    label: Text(paper.label(arabic: arabic)),
                    selected: appearance.paper == paper,
                    onSelected: (_) => notifier.setPaper(paper),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.tr(
                  'في الوضع الداكن يُستخدم لون داكن مريح للعين.',
                  'In dark mode a comfortable dark page is used.',
                ),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
