/// ذكر يضيفه المستخدم بنفسه — يُحفظ على جهازه فقط (SPEC §10).
library;

/// حد أقصى لطول النص وعدد التكرار — حماية من المدخلات الشاذة.
const int kUserDhikrMaxLength = 2000;
const int kUserDhikrMaxRepeat = 100;

class UserDhikr {
  const UserDhikr({
    required this.id,
    required this.text,
    required this.repeat,
    required this.createdAt,
    this.source,
  });

  final String id;
  final String text;
  final int repeat;

  /// مصدر اختياري يكتبه المستخدم (مثل: رواه مسلم).
  final String? source;
  final DateTime createdAt;

  UserDhikr copyWith({String? text, int? repeat, String? source}) => UserDhikr(
    id: id,
    text: text ?? this.text,
    repeat: repeat ?? this.repeat,
    source: source ?? this.source,
    createdAt: createdAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'repeat': repeat,
    'source': source,
    'createdAt': createdAt.toIso8601String(),
  };

  /// يرمي استثناءً عند مدخل تالف — والمستودع يتعامل معه.
  factory UserDhikr.fromJson(Map<String, dynamic> json) => UserDhikr(
    id: json['id'] as String,
    text: json['text'] as String,
    repeat: (json['repeat'] as num?)?.toInt() ?? 1,
    source: json['source'] as String?,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  /// يبني ذكراً جديداً بعد التحقق من المدخلات.
  static UserDhikr create({
    required String text,
    required int repeat,
    String? source,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('نص الذكر مطلوب');
    }
    if (trimmed.length > kUserDhikrMaxLength) {
      throw ArgumentError('النص أطول من الحد المسموح');
    }
    final safeRepeat = repeat.clamp(1, kUserDhikrMaxRepeat);
    return UserDhikr(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: trimmed,
      repeat: safeRepeat,
      source: (source == null || source.trim().isEmpty) ? null : source.trim(),
      createdAt: DateTime.now(),
    );
  }
}
