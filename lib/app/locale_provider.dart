import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/prefs/shared_preferences_provider.dart';

/// لغة الواجهة المختارة — null يعني اتباع لغة النظام (العربية افتراضياً).
class LocaleNotifier extends Notifier<Locale?> {
  static const _key = 'app.locale';

  @override
  Locale? build() {
    final code = ref.watch(sharedPreferencesProvider).getString(_key);
    return code == null ? null : Locale(code);
  }

  void select(Locale locale) {
    ref.read(sharedPreferencesProvider).setString(_key, locale.languageCode);
    state = locale;
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  LocaleNotifier.new,
);
