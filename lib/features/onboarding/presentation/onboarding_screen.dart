import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/app/locale_provider.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:yousuf/core/platform/adhan_channel.dart';
import 'package:yousuf/core/prefs/shared_preferences_provider.dart';
import 'package:yousuf/l10n/generated/app_localizations.dart';

import '../../cities/data/cities_repository.dart';
import '../../cities/data/device_location.dart';
import '../../prayer/data/prayer_settings_repository.dart';
import '../../prayer/domain/adhan_sounds.dart';
import '../../prayer/domain/prayer_times_models.dart';
import '../../prayer/presentation/adhan_readiness.dart';
import '../../prayer/presentation/prayer_providers.dart';

/// شاشة الترحيب — 5 خطوات (SPEC §7.1): اللغة، المدينة، طريقة الحساب،
/// صوت الأذان، وجاهزية الأذان مع تجربة.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  final TextEditingController _search = TextEditingController();

  int _index = 0;
  static const int _steps = 5;

  Locale _locale = const Locale('ar');
  City? _city;

  /// الموقع المختار: مركز المدينة، أو إحداثيات الجهاز إن استُخدم GPS.
  PrayerLocation? _location;
  CalculationMethod _method = CalculationMethod.ummAlQura;
  AsrMadhab _madhab = AsrMadhab.shafi;
  String _soundId = 'makkah';
  List<String> _availableSounds = const [];
  bool _locating = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _locale = ref.read(localeProvider) ?? const Locale('ar');
    _loadSounds();
  }

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadSounds() async {
    if (!AdhanChannel.isSupported) return;
    try {
      final status = await AdhanChannel().status();
      if (mounted) setState(() => _availableSounds = status.availableSounds);
    } catch (_) {
      // على المنصات غير المدعومة تبقى القائمة فارغة (الافتراضي فقط).
    }
  }

  void _selectCity(City city, {PrayerLocation? location}) {
    setState(() {
      _city = city;
      _location = location ?? city.toPrayerLocation();
      _method = defaultMethodForCountry(city.countryCode);
    });
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final result = await locateDeviceFromWidget(ref);
    if (!mounted) return;
    setState(() => _locating = false);
    if (!result.ok) {
      _snack(
        result.failure == LocateFailure.denied
            ? context.tr(
                'لم يُسمح بالوصول للموقع — اختر مدينتك يدوياً',
                'Location access denied — pick your city manually',
              )
            : context.tr(
                'تعذر تحديد الموقع — اختر مدينتك يدوياً',
                'Could not get your location — pick your city manually',
              ),
      );
      return;
    }
    _selectCity(result.city!, location: result.location);
    _snack(
      context.tr(
        'تم تحديد موقعك (قرب ${result.city!.nameAr})',
        'Location set (near ${result.city!.nameEn})',
      ),
    );
  }

  Future<void> _finish() async {
    final location = _location;
    if (location == null || _finishing) return;
    setState(() => _finishing = true);

    // الفجر يحتفظ بصوته الافتراضي المختلف (SPEC §8)، والمختار لبقية الصلوات.
    final settings = PrayerSettings(
      location: location,
      method: _method,
      madhab: _madhab,
      prayerSounds: {
        'fajr': PrayerSound.defaults['fajr']!,
        for (final prayer in const ['dhuhr', 'asr', 'maghrib', 'isha'])
          prayer: PrayerSound(sound: _soundId),
      },
    );

    try {
      await ref.read(prayerSettingsControllerProvider).save(settings);
      ref.read(localeProvider.notifier).select(_locale);
      ref.read(onboardingDoneProvider.notifier).complete();
    } catch (error) {
      if (!mounted) return;
      setState(() => _finishing = false);
      _snack(context.tr('تعذر الحفظ: $error', 'Could not save: $error'));
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _next() {
    if (_index < _steps - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  bool get _canProceed => switch (_index) {
    1 => _location != null,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _index = index),
                children: [
                  _LanguageStep(
                    selected: _locale,
                    onSelect: (locale) {
                      setState(() => _locale = locale);
                      ref.read(localeProvider.notifier).select(locale);
                    },
                  ),
                  _CityStep(
                    search: _search,
                    selected: _city,
                    fromGps: _location?.fromGps ?? false,
                    locating: _locating,
                    onLocate: _locate,
                    onSelect: _selectCity,
                  ),
                  _MethodStep(
                    method: _method,
                    madhab: _madhab,
                    onMethod: (method) => setState(() => _method = method),
                    onMadhab: (madhab) => setState(() => _madhab = madhab),
                  ),
                  _SoundStep(
                    soundId: effectiveAdhanSound(_soundId, _availableSounds),
                    available: _availableSounds,
                    onSelect: (id) => setState(() => _soundId = id),
                  ),
                  _StepScaffold(
                    title: context.tr('جاهزية الأذان', 'Adhan readiness'),
                    subtitle: context.tr(
                      'خطوات بسيطة تضمن ألا يفوتك الأذان',
                      'A few steps so you never miss the adhan',
                    ),
                    child: const SingleChildScrollView(
                      child: AdhanReadinessPanel(dense: false),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                children: [
                  if (_index > 0)
                    TextButton(
                      onPressed: () => _controller.previousPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                      child: Text(context.tr('السابق', 'Back')),
                    ),
                  const Spacer(),
                  Row(
                    children: [
                      for (var i = 0; i < _steps; i++)
                        Container(
                          width: i == _index ? 18 : 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: i == _index
                                ? scheme.primary
                                : scheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _canProceed && !_finishing ? _next : null,
                    child: Text(
                      _index == _steps - 1
                          ? context.tr('ابدأ', 'Start')
                          : context.tr('التالي', 'Next'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.tagline,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFamily: 'Amiri',
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _LanguageStep extends StatelessWidget {
  const _LanguageStep({required this.selected, required this.onSelect});

  final Locale selected;
  final ValueChanged<Locale> onSelect;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: context.tr('أهلاً بك في يوسف', 'Welcome to Yousuf'),
      subtitle: context.tr(
        'رفيقك في الطاعة — اختر لغة الواجهة',
        'Your companion in worship — choose the interface language',
      ),
      child: Column(
        children: [
          _ChoiceCard(
            title: 'العربية',
            subtitle: 'الواجهة الافتراضية مع دعم كامل للعربية',
            selected: selected.languageCode == 'ar',
            onTap: () => onSelect(const Locale('ar')),
          ),
          const SizedBox(height: 12),
          _ChoiceCard(
            title: 'English',
            subtitle: 'English interface (Quran and adhkar stay in Arabic)',
            selected: selected.languageCode == 'en',
            onTap: () => onSelect(const Locale('en')),
          ),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
              ?trailing,
              if (selected) Icon(Icons.check_circle, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CityStep extends ConsumerWidget {
  const _CityStep({
    required this.search,
    required this.selected,
    required this.fromGps,
    required this.locating,
    required this.onLocate,
    required this.onSelect,
  });

  final TextEditingController search;
  final City? selected;
  final bool fromGps;
  final bool locating;
  final VoidCallback onLocate;
  final void Function(City city) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final citiesAsync = ref.watch(citiesRepositoryProvider);
    final arabic = context.isArabic;
    final scheme = Theme.of(context).colorScheme;
    return _StepScaffold(
      title: context.tr('أين أنت؟', 'Where are you?'),
      subtitle: context.tr(
        'لتحديد المواقيت بدقة — كل شيء يعمل دون إنترنت بعد الاختيار',
        'For accurate prayer times — everything works offline afterwards',
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  decoration: InputDecoration(
                    hintText: context.tr(
                      'ابحث عن مدينة…',
                      'Search for a city…',
                    ),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: locating ? null : onLocate,
                icon: locating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, size: 18),
                label: Text(context.tr('موقعي', 'My location')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: search,
              builder: (context, value, _) {
                return citiesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Text(
                      context.tr(
                        'تعذر تحميل المدن: $error',
                        'Could not load cities: $error',
                      ),
                    ),
                  ),
                  data: (repository) {
                    final results = repository.search(search.text);
                    return ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final city = results[index];
                        final isSelected = !fromGps && selected?.id == city.id;
                        return ListTile(
                          dense: true,
                          title: Text(city.name(arabic: arabic)),
                          subtitle: Text(
                            '${city.name(arabic: !arabic)} · ${city.countryCode}',
                          ),
                          trailing: isSelected
                              ? Icon(Icons.check_circle, color: scheme.primary)
                              : null,
                          onTap: () => onSelect(city),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          if (selected != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                fromGps
                    ? context.tr(
                        'موقعك الحالي (قرب ${selected!.nameAr})',
                        'Your current location (near ${selected!.nameEn})',
                      )
                    : context.tr(
                        'المختار: ${selected!.nameAr}',
                        'Selected: ${selected!.nameEn}',
                      ),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _MethodStep extends StatelessWidget {
  const _MethodStep({
    required this.method,
    required this.madhab,
    required this.onMethod,
    required this.onMadhab,
  });

  final CalculationMethod method;
  final AsrMadhab madhab;
  final ValueChanged<CalculationMethod> onMethod;
  final ValueChanged<AsrMadhab> onMadhab;

  @override
  Widget build(BuildContext context) {
    final arabic = context.isArabic;
    return _StepScaffold(
      title: context.tr('طريقة الحساب', 'Calculation method'),
      subtitle: context.tr(
        'اقترحناها حسب دولتك — يمكنك تغييرها لاحقاً من الإعدادات',
        'Suggested for your country — you can change it later in Settings',
      ),
      child: ListView(
        children: [
          for (final option in CalculationMethod.selectable)
            RadioListTile<CalculationMethod>(
              value: option,
              // ignore: deprecated_member_use
              groupValue: method,
              // ignore: deprecated_member_use
              onChanged: (value) => value == null ? null : onMethod(value),
              title: Text(option.label(arabic: arabic)),
              dense: true,
            ),
          const Divider(),
          SwitchListTile(
            title: Text(context.tr('مذهب العصر: حنفي', 'Asr: Hanafi')),
            subtitle: Text(
              context.tr(
                'الافتراضي: الجمهور (شافعي)',
                'Default: Standard (Shafii)',
              ),
            ),
            value: madhab == AsrMadhab.hanafi,
            onChanged: (value) =>
                onMadhab(value ? AsrMadhab.hanafi : AsrMadhab.shafi),
          ),
        ],
      ),
    );
  }
}

class _SoundStep extends StatefulWidget {
  const _SoundStep({
    required this.soundId,
    required this.available,
    required this.onSelect,
  });

  final String soundId;
  final List<String> available;
  final ValueChanged<String> onSelect;

  @override
  State<_SoundStep> createState() => _SoundStepState();
}

class _SoundStepState extends State<_SoundStep> {
  String? _previewing;

  @override
  void dispose() {
    if (_previewing != null) {
      AdhanChannel().stopSound().catchError((_) => false);
    }
    super.dispose();
  }

  Future<void> _preview(String id) async {
    final channel = AdhanChannel();
    if (_previewing == id) {
      setState(() => _previewing = null);
      await channel.stopSound().catchError((_) => false);
      return;
    }
    setState(() => _previewing = id);
    try {
      await channel.previewSound(id);
    } catch (_) {
      if (mounted) setState(() => _previewing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final arabic = context.isArabic;
    final sounds = selectableAdhanSounds(widget.available);
    return _StepScaffold(
      title: context.tr('صوت الأذان', 'Adhan sound'),
      subtitle: context.tr(
        'اختر المؤذن لصلوات اليوم — للفجر صوته الخاص، ويمكنك تغيير كل صلاة من الإعدادات',
        'Choose the muezzin — Fajr keeps its own voice; change any prayer in Settings',
      ),
      child: ListView(
        children: [
          for (final sound in sounds)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ChoiceCard(
                title: sound.label(arabic: arabic),
                subtitle: sound.label(arabic: !arabic),
                selected: widget.soundId == sound.id,
                onTap: () => widget.onSelect(sound.id),
                trailing: AdhanChannel.isSupported
                    ? IconButton(
                        tooltip: context.tr('استماع', 'Preview'),
                        icon: Icon(
                          _previewing == sound.id
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                        ),
                        onPressed: () => _preview(sound.id),
                      )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}
