import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';

/// وضع الحفظ (SPEC §7.3): نص الصفحة يظهر **ممسوحاً**، ولا يبقى ظاهراً إلا
/// رقم الآية. يقرأ الطفل/الحافظ الآية من حفظه ثم يضغطها فتُكشف للتحقق.
///
/// الحالة محفوظة محلياً حتى يبقى الوضع كما اختاره المستخدم بين الجلسات.
const String hifzModeKey = 'quran.hifz_mode';

class HifzModeNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(hifzModeKey) ?? false;

  Future<void> set(bool value) async {
    await ref.read(sharedPreferencesProvider).setBool(hifzModeKey, value);
    state = value;
  }

  Future<void> toggle() => set(!state);
}

final hifzModeProvider = NotifierProvider<HifzModeNotifier, bool>(
  HifzModeNotifier.new,
);

/// هل يُخفى نص هذه الآية؟ (دالة نقية — تُختبر وحدها)
bool isAyahMasked({
  required bool hifz,
  required Set<int> revealed,
  required int ayahId,
}) => hifz && !revealed.contains(ayahId);
