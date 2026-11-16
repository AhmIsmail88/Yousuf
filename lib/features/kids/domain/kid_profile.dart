/// نماذج وضع الأطفال (SPEC §7.9، م4).
library;

/// صور رمزية بسيطة (إيموجي) — بلا أصول خارجية.
const List<String> kidAvatars = ['🌙', '⭐', '🕌', '📖', '🕋', '🧸'];

/// ملف طفل: اسم + صورة رمزية + نجوم.
class KidProfile {
  const KidProfile({
    required this.id,
    required this.name,
    required this.avatar,
    this.stars = 0,
  });

  final String id;
  final String name;

  /// فهرس الصورة في [kidAvatars].
  final int avatar;
  final int stars;

  String get avatarEmoji => kidAvatars[avatar.clamp(0, kidAvatars.length - 1)];

  KidProfile copyWith({String? name, int? avatar, int? stars}) => KidProfile(
    id: id,
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    stars: stars ?? this.stars,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'avatar': avatar,
    'stars': stars,
  };

  factory KidProfile.fromJson(Map<String, dynamic> json) => KidProfile(
    id: json['id'] as String,
    name: (json['name'] as String?)?.trim().isNotEmpty == true
        ? json['name'] as String
        : 'صديق يوسف',
    avatar: (json['avatar'] as num?)?.toInt() ?? 0,
    stars: (json['stars'] as num?)?.toInt() ?? 0,
  );

  /// المصحف كامل يبدأ من الفاتحة إلى الناس.
  static const int firstSurah = 1;
  static const int lastSurah = 114;
  static const int totalSurahs = 114;
}

/// إنجاز طفل: السور المكتملة + الآيات التي سمّعها صحيحة.
///
/// نجمة لكل آية يقرؤها الطفل من حفظه صحيحة (أول مرة)، ونجمة إضافية عند
/// إتمام السورة كاملة.
class KidProgress {
  const KidProgress({
    required this.completedSurahs,
    this.memorizedAyat = const {},
  });

  final Set<int> completedSurahs;

  /// معرّفات الآيات (العامة) التي سمّعها الطفل صحيحة.
  final Set<int> memorizedAyat;

  bool isDone(int surahId) => completedSurahs.contains(surahId);

  bool isMemorized(int ayahId) => memorizedAyat.contains(ayahId);

  int get stars => completedSurahs.length + memorizedAyat.length;

  KidProgress copyWith({Set<int>? completedSurahs, Set<int>? memorizedAyat}) =>
      KidProgress(
        completedSurahs: completedSurahs ?? this.completedSurahs,
        memorizedAyat: memorizedAyat ?? this.memorizedAyat,
      );

  Map<String, Object?> toJson() => {
    'surahs': completedSurahs.toList(growable: false),
    'ayat': memorizedAyat.toList(growable: false),
  };

  factory KidProgress.fromJson(Map<String, dynamic> json) => KidProgress(
    completedSurahs: {
      for (final value in (json['surahs'] as List? ?? const []))
        if (value is num) value.toInt(),
    },
    memorizedAyat: {
      for (final value in (json['ayat'] as List? ?? const []))
        if (value is num) value.toInt(),
    },
  );
}
