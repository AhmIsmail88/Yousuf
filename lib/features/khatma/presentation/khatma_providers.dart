import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../../core/time/clock_providers.dart';
import '../../quran/presentation/quran_providers.dart';
import '../data/khatma_repository.dart';
import '../domain/khatma_plan.dart';

final khatmaRepositoryProvider = Provider<KhatmaRepository>(
  (ref) => KhatmaRepository(ref.watch(sharedPreferencesProvider)),
);

/// الخطة الحالية (null = لا خطة).
class KhatmaPlanNotifier extends Notifier<KhatmaPlan?> {
  @override
  KhatmaPlan? build() => ref.watch(khatmaRepositoryProvider).load();

  /// يبدأ خطة جديدة من الصفحة الحالية (أو من ١ إن لم يقرأ).
  Future<void> start({required int days, int? startPage}) async {
    final lastPage = await ref.read(lastReadPageProvider.future);
    final plan = KhatmaPlan(
      days: days,
      startPage: startPage ?? (lastPage < 1 ? 1 : lastPage),
      startDate: ref.read(todayProvider),
    );
    await ref.read(khatmaRepositoryProvider).save(plan);
    state = plan;
    ref.invalidate(khatmaReadProvider);
  }

  /// يبدأ الخطة من الصفحة الأولى في المصحف.
  Future<void> restartFromBeginning({required int days}) =>
      start(days: days, startPage: 1);

  Future<void> cancel() async {
    await ref.read(khatmaRepositoryProvider).clear();
    state = null;
    ref.invalidate(khatmaReadProvider);
  }
}

final khatmaPlanProvider = NotifierProvider<KhatmaPlanNotifier, KhatmaPlan?>(
  KhatmaPlanNotifier.new,
);

/// سجل القراءة: كل الصفحات المقروءة + ما قُرئ اليوم.
typedef KhatmaRead = ({Set<int> all, Set<int> today});

class KhatmaReadNotifier extends Notifier<KhatmaRead> {
  @override
  KhatmaRead build() {
    final repository = ref.watch(khatmaRepositoryProvider);
    final today = ref.watch(todayProvider);
    return (all: repository.readPages(), today: repository.readOn(today));
  }

  /// يعلّم صفحات كمقروءة (لا شيء إن لم توجد خطة).
  Future<void> mark(Iterable<int> pages) async {
    if (ref.read(khatmaPlanProvider) == null) return;
    final fresh = pages.where((p) => !state.all.contains(p)).toList();
    if (fresh.isEmpty) return;
    await ref
        .read(khatmaRepositoryProvider)
        .markRead(fresh, ref.read(todayProvider));
    state = (all: {...state.all, ...fresh}, today: {...state.today, ...fresh});
  }

  Future<void> unmark(int page) async {
    await ref
        .read(khatmaRepositoryProvider)
        .unmark(page, ref.read(todayProvider));
    state = (
      all: {...state.all}..remove(page),
      today: {...state.today}..remove(page),
    );
  }
}

final khatmaReadProvider = NotifierProvider<KhatmaReadNotifier, KhatmaRead>(
  KhatmaReadNotifier.new,
);

/// تقدّم الخطة محسوباً من الصفحات المقروءة فعلاً.
final khatmaProgressProvider = FutureProvider<KhatmaProgress?>((ref) async {
  final plan = ref.watch(khatmaPlanProvider);
  if (plan == null) return null;
  final read = ref.watch(khatmaReadProvider);
  return computeKhatma(
    plan: plan,
    readPages: read.all,
    readToday: read.today,
    now: ref.watch(todayProvider),
  );
});
