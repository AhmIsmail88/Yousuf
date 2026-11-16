import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:yousuf/app/theme/app_theme.dart';
import 'package:yousuf/app/locale_provider.dart';
import 'package:yousuf/app/theme/app_colors.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:yousuf/core/platform/adhan_channel.dart';
import 'package:yousuf/core/utils/arabic_dates.dart';
import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/utils/arabic_digits.dart';
import 'package:yousuf/core/utils/quran_text.dart';
import 'package:yousuf/l10n/generated/app_localizations.dart';

import '../../cities/data/cities_repository.dart';
import '../../cities/data/device_location.dart';
import '../../prayer/data/adhan_downloads.dart';
import '../../prayer/data/prayer_settings_repository.dart';
import '../../prayer/domain/adhan_sounds.dart';
import '../../prayer/domain/prayer_times_models.dart';
import '../../prayer/presentation/adhan_readiness.dart';
import '../../prayer/presentation/prayer_providers.dart';
import '../data/appearance_settings.dart';

/// الإعدادات (SPEC §8): الموقع، الحساب، الأذان، التقويم، المظهر، الجاهزية،
/// والمصادر. كل تغيير يؤثر على المواقيت يُحفظ ويُرسل للمحرك فوراً.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _preAlertOptions = [0, 5, 10, 15, 20, 30];
  static const _iqamaOptions = [0, 5, 10, 15, 20];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settingsAsync = ref.watch(prayerSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            context.tr(
              'تعذر تحميل الإعدادات: $error',
              'Could not load settings: $error',
            ),
          ),
        ),
        data: (settings) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _LocationSection(settings: settings),
            const SizedBox(height: 12),
            _CalculationSection(settings: settings),
            const SizedBox(height: 12),
            _AdhanSection(settings: settings),
            const SizedBox(height: 12),
            _CalendarSection(settings: settings),
            const SizedBox(height: 12),
            const _AppearanceSection(),
            const SizedBox(height: 12),
            const _ReadinessSection(),
            const SizedBox(height: 12),
            const _MoreSection(),
          ],
        ),
      ),
    );
  }
}

/// يحفظ الإعدادات ويعيد الجدولة — مع رسالة نجاح/فشل.
Future<void> _apply(
  BuildContext context,
  WidgetRef ref,
  PrayerSettings settings,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final saved = context.tr('تم الحفظ', 'Saved');
  final engineFailed = context.tr(
    'تم الحفظ، لكن تعذر تحديث جدولة الأذان — افتح «جاهزية الأذان»',
    'Saved, but the adhan schedule could not be updated — check Adhan readiness',
  );
  final failed = context.tr('تعذر الحفظ', 'Could not save');
  try {
    final engineOk = await ref
        .read(prayerSettingsControllerProvider)
        .save(settings);
    messenger.showSnackBar(
      SnackBar(content: Text(engineOk ? saved : engineFailed)),
    );
  } catch (error) {
    debugPrint('[Yousuf] حفظ الإعدادات فشل: $error');
    messenger.showSnackBar(SnackBar(content: Text('$failed: $error')));
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
    return Material(
      color: theme.colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.shadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.deepSand),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.trailing,
    this.leading,
  });

  final IconData? leading;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: leading == null
          ? null
          : Icon(leading, size: 22, color: theme.colorScheme.primary),
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: theme.textTheme.labelSmall),
      trailing:
          trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value != null)
                Text(
                  context.digits(value!),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (onTap != null) const Icon(Icons.chevron_left, size: 18),
            ],
          ),
      onTap: onTap,
    );
  }
}

/// ---------- الموقع ----------

class _LocationSection extends ConsumerWidget {
  const _LocationSection({required this.settings});

  final PrayerSettings settings;

