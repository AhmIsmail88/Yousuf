import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تفضيلات التطبيق — تُحقن عند بدء التشغيل في main() بعد تحميلها.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  );
});

/// هل أكمل المستخدم شاشة الترحيب؟ (SPEC §7.1)
class OnboardingDoneNotifier extends Notifier<bool> {
  static const _key = 'onboarding.done';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  void complete() {
    ref.read(sharedPreferencesProvider).setBool(_key, true);
    state = true;
  }
}

final onboardingDoneProvider = NotifierProvider<OnboardingDoneNotifier, bool>(
  OnboardingDoneNotifier.new,
);
