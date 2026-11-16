import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../../core/time/clock_providers.dart';
import '../../../core/utils/arabic_dates.dart';
import '../../quran/presentation/quran_providers.dart';
import '../data/adhkar_repository.dart';
import '../data/user_adhkar_store.dart';
import '../domain/adhkar_models.dart';
import '../domain/user_dhikr.dart';

/// مستودع الأذكار — يقرأ من قاعدة المحتوى المشحونة.
final adhkarRepositoryProvider = FutureProvider<AdhkarRepository>((ref) async {
  final content = await ref.watch(contentDbProvider.future);
  return AdhkarRepository(content);
});

/// أقسام الأذكار كلها (أبواب حصن المسلم + أدعية القرآن).
final adhkarCategoriesProvider = FutureProvider<List<DhikrCategory>>((
  ref,
) async {
  final repository = await ref.watch(adhkarRepositoryProvider.future);
  return repository.categories();
});

/// الأقسام التي تظهر كشرائح سريعة — بالترتيب المطلوب.
const featuredAdhkarSlugs = <String>[
  'quranic',
  'morning',
  'evening',
  'wake',
  'sleep',
  'after_prayer',
  'distress',
  'travel',
];

/// الأقسام المميزة الموجودة فعلاً في القاعدة (بترتيب [featuredAdhkarSlugs]).
final featuredAdhkarCategoriesProvider = FutureProvider<List<DhikrCategory>>((
  ref,
) async {
  final categories = await ref.watch(adhkarCategoriesProvider.future);
  final bySlug = {for (final category in categories) category.slug: category};
  return [
    for (final slug in featuredAdhkarSlugs)
      if (bySlug[slug] != null) bySlug[slug]!,
  ];
});

/// أذكار قسم محدد.
final adhkarOfCategoryProvider = FutureProvider.family<List<Dhikr>, int>((
  ref,
  categoryId,
) async {
  final repository = await ref.watch(adhkarRepositoryProvider.future);
  return repository.dhikrOf(categoryId);
});

/// عدد الأذكار في كل قسم.
final adhkarCategoryCountsProvider = FutureProvider<Map<int, int>>((ref) async {
  final repository = await ref.watch(adhkarRepositoryProvider.future);
  return repository.countsByCategory();
});

/// هل المحتوى مُعتمد من المراجع؟ (content_version.reviewed_by)
final contentReviewedByProvider = FutureProvider<String?>((ref) async {
  final content = await ref.watch(contentDbProvider.future);
  return content.reviewedBy();
});

/// المصدر المعروض: قسم من الكتاب، أو «أذكاري»، أو «كل الأقسام».
class AdhkarSelection extends Notifier<String> {
  /// قيمة خاصة تعني قائمة المستخدم.
  static const String userSource = '__user__';

  /// قيمة خاصة تعني فهرس كل الأقسام.
  static const String allSources = '__all__';

  @override
  String build() => featuredAdhkarSlugs.first;

  void select(String source) => state = source;
}

final adhkarSelectionProvider = NotifierProvider<AdhkarSelection, String>(
  AdhkarSelection.new,
);

/// أذكار المستخدم (محلية فقط).
final userAdhkarStoreProvider = Provider<UserAdhkarStore>(
  (ref) => UserAdhkarStore(ref.watch(sharedPreferencesProvider)),
);

class UserAdhkarNotifier extends Notifier<List<UserDhikr>> {
  @override
  List<UserDhikr> build() => ref.watch(userAdhkarStoreProvider).load();

  Future<void> _persist(List<UserDhikr> next) async {
    state = next;
    await ref.read(userAdhkarStoreProvider).save(next);
  }

  Future<void> add(UserDhikr dhikr) => _persist([...state, dhikr]);

  Future<void> update(UserDhikr dhikr) =>
      _persist([for (final item in state) item.id == dhikr.id ? dhikr : item]);

  Future<void> remove(String id) =>
      _persist(state.where((item) => item.id != id).toList(growable: false));
}

final userAdhkarProvider =
    NotifierProvider<UserAdhkarNotifier, List<UserDhikr>>(
      UserAdhkarNotifier.new,
    );

/// تخزين تقدّم اليوم: مفتاح نصي («d:12» للكتاب، «u:…» للمستخدم).
class AdhkarProgressStore {
  AdhkarProgressStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _prefix = 'adhkar.progress.';

  /// عدد الأيام التي يُحتفظ بتقدّمها (الأقدم يُحذف).
  static const int keepDays = 7;

  static String _key(DateTime date) => '$_prefix${dayKey(date)}';

  /// يحذف تقدّم الأيام الأقدم من [keepDays] — حتى لا تتراكم المفاتيح.
  Future<void> prune(DateTime today) async {
    final oldest = dayKey(
      DateTime(today.year, today.month, today.day - keepDays + 1),
    );
    for (final key in _prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final day = key.substring(_prefix.length);
      // مفاتيح yyyy-MM-dd تُقارن نصياً بترتيب زمني.
      if (day.compareTo(oldest) < 0) await _prefs.remove(key);
    }
  }

  Map<String, int> load(DateTime date) {
    final raw = _prefs.getString(_key(date));
    if (raw == null) return <String, int>{};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          entry.key: (entry.value as num).toInt(),
      };
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> save(DateTime date, Map<String, int> counts) =>
      _prefs.setString(_key(date), jsonEncode(counts));
}

final adhkarProgressStoreProvider = Provider<AdhkarProgressStore>(
  (ref) => AdhkarProgressStore(ref.watch(sharedPreferencesProvider)),
);

/// مفاتيح التقدّم — الذكر من القاعدة والمعرّف النصي للمستخدم.
String dhikrProgressKey(int id) => 'd:$id';
String userDhikrProgressKey(String id) => 'u:$id';

/// تقدّم اليوم الحالي (مفتاح الذكر ← عدد الضغطات).
///
/// مربوط بـ [todayProvider]: عند منتصف الليل يُعاد بناؤه فارغاً لليوم الجديد،
/// ويُحفظ دائماً تحت مفتاح اليوم الذي بُني له — فلا تُنسخ عدّادات الأمس.
class AdhkarProgressNotifier extends Notifier<Map<String, int>> {
  late DateTime _day;

  @override
  Map<String, int> build() {
    _day = ref.watch(todayProvider);
    final store = ref.watch(adhkarProgressStoreProvider);
    unawaited(store.prune(_day));
    return store.load(_day);
  }

  void _persist() {
    unawaited(ref.read(adhkarProgressStoreProvider).save(_day, state));
  }

  /// يزيد عدّاد ذكر — لا يتجاوز عدد التكرار المطلوب.
  void incrementKey(String key, int repeat) {
    final current = state[key] ?? 0;
    if (current >= repeat) return;
    state = {...state, key: current + 1};
    _persist();
  }

  void resetKey(String key) {
    if (!state.containsKey(key)) return;
    state = {...state}..remove(key);
    _persist();
  }

  void resetAll() {
    state = <String, int>{};
    _persist();
  }
}

final adhkarProgressProvider =
    NotifierProvider<AdhkarProgressNotifier, Map<String, int>>(
      AdhkarProgressNotifier.new,
    );