  Future<void> _pickCity(BuildContext context, WidgetRef ref) async {
    final city = await showModalBottomSheet<City>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CityPicker(),
    );
    if (city == null) return;
    if (!context.mounted) return;
    await _apply(
      context,
      ref,
      settings.copyWith(location: city.toPrayerLocation()),
    );
  }

  Future<void> _locate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final denied = context.tr(
      'لم يُسمح بالوصول للموقع — اختر مدينتك',
      'Location access denied — pick your city',
    );
    final failed = context.tr(
      'تعذر تحديد الموقع — اختر مدينتك يدوياً',
      'Could not get your location — pick your city manually',
    );
    final result = await locateDeviceFromWidget(ref);
    if (!result.ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.failure == LocateFailure.denied ? denied : failed,
          ),
        ),
      );
      return;
    }
    if (!context.mounted) return;
    await _apply(context, ref, settings.copyWith(location: result.location));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = settings.location;
    final name =
        location.displayName(arabic: context.isArabic) ??
        context.tr('موقع مخصص', 'Custom location');
    final city = location.fromGps
        ? context.tr('موقعي الحالي (قرب $name)', 'My location (near $name)')
        : name;
    final coords =
        '${location.latitude.toStringAsFixed(3)}، '
        '${location.longitude.toStringAsFixed(3)} · ${location.timezoneId}';

    return _SectionCard(
      title: context.tr('الموقع', 'Location'),
      icon: Icons.location_on_outlined,
      children: [
        _SettingTile(
          title: city,
          subtitle: coords,
          onTap: () => _pickCity(context, ref),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _locate(context, ref),
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(context.tr('حدّد موقعي', 'Use my location')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr(
                    'الموقع يبقى على جهازك ولا يُرسل لأي سيرفر',
                    'Your location stays on your device',
                  ),
                  style: Theme.of(context).textTheme.labelSmall,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CityPicker extends ConsumerStatefulWidget {
  const _CityPicker();

  @override
  ConsumerState<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends ConsumerState<_CityPicker> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final citiesAsync = ref.watch(citiesRepositoryProvider);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.tr('ابحث عن مدينة…', 'Search for a city…'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
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
                      final cities = repository.search(_controller.text);
                      if (cities.isEmpty) {
                        return Center(
                          child: Text(
                            context.tr('لا توجد نتائج', 'No results'),
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: cities.length,
                        itemBuilder: (context, index) {
                          final city = cities[index];
                          return ListTile(
                            dense: true,
                            title: Text(city.nameAr),
                            subtitle: Text(
                              '${city.nameEn} · ${city.countryCode}',
                            ),
                            onTap: () => Navigator.pop(context, city),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------- الحساب ----------

class _CalculationSection extends ConsumerWidget {
  const _CalculationSection({required this.settings});

  final PrayerSettings settings;

  Future<void> _pickMethod(BuildContext context, WidgetRef ref) async {
    final method = await showDialog<CalculationMethod>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(context.tr('طريقة الحساب', 'Calculation method')),
        children: [
          for (final option in CalculationMethod.selectable)
            RadioListTile<CalculationMethod>(
              value: option,
              // ignore: deprecated_member_use
              groupValue: settings.method,
              // ignore: deprecated_member_use
              onChanged: (value) => Navigator.pop(dialogContext, value),
              title: Text(option.label(arabic: context.isArabic)),
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
        ],
      ),
    );
    if (method == null) return;
    if (!context.mounted) return;
    await _apply(context, ref, settings.copyWith(method: method));
  }

  Future<void> _pickAdjustments(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<PrayerAdjustments>(
      context: context,
      builder: (_) => _AdjustmentsDialog(initial: settings.adjustments),
    );
    if (result == null) return;
    if (!context.mounted) return;
    await _apply(context, ref, settings.copyWith(adjustments: result));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adjustments = settings.adjustments;
    return _SectionCard(
      title: context.tr('الحساب', 'Calculation'),
      icon: Icons.calculate_outlined,
      children: [
        _SettingTile(
          title: context.tr('طريقة الحساب', 'Calculation method'),
          value: settings.method.label(arabic: context.isArabic),
          onTap: () => _pickMethod(context, ref),
        ),
        _SettingTile(
          title: context.tr('مذهب العصر', 'Asr method'),
          value: settings.madhab.label(arabic: context.isArabic),
          onTap: () async {
            final madhab = await showDialog<AsrMadhab>(
              context: context,
              builder: (dialogContext) => SimpleDialog(
                title: Text(context.tr('مذهب العصر', 'Asr method')),
                children: [
                  for (final option in AsrMadhab.values)
                    RadioListTile<AsrMadhab>(
                      value: option,
                      // ignore: deprecated_member_use
                      groupValue: settings.madhab,
                      // ignore: deprecated_member_use
                      onChanged: (value) => Navigator.pop(dialogContext, value),
                      title: Text(option.label(arabic: context.isArabic)),
                      dense: true,
                    ),
                ],
              ),
            );
            if (madhab == null) return;
            if (!context.mounted) return;
            await _apply(context, ref, settings.copyWith(madhab: madhab));
          },
        ),
        _SettingTile(
          title: context.tr(
            'المسار في العروض العالية (> ٤٨°)',
            'High-latitude rule (> 48°)',
          ),
          value: settings.highLatRule.label(arabic: context.isArabic),
          onTap: () async {
            final rule = await showDialog<HighLatRule>(
              context: context,
              builder: (dialogContext) => SimpleDialog(
                title: Text(
                  context.tr('قاعدة العرض العالي', 'High-latitude rule'),
                ),
                children: [
                  for (final option in HighLatRule.values)
                    RadioListTile<HighLatRule>(
                      value: option,
                      // ignore: deprecated_member_use
                      groupValue: settings.highLatRule,
                      // ignore: deprecated_member_use
                      onChanged: (value) => Navigator.pop(dialogContext, value),
                      title: Text(option.label(arabic: context.isArabic)),
                      dense: true,
                    ),
                ],
              ),
            );
            if (rule == null) return;
            if (!context.mounted) return;
            await _apply(context, ref, settings.copyWith(highLatRule: rule));
          },
        ),
        _SettingTile(
          title: context.tr('تعديل المواقيت بالدقائق', 'Minute adjustments'),
          subtitle: adjustments.isZero
              ? context.tr(
                  'لا تعديلات — المواقيت كما تُحسب',
                  'No adjustments — times as calculated',
                )
              : [
                  for (final prayer in PrayerName.values)
                    if (adjustments.toMap()[prayer.id] != 0)
                      '${prayer.label(arabic: context.isArabic)} ${context.digits(_signed(adjustments.toMap()[prayer.id]!))}',
                ].join(' · '),
          onTap: () => _pickAdjustments(context, ref),
        ),
        _SettingTile(
          title: context.tr('تنبيه قبل الصلاة', 'Pre-prayer alert'),
          value: settings.prePrayerAlertMinutes == 0
              ? context.tr('مطفأ', 'Off')
              : context.tr(
                  '${settings.prePrayerAlertMinutes} دقيقة',
                  '${settings.prePrayerAlertMinutes} min',
                ),
          onTap: () async {
            final minutes = await _pickNumber(
              context,
              title: context.tr('التنبيه قبل الصلاة', 'Pre-prayer alert'),
              options: SettingsScreen._preAlertOptions,
              current: settings.prePrayerAlertMinutes,
            );
            if (minutes == null) return;
            if (!context.mounted) return;
            await _apply(
              context,
              ref,
              settings.copyWith(prePrayerAlertMinutes: minutes),
            );
          },
        ),
        _SettingTile(
          title: context.tr(
            'تذكير الإقامة بعد الأذان',
            'Iqama reminder after adhan',
          ),
          value: settings.iqamaReminderMinutes == 0
              ? context.tr('مطفأ', 'Off')
              : context.tr(
                  '${settings.iqamaReminderMinutes} دقيقة',
                  '${settings.iqamaReminderMinutes} min',
                ),
          onTap: () async {
            final minutes = await _pickNumber(
              context,
              title: context.tr('تذكير الإقامة', 'Iqama reminder'),
              options: SettingsScreen._iqamaOptions,
              current: settings.iqamaReminderMinutes,
            );
            if (minutes == null) return;
            if (!context.mounted) return;
            await _apply(
              context,
              ref,
              settings.copyWith(iqamaReminderMinutes: minutes),
            );
          },
        ),
      ],
    );
  }
}

String _signed(int minutes) =>
    minutes == 0 ? '٠' : (minutes > 0 ? '+$minutes' : '$minutes');

Future<int?> _pickNumber(
  BuildContext context, {
  required String title,
  required List<int> options,
  required int current,
}) {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(title),
      children: [
        for (final option in options)
          RadioListTile<int>(
            value: option,
            // ignore: deprecated_member_use
            groupValue: current,
            // ignore: deprecated_member_use
            onChanged: (value) => Navigator.pop(dialogContext, value),
            title: Text(
              option == 0
                  ? context.tr('مطفأ', 'Off')
                  : context.tr(
                      '${context.digits(option)} دقيقة',
                      '$option min',
                    ),
            ),
            dense: true,
          ),
      ],
    ),
  );
}

class _AdjustmentsDialog extends StatefulWidget {
  const _AdjustmentsDialog({required this.initial});

  final PrayerAdjustments initial;

  @override
  State<_AdjustmentsDialog> createState() => _AdjustmentsDialogState();
}

class _AdjustmentsDialogState extends State<_AdjustmentsDialog> {
  late final Map<String, int> _values = widget.initial.toMap();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        context.tr('تعديل المواقيت (دقائق)', 'Adjust times (minutes)'),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final prayer in PrayerName.values)
              Row(
                children: [
                  Expanded(child: Text(prayer.label(arabic: context.isArabic))),
                  IconButton(
                    onPressed: _values[prayer.id]! > -30
                        ? () => setState(
                            () => _values[prayer.id] = _values[prayer.id]! - 1,
                          )
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    visualDensity: VisualDensity.compact,
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      _signed(_values[prayer.id]!),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: _values[prayer.id]! < 30
                        ? () => setState(
                            () => _values[prayer.id] = _values[prayer.id]! + 1,
                          )
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            PrayerAdjustments.fromMap(_values.cast<String, dynamic>()),
          ),
          child: Text(context.tr('حفظ', 'Save')),
        ),
      ],
    );
  }
}

/// ---------- الأذان ----------

const _adhanModes = <(String, String, String)>[
  ('full', 'أذان كامل', 'Full adhan'),
  ('takbir', 'تكبير فقط', 'Takbir only'),
  ('notification', 'إشعار صامت', 'Silent notification'),
  ('off', 'مطفأ', 'Off'),
];

String _modeLabel(BuildContext context, String mode) {
  for (final (id, ar, en) in _adhanModes) {
    if (id == mode) return context.tr(ar, en);
  }
  return context.tr('أذان كامل', 'Full adhan');
}

/// الأصوات الموجودة فعلاً في الحزمة (يقرؤها المحرك الأصلي).
final _availableAdhanSoundsProvider = FutureProvider<List<String>>((ref) async {
  if (!AdhanChannel.isSupported) return const [];
  try {
    return (await AdhanChannel().status()).availableSounds;
  } catch (_) {
    return const [];
  }
});

class _AdhanSection extends ConsumerWidget {
  const _AdhanSection({required this.settings});

  final PrayerSettings settings;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    String prayerId,
    List<String> available,
  ) async {
    final current = settings.soundFor(prayerId);
    final result = await showDialog<PrayerSound>(
      context: context,
      builder: (_) => _PrayerSoundDialog(
        initial: current,
        available: available,
        prayerLabel: PrayerName.fromId(prayerId)
            .label(arabic: context.isArabic),
      ),
    );
    if (result == null) return;
    if (!context.mounted) return;
    await _apply(
      context,
      ref,
      settings.copyWith(
        prayerSounds: {...settings.prayerSounds, prayerId: result},
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available =
        ref.watch(_availableAdhanSoundsProvider).value ?? const <String>[];
    final arabic = context.isArabic;
    return _SectionCard(
      title: context.tr('الأذان', 'Adhan'),
      icon: Icons.volume_up_outlined,
      children: [
        for (final prayer in PrayerName.values)
          if (prayer != PrayerName.sunrise)
            Builder(
              builder: (context) {
                final sound = settings.soundFor(prayer.id);
                final mode = _modeLabel(context, sound.mode);
                final voice = adhanSoundById(
                  effectiveAdhanSound(sound.sound, available),
                ).label(arabic: arabic);
                final showVoice =
                    sound.mode == 'full' || sound.mode == 'takbir';
                return _SettingTile(
                  title: prayer.label(arabic: arabic),
                  value: showVoice ? '$mode · $voice' : mode,
                  onTap: () => _edit(context, ref, prayer.id, available),
                );
              },
            ),
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(context.tr('احترام الوضع الصامت', 'Respect silent mode')),
          subtitle: Text(
            context.tr(
              'إشعار بلا صوت إن كان الهاتف صامتاً',
              'Notification without sound when the phone is silent',
            ),
          ),
          value: settings.respectSilentMode,
          onChanged: (value) =>
              _apply(context, ref, settings.copyWith(respectSilentMode: value)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            context.tr(
              'أثناء المكالمات يصلك إشعار بلا صوت. التنبيه قبل الصلاة '
                  'وتذكير الإقامة بصوت إشعار الهاتف فقط.',
              'During calls you get a silent notification. Pre-prayer and '
                  'iqama reminders use the phone notification sound only.',
            ),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}

class _PrayerSoundDialog extends ConsumerStatefulWidget {
  const _PrayerSoundDialog({
    required this.initial,
    required this.available,
    required this.prayerLabel,
  });

  final PrayerSound initial;
  final List<String> available;
  final String prayerLabel;

  @override
  ConsumerState<_PrayerSoundDialog> createState() => _PrayerSoundDialogState();
}

class _PrayerSoundDialogState extends ConsumerState<_PrayerSoundDialog> {
  late String _mode = widget.initial.mode;
  late String _sound = effectiveAdhanSound(
    widget.initial.sound,
    widget.available,
  );
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

  Future<void> _download(AdhanSound sound) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr(
      'تعذر تحميل الصوت — تحقق من الاتصال وحاول مجدداً',
      'Could not download — check your connection and retry',
    );
    try {
      await ref.read(adhanDownloadsProvider.notifier).download(sound);
      ref.invalidate(_availableAdhanSoundsProvider);
      if (mounted) setState(() => _sound = sound.id);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final arabic = context.isArabic;
    final voiced = _mode == 'full' || _mode == 'takbir';
    final available =
        ref.watch(_availableAdhanSoundsProvider).value ?? widget.available;
    final progress = ref.watch(adhanDownloadsProvider);
    final sounds = selectableAdhanSounds(available);
    final downloadable = downloadableAdhanSounds(available);
    return AlertDialog(
      title: Text(widget.prayerLabel),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('نوع التنبيه', 'Alert type'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final (id, ar, en) in _adhanModes)
              RadioListTile<String>(
                value: id,
                // ignore: deprecated_member_use
                groupValue: _mode,
                // ignore: deprecated_member_use
                onChanged: (value) => setState(() => _mode = value!),
                title: Text(context.tr(ar, en)),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            const Divider(),
            Text(
              context.tr('صوت المؤذن', 'Muezzin'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            for (final sound in sounds)
              RadioListTile<String>(
                value: sound.id,
                // ignore: deprecated_member_use
                groupValue: _sound,
                // ignore: deprecated_member_use
                onChanged: voiced
                    ? (value) => setState(() => _sound = value!)
                    : null,
                title: Text(sound.label(arabic: arabic)),
                dense: true,
                contentPadding: EdgeInsets.zero,
                secondary: IconButton(
                  tooltip: context.tr('استماع', 'Preview'),
                  icon: Icon(
                    _previewing == sound.id
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                  ),
                  onPressed: AdhanChannel.isSupported
                      ? () => _preview(sound.id)
                      : null,
                ),
              ),
            if (downloadable.isNotEmpty) ...[
              const Divider(),
              Text(
                context.tr('أصوات للتحميل', 'Voices to download'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                context.tr(
                  'من AlAdhan — حوالي ٤ ميجابايت لكل صوت، تُحفظ على جهازك',
                  'From AlAdhan — about 4 MB each, saved on your device',
                ),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              for (final sound in downloadable)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(sound.label(arabic: arabic)),
                  trailing: progress.containsKey(sound.id)
                      ? SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            value: (progress[sound.id] ?? 0) > 0
                                ? progress[sound.id]
                                : null,
                            strokeWidth: 3,
                          ),
                        )
                      : IconButton(
                          tooltip: context.tr('تحميل', 'Download'),
                          icon: const Icon(Icons.download_outlined),
                          onPressed: () => _download(sound),
                        ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('إلغاء', 'Cancel')),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, PrayerSound(mode: _mode, sound: _sound)),
          child: Text(context.tr('حفظ', 'Save')),
        ),
      ],
    );
  }
}

/// ---------- التقويم ----------

class _CalendarSection extends ConsumerWidget {
  const _CalendarSection({required this.settings});

  final PrayerSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = hijriDay(
      DateTime.now(),
      offsetDays: settings.hijriOffsetDays,
    );
    return _SectionCard(
      title: context.tr('التقويم', 'Calendar'),
      icon: Icons.calendar_month_outlined,
      children: [
        _SettingTile(
          title: context.tr('إزاحة التاريخ الهجري', 'Hijri date offset'),
          subtitle: preview == null
              ? context.tr(
                  'تعذر حساب التاريخ لهذه السنة',
                  'Could not compute the date',
                )
              : context.tr('اليوم: ', 'Today: ') + context.formatHijri(preview),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: context.tr('يوم أقل', 'One day less'),
                onPressed: settings.hijriOffsetDays > -2
                    ? () => _apply(
                        context,
                        ref,
                        settings.copyWith(
                          hijriOffsetDays: settings.hijriOffsetDays - 1,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                context.digits(_signed(settings.hijriOffsetDays)),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              IconButton(
                tooltip: context.tr('يوم أكثر', 'One day more'),
                onPressed: settings.hijriOffsetDays < 2
                    ? () => _apply(
                        context,
                        ref,
                        settings.copyWith(
                          hijriOffsetDays: settings.hijriOffsetDays + 1,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text(
            context.tr(
              'تُضاف الإزاحة عند اختلاف رؤية الهلال في بلدك (±٢ يوم).',
              'Use an offset when the moon sighting in your country differs (±2 days).',
            ),
            style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }
}

/// ---------- المظهر ----------

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final locale = ref.watch(localeProvider);
    final notifier = ref.read(appearanceProvider.notifier);

    return _SectionCard(
      title: context.tr('المظهر واللغة', 'Appearance & language'),
      icon: Icons.palette_outlined,
      children: [
        _SegmentedRow<ThemeMode>(
          title: context.tr('الثيم', 'Theme'),
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              label: Text(context.tr('النظام', 'System')),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text(context.tr('فاتح', 'Light')),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text(context.tr('داكن', 'Dark')),
            ),
          ],
          selected: appearance.themeMode,
          onChanged: notifier.setThemeMode,
        ),
        _SegmentedRow<DigitStyle>(
          title: context.tr('الأرقام', 'Digits'),
          segments: const [
            ButtonSegment(value: DigitStyle.hindi, label: Text('١٢٣')),
            ButtonSegment(value: DigitStyle.arabic, label: Text('123')),
          ],
          selected: appearance.digitStyle,
          onChanged: notifier.setDigitStyle,
        ),
        _SegmentedRow<String>(
          title: context.tr('اللغة', 'Language'),
          segments: const [
            ButtonSegment(value: 'ar', label: Text('العربية')),
            ButtonSegment(value: 'en', label: Text('English')),
          ],
          selected: locale?.languageCode ?? 'ar',
          onChanged: (code) =>
              ref.read(localeProvider.notifier).select(Locale(code)),
        ),
      ],
    );
  }
}

/// صف عنوان + أزرار اختيار بعرض كامل — آمن من الفائض على الشاشات الضيقة.
class _SegmentedRow<T> extends StatelessWidget {
  const _SegmentedRow({
    required this.title,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: segments,
              selected: {selected},
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------- الجاهزية ----------

class _ReadinessSection extends StatelessWidget {
  const _ReadinessSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: context.tr('جاهزية الأذان', 'Adhan readiness'),
      icon: Icons.alarm_on_outlined,
      children: const [AdhanReadinessPanel()],
    );
  }
}

/// ---------- عن التطبيق ----------

/// خاتمة «عن التطبيق»: دعاء من سورة التحريم (٨) — بنص المصحف (Tanzil) حرفياً.
const String _closingAyah =
    'رَبَّنَآ أَتْمِمْ لَنَا نُورَنَا وَٱغْفِرْ لَنَآ ۖ إِنَّكَ عَلَىٰ كُلِّ شَىْءٍ قَدِيرٌ';

/// «لا تنسنا من دعائك» ثم آية التحريم — آخر ما في «عن التطبيق».
class _ClosingDua extends StatelessWidget {
  const _ClosingDua();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          context.tr(
            'لا تنسنا من صالح دعائك',
            'Please remember us in your duas',
          ),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          // مسافة غير قابلة للفصل: يبقى رقم الآية ملتصقاً بآخر كلمة.
          '${displayQuranText(_closingAyah)}${ayahMark(8)}',
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontFamily: AppTheme.quranFont,
            fontFamilyFallback: AppTheme.quranFallback,
            fontSize: 19,
            height: 1.9,
            color: AppColors.deepTeal,
          ),
        ),
      ],
    );
  }
}

class _MoreSection extends StatelessWidget {
  const _MoreSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: context.tr('عن التطبيق', 'About'),
      icon: Icons.info_outline,
      children: [
        // بطاقة الهوية: الشعار والاسم والإصدار.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  'assets/brand/icon_master_1024.png',
                  width: 52,
                  height: 52,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(
                        'يوسف — رفيقك في الطاعة',
                        'Yousuf — your companion in faith',
                      ),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr(
                        'الإصدار ${context.digits('1.0.0')} · مجاني بلا إعلانات',
                        'Version 1.0.0 · Free, no ads',
                      ),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 16, indent: 16, endIndent: 16),
        _SettingTile(
          leading: Icons.auto_stories_outlined,
          title: context.tr('عن يوسف', 'About Yousuf'),
          subtitle: context.tr('الفكرة والمبادئ', 'The idea and principles'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
        ),
        _SettingTile(
          leading: Icons.download_for_offline_outlined,
          title: context.tr('التحميلات', 'Downloads'),
          subtitle: context.tr(
            'التلاوات المحفوظة على جهازك',
            'Recitations saved on your device',
          ),
          onTap: () => context.push('/downloads'),
        ),
        _SettingTile(
          leading: Icons.verified_outlined,
          title: context.tr('المصادر والتراخيص', 'Sources & licenses'),
          subtitle: context.tr(
            'مصدر كل نص وصوت في التطبيق',
            'Where every text and recording comes from',
          ),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const SourcesPage())),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: _ClosingDua(),
        ),
      ],
    );
  }
}

/// شاشة المصادر والتراخيص — شرط ترخيص Tanzil (SPEC §4).
class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sources = <(String, String)>[
      (
        context.tr('نص القرآن الكريم', 'Quran text'),
        context.tr(
          'Tanzil.net — رخصة CC BY 3.0، نسخ حرفي بلا تعديل. https://tanzil.net',
          'Tanzil.net — CC BY 3.0, verbatim copy without changes. https://tanzil.net',
        ),
      ),
      (
        context.tr(
          'بيانات السور والصفحات والأجزاء',
          'Surah, page and juz data',
        ),
        context.tr(
          'alquran.cloud (نسخة Tanzil) — نفس النص العثماني والإملائي.',
          'alquran.cloud (Tanzil edition) — same Uthmani and simple text.',
        ),
      ),
      (
        context.tr('قاعدة المدن', 'Cities database'),
        context.tr(
          'GeoNames — رخصة CC BY 4.0، مع تنقية الأسماء العربية.',
          'GeoNames — CC BY 4.0, with cleaned Arabic names.',
        ),
      ),
      (
        context.tr('الخطوط', 'Fonts'),
        'Amiri, IBM Plex Sans Arabic, Cinzel — SIL Open Font License.',
      ),
      (
        context.tr('تسجيل الأذان', 'Adhan recording'),
        context.tr(
          'Beautiful adhan — Adam-synagda، رخصة CC0 1.0. '
              '«The Adhan» بصوت عاقب عزيز — رفع Atcovi، رخصة CC BY-SA 4.0. '
              '«Azan» — Andrewler، رخصة CC BY-SA 4.0. '
              'كلها من Wikimedia Commons، مُعاد ترميزها إلى OGG أحادي دون تعديل المحتوى. '
              'أذانات علي ملا وعبد الباسط والحصري والمنشاوي ومحمد رفعت والبنا: '
              'تسجيلات مجانية قدّمها مالك التطبيق، وحقوقها لأصحابها. '
              'أصوات التحميل الاختياري (العفاسي، النفيس، الزهراني، أوزجان) من صفحة '
              '«Download Adhans» في AlAdhan (Islamic Network)، تُحمَّل إلى جهازك فقط.',
          'Beautiful adhan — Adam-synagda, CC0 1.0. '
              '"The Adhan" by Aaqib Azeez — uploaded by Atcovi, CC BY-SA 4.0. '
              '"Azan" — Andrewler, CC BY-SA 4.0. '
              'All from Wikimedia Commons, re-encoded to mono OGG with no content changes. '
              'Adhans by Ali Mulla, Abdul Basit, al-Husary, al-Minshawi, Muhammad Rifaat and al-Banna: '
              'free recordings provided by the app owner; rights remain with their holders. '
              'Optional downloads (Alafasy, al-Nafees, Al-Zahrani, Özcan) come from the '
              '"Download Adhans" page of AlAdhan (Islamic Network), saved on your device only.',
        ),
      ),
      (
        context.tr(
          'التلاوات (تحميل اختياري)',
          'Recitations (optional download)',
        ),
        context.tr(
          'Islamic Network CDN وEveryAyah — للاستخدام الشخصي والتعليمي المجاني، '
              'تُبثّ وتُحفظ على جهازك فقط. حقوق التسجيلات لأصحابها من القرّاء.',
          'Islamic Network CDN and EveryAyah — free personal and educational use, '
              "streamed and stored on your device only. Recordings remain the reciters' copyright.",
        ),
      ),
      (
        context.tr('الأذكار', 'Adhkar'),
        context.tr(
          'حصن المسلم — الشيخ سعيد بن علي بن وهف القحطاني. المتن والتخريج من نسخة '
              'مفتوحة برخصة MIT (abdalrhmanreda/islamic-data-assets). الآيات من نص المصحف. '
              'المحتوى قيد المراجعة الشرعية.',
          'Hisn al-Muslim — Sheikh Said al-Qahtani. Text from an MIT-licensed open '
              'dataset (abdalrhmanreda/islamic-data-assets); verses from the Mushaf text. '
              'Under scholarly review.',
        ),
      ),
      (
        context.tr('الحديث', 'Hadith'),
        context.tr(
          'الأربعون النووية — hadith-api (ملكية عامة، Unlicense).',
          "An-Nawawi's Forty — hadith-api (public domain, Unlicense).",
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('المصادر والتراخيص', 'Sources & licenses')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (title, body) in sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(body, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// «عن يوسف» — قصة الفكرة ومبادئها (SPEC §7.10).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget principle(IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('عن يوسف', 'About Yousuf'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Image.asset(
              'assets/brand/logo_splash.png',
              height: 110,
              fit: BoxFit.contain,
              semanticLabel: 'يوسف',
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr('رفيقك في الطاعة', 'Your companion in faith'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'Amiri',
              color: AppColors.deepTeal,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                context.tr(
                  'الإصدار ${context.digits('1.0.0')}',
                  'Version 1.0.0',
                ),
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.tr(
              'يوسف تطبيق إسلامي شامل يجمع لك المواقيت والأذان والقبلة والمصحف '
                  'والأذكار والختمة وتعليم الأطفال في مكان واحد، بتصميم هادئ '
                  'يعينك على الطاعة كل يوم.',
              'Yousuf brings prayer times, adhan, qibla, the Quran, adhkar, '
                  'khatma plans and kids learning together in one calm app '
                  'that helps you stay consistent every day.',
            ),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
          ),
          const SizedBox(height: 22),
          principle(
            Icons.volunteer_activism_outlined,
            context.tr('مجاني بالكامل', 'Completely free'),
            context.tr(
              'بلا إعلانات ولا مشتريات ولا اشتراكات — صدقة جارية.',
              'No ads, purchases or subscriptions — an ongoing charity.',
            ),
          ),
          principle(
            Icons.lock_outline,
            context.tr('خصوصيتك أولاً', 'Your privacy first'),
            context.tr(
              'لا حسابات، وموقعك وبياناتك لا تغادر جهازك ولا تُرسل إلى أي سيرفر.',
              'No accounts. Your location and data never leave your device.',
            ),
          ),
          principle(
            Icons.cloud_off_outlined,
            context.tr('يعمل دون إنترنت', 'Works offline'),
            context.tr(
              'المواقيت والأذان والقبلة والمصحف والأذكار تعمل من أول تشغيل.',
              'Prayer times, adhan, qibla, Quran and adhkar work from the first launch.',
            ),
          ),
          principle(
            Icons.menu_book_outlined,
            context.tr('محتوى موثّق', 'Trusted content'),
            context.tr(
              'نص المصحف من Tanzil، والأذكار من «حصن المسلم»، ولكل محتوى مصدره '
                  'في صفحة «المصادر والتراخيص».',
              'Quran text from Tanzil, adhkar from Hisn al-Muslim, and every '
                  'source listed under "Sources & licenses".',
            ),
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 16),
          const _ClosingDua(),
        ],
      ),
    );
  }
}
