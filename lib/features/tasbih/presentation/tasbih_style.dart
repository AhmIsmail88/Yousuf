import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';

/// شكل عرض المسبحة: كلاسيكي (حبات) أو إلكتروني (عدّاد رقمي).
enum TasbihStyle { classic, electronic }

const String _key = 'tasbih.style';

class TasbihStyleNotifier extends Notifier<TasbihStyle> {
  @override
  TasbihStyle build() {
    final value = ref.watch(sharedPreferencesProvider).getString(_key);
    return value == 'electronic' ? TasbihStyle.electronic : TasbihStyle.classic;
  }

  Future<void> set(TasbihStyle style) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          _key,
          style == TasbihStyle.electronic ? 'electronic' : 'classic',
        );
    state = style;
  }

  Future<void> toggle() => set(
    state == TasbihStyle.classic ? TasbihStyle.electronic : TasbihStyle.classic,
  );
}

final tasbihStyleProvider = NotifierProvider<TasbihStyleNotifier, TasbihStyle>(
  TasbihStyleNotifier.new,
);
