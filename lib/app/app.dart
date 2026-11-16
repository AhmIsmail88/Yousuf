import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/adhan_playing_bar.dart';
import '../features/prayer/presentation/adhan_playback_provider.dart';
import '../features/quran/presentation/quran_providers.dart';
import '../features/settings/data/appearance_settings.dart';
import '../features/splash/presentation/splash_screen.dart';
import '../l10n/generated/app_localizations.dart';
import 'locale_provider.dart';
import 'router.dart';
import 'theme/app_theme.dart';

const _delegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

const _supportedLocales = <Locale>[Locale('ar'), Locale('en')];

Locale _resolveLocale(Locale? preferred, Iterable<Locale> supported) {
  // العربية افتراضية (SPEC §1)، لكن الاختيار اليدوي للغة يُحترم فوراً.
  if (preferred != null) {
    for (final locale in supported) {
      if (locale.languageCode == preferred.languageCode) {
        return Locale(preferred.languageCode);
      }
    }
  }
  return const Locale('ar');
}

/// شاشة البداية مفعّلة في التطبيق، وتُعطَّل في الاختبارات عبر التجاوز.
final splashEnabledProvider = Provider<bool>((ref) => true);

/// هل انتهت شاشة البداية؟
///
/// تبقى البداية حتى تكتمل حركتها ([kSplashAnimation]) ثم مهلة القراءة
/// ([kSplashHold])، وتُجهَّز قاعدة المحتوى
/// (نسخها أول مرة)، وبحد أقصى [_maxSplash] مهما تأخرت القاعدة.
class AppReadyNotifier extends Notifier<bool> {
  static final _minSplash = kSplashAnimation + kSplashHold;
  static const _maxSplash = Duration(milliseconds: 7500);

  bool _minElapsed = false;
  bool _contentReady = false;

  @override
  bool build() {
    if (!ref.watch(splashEnabledProvider)) return true;
    final minTimer = Timer(_minSplash, () {
      _minElapsed = true;
      _update();
    });
    final maxTimer = Timer(_maxSplash, () => state = true);
    ref.onDispose(() {
      minTimer.cancel();
      maxTimer.cancel();
    });
    // تهيئة القاعدة أثناء البداية (تُستخدم في الرئيسية مباشرة).
    ref
        .read(contentDbProvider.future)
        .then((_) => _markContent(), onError: (_) => _markContent());
    return false;
  }

  void _markContent() {
    _contentReady = true;
    _update();
  }

  void _update() {
    if (_minElapsed && _contentReady) state = true;
  }
}

final appReadyProvider = NotifierProvider<AppReadyNotifier, bool>(
  AppReadyNotifier.new,
);

/// جذر التطبيق: `MaterialApp` واحد بموجّه واحد — البداية والترحيب مسارات
/// فيه (لا تطبيقات متبدّلة)، فلا تضيع الحالة ولا تتكرر الإعدادات.
class YousufApp extends ConsumerWidget {
  const YousufApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final appearance = ref.watch(appearanceProvider);

    return MaterialApp.router(
      title: 'يوسف',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.of(Brightness.light, appearance.digitStyle),
      darkTheme: AppTheme.of(Brightness.dark, appearance.digitStyle),
      themeMode: appearance.themeMode,
      locale: locale ?? const Locale('ar'),
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: _delegates,
      supportedLocales: _supportedLocales,
      localeResolutionCallback: _resolveLocale,
      builder: (context, child) {
        final playing = ref.watch(adhanPlayingProvider).value ?? false;
        return Column(
          children: [
            if (playing) const AdhanPlayingBar(),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
    );
  }
}
