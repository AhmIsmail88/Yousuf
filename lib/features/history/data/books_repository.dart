import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';

/// آخر صفحة قُرئت من كل كتاب في المكتبة (للمتابعة) — رقمها في ترتيب الكتاب.
class BookPositionNotifier extends Notifier<Map<String, int>> {
  static String _key(String slug) => 'books.position.$slug';

  @override
  Map<String, int> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return {
      for (final key in prefs.getKeys())
        if (key.startsWith('books.position.'))
          key.substring('books.position.'.length): prefs.getInt(key) ?? 0,
    };
  }

  Future<void> save(String slug, int page) async {
    await ref.read(sharedPreferencesProvider).setInt(_key(slug), page);
    state = {...state, slug: page};
  }
}

final bookPositionProvider =
    NotifierProvider<BookPositionNotifier, Map<String, int>>(
      BookPositionNotifier.new,
    );
