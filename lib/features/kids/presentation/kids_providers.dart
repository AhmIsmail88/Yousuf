import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../quran/data/quran_audio_repository.dart';
import '../../quran/domain/quran_reciter.dart';
import '../data/kids_repository.dart';
import '../domain/kid_profile.dart';

final kidsRepositoryProvider = Provider<KidsRepository>(
  (ref) => KidsRepository(ref.watch(sharedPreferencesProvider)),
);

/// ملفات الأطفال.
class KidProfilesNotifier extends Notifier<List<KidProfile>> {
  @override
  List<KidProfile> build() => ref.watch(kidsRepositoryProvider).loadProfiles();

  Future<KidProfile> add(String name, int avatar) async {
    final profile = KidProfile(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'صديق يوسف' : name.trim(),
      avatar: avatar,
    );
    final next = [...state, profile];
    await ref.read(kidsRepositoryProvider).saveProfiles(next);
    state = next;
    return profile;
  }

  Future<void> remove(String id) async {
    final next = state.where((profile) => profile.id != id).toList();
    await ref.read(kidsRepositoryProvider).saveProfiles(next);
    state = next;
    if (ref.read(kidsRepositoryProvider).activeProfileId() == id) {
      await ref.read(kidsRepositoryProvider).setActiveProfile(null);
      ref.invalidate(activeKidProvider);
    }
  }

  /// يضيف نجوماً لملف (آية سُمّعت صحيحة، أو إتمام سورة).
  Future<void> awardStar(String id, {int count = 1}) async {
    final next = [
      for (final profile in state)
        profile.id == id
            ? profile.copyWith(stars: profile.stars + count)
            : profile,
    ];
    await ref.read(kidsRepositoryProvider).saveProfiles(next);
    state = next;
  }
}

final kidProfilesProvider =
    NotifierProvider<KidProfilesNotifier, List<KidProfile>>(
      KidProfilesNotifier.new,
    );

/// الطفل النشط حالياً.
class ActiveKidNotifier extends Notifier<KidProfile?> {
  @override
  KidProfile? build() {
    final id = ref.watch(kidsRepositoryProvider).activeProfileId();
    if (id == null) return null;
    for (final profile in ref.watch(kidProfilesProvider)) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Future<void> select(KidProfile? profile) async {
    await ref.read(kidsRepositoryProvider).setActiveProfile(profile?.id);
    state = profile;
  }
}

final activeKidProvider = NotifierProvider<ActiveKidNotifier, KidProfile?>(
  ActiveKidNotifier.new,
);

/// تقدّم الطفل النشط في جزء عمّ.
class KidProgressNotifier extends Notifier<KidProgress> {
  @override
  KidProgress build() {
    final kid = ref.watch(activeKidProvider);
    if (kid == null) return const KidProgress(completedSurahs: {});
    return ref.watch(kidsRepositoryProvider).loadProgress(kid.id);
  }

  /// يسجّل إتمام سورة ويعيد true إن كانت جديدة (لإضافة نجمة).
  Future<bool> completeSurah(int surahId) async {
    final kid = ref.read(activeKidProvider);
    if (kid == null) return false;
    if (state.completedSurahs.contains(surahId)) return false;
    final next = state.copyWith(
      completedSurahs: {...state.completedSurahs, surahId},
    );
    await ref.read(kidsRepositoryProvider).saveProgress(kid.id, next);
    await ref.read(kidProfilesProvider.notifier).awardStar(kid.id);
    state = next;
    return true;
  }

  /// آية سُمّعت صحيحة: نجمة جديدة إن لم تُسجَّل من قبل.
  Future<bool> memorize(int ayahId) async {
    final kid = ref.read(activeKidProvider);
    if (kid == null || state.memorizedAyat.contains(ayahId)) return false;
    final next = state.copyWith(
      memorizedAyat: {...state.memorizedAyat, ayahId},
    );
    await ref.read(kidsRepositoryProvider).saveProgress(kid.id, next);
    await ref.read(kidProfilesProvider.notifier).awardStar(kid.id);
    state = next;
    return true;
  }
}

final kidProgressProvider = NotifierProvider<KidProgressNotifier, KidProgress>(
  KidProgressNotifier.new,
);

/// رمز الخروج (٤ أرقام) — null يعني بلا رمز.
class KidPinNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(kidsRepositoryProvider).pin();

  Future<void> set(String? pin) async {
    await ref.read(kidsRepositoryProvider).savePin(pin);
    state = (pin == null || pin.length != 4) ? null : pin;
  }
}

final kidPinProvider = NotifierProvider<KidPinNotifier, String?>(
  KidPinNotifier.new,
);

/// قارئ قسم الأطفال — المصحف المعلّم (الحصري أو المنشاوي مع الأطفال).
class KidReciterNotifier extends Notifier<QuranReciter> {
  static const _key = 'kids.reciter';

  @override
  QuranReciter build() {
    final id = ref.watch(sharedPreferencesProvider).getString(_key);
    return kTeacherReciters.firstWhere(
      (reciter) => reciter.id == id,
      orElse: () => kTeacherReciters.first,
    );
  }

  Future<void> select(QuranReciter reciter) async {
    await ref.read(sharedPreferencesProvider).setString(_key, reciter.id);
    state = reciter;
  }
}

final kidReciterProvider = NotifierProvider<KidReciterNotifier, QuranReciter>(
  KidReciterNotifier.new,
);

/// مستودع صوت قارئ الأطفال (يُغلق عند تغيير القارئ).
final kidAudioRepositoryProvider = Provider<QuranAudioRepository>((ref) {
  final repository = QuranAudioRepository(
    reciter: ref.watch(kidReciterProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});
