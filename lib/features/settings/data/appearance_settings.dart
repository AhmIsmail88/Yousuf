import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../../core/utils/arabic_digits.dart';
import '../../../core/utils/arabic_digits.dart' as digits_ show setDigitStyle;

/// إعدادات المظهر: الثيم وصيغة الأرقام (SPEC §8).
class AppearanceSettings {
  const AppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.digitStyle = DigitStyle.hindi,
  });

  final ThemeMode themeMode;
  final DigitStyle digitStyle;

  AppearanceSettings copyWith({ThemeMode? themeMode, DigitStyle? digitStyle}) =>
      AppearanceSettings(
        themeMode: themeMode ?? this.themeMode,
        digitStyle: digitStyle ?? this.digitStyle,
      );
}

/// يحفظ المظهر محلياً ويحدّث الواجهة فوراً.
///
/// صيغة الأرقام تصل للواجهة عبر الثيم (`DigitsTheme` ← `context.digits`).
/// المتغير العام في `arabic_digits.dart` يُضبط **هنا فقط** (عند القراءة
/// والتغيير) للشيفرة القديمة التي لم تنتقل بعد — لا داخل `build` الواجهات.
class AppearanceNotifier extends Notifier<AppearanceSettings> {
  static const _themeKey = 'appearance.theme_mode';
  static const _digitsKey = 'appearance.digits';

  @override
  AppearanceSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final digits = prefs.getString(_digitsKey);
    final style = digits == 'arabic' ? DigitStyle.arabic : DigitStyle.hindi;
    // الدالة العامة (لا دالة هذا الصنف التي تحمل الاسم نفسه).
    digits_.setDigitStyle(style);
    return AppearanceSettings(
      themeMode: _themeFromId(prefs.getString(_themeKey)),
      digitStyle: style,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await ref.read(sharedPreferencesProvider).setString(_themeKey, mode.name);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setDigitStyle(DigitStyle style) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(_digitsKey, style == DigitStyle.arabic ? 'arabic' : 'hindi');
    digits_.setDigitStyle(style);
    state = state.copyWith(digitStyle: style);
  }

  static ThemeMode _themeFromId(String? id) => switch (id) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

final appearanceProvider =
    NotifierProvider<AppearanceNotifier, AppearanceSettings>(
      AppearanceNotifier.new,
    );
