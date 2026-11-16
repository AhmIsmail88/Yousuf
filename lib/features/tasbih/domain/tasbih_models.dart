/// نماذج مسبحة: عدّاد تسبيح بإحصاء يومي (SPEC §7.4).
///
/// ملف Dart خالص بلا أي اعتماديات على Flutter — قابل للاختبار مباشرة.
library;

/// عدّاد تسبيح واحد: نص الذكر وهدفه والعدد المنجز.
///
/// الهدف قد يكون 33 أو 100 أو أي رقم مخصص. لا يُصفَّر العدد تلقائياً عند
/// بلوغ الهدف؛ التصفير قرار صريح من المستخدم.
class TasbihCounter {
  const TasbihCounter({
    required this.id,
    required this.label,
    required this.target,
    this.count = 0,
    required this.updatedAt,
  });

  /// معرّف محلي بسيط (طابع زمني) — بلا حزمة uuid.
  final String id;

  /// نص الذكر المعروض (مثل «سبحان الله»).
  final String label;

  /// الهدف المطلوب للتسبيح.
  final int target;

  /// عدد التسبيحات المسجّلة.
  final int count;

  /// آخر تعديل على العدّاد.
  final DateTime updatedAt;

  /// هل بلغ العدّاد هدفه؟
  bool get isCompleted => target > 0 && count >= target;

  /// نسبة التقدّم بين 0 و1 — لحلقة العرض.
  double get progress {
    if (target <= 0) return 0;
    final value = count / target;
    return value > 1 ? 1 : value;
  }

  /// ما تبقّى للوصول إلى الهدف (لا يقل عن صفر).
  int get remaining {
    final left = target - count;
    return left < 0 ? 0 : left;
  }

  /// نسخة معدّلة مع إبقاء ما لم يُحدَّد.
  TasbihCounter copyWith({
    String? id,
    String? label,
    int? target,
    int? count,
    DateTime? updatedAt,
  }) {
    return TasbihCounter(
      id: id ?? this.id,
      label: label ?? this.label,
      target: target ?? this.target,
      count: count ?? this.count,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'target': target,
    'count': count,
    'updatedAt': updatedAt.toIso8601String(),
  };

  /// يقرأ العدّاد من JSON — يرمي استثناءً عند حقل ناقص أو نوع خاطئ،
  /// والمستودع هو من يتحمّل ذلك ويعود للافتراضي.
  factory TasbihCounter.fromJson(Map<String, dynamic> json) {
    return TasbihCounter(
      id: json['id'] as String,
      label: json['label'] as String,
      target: (json['target'] as num).toInt(),
      count: (json['count'] as num?)?.toInt() ?? 0,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// إحصاء التسبيح في يوم واحد.
class TasbihDailyStat {
  const TasbihDailyStat({required this.dateKey, required this.taps});

  /// مفتاح اليوم بصيغة yyyy-MM-dd (قابل للفرز النصي).
  final String dateKey;

  /// عدد التسبيحات في ذلك اليوم.
  final int taps;

  /// يبني مفتاح اليوم من تاريخ محلي.
  static String dateKeyOf(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  TasbihDailyStat copyWith({int? taps}) =>
      TasbihDailyStat(dateKey: dateKey, taps: taps ?? this.taps);

  Map<String, Object?> toJson() => {'dateKey': dateKey, 'taps': taps};

  /// يقرأ الإحصاء اليومي من JSON — يرمي استثناءً عند المدخل التالف.
  factory TasbihDailyStat.fromJson(Map<String, dynamic> json) {
    return TasbihDailyStat(
      dateKey: json['dateKey'] as String,
      taps: (json['taps'] as num).toInt(),
    );
  }
}
