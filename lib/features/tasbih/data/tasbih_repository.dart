import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/tasbih_models.dart';

/// تخزين مسبحة محلياً في SharedPreferences (SPEC §5، §7.4).
///
/// المفاتيح:
/// - [countersKey]: قائمة العدّادات (JSON list).
/// - [dailyKey]: الإحصاء اليومي (JSON list، آخر [dailyHistoryDays] يوماً).
///
/// يحتفظ المستودع بنسخة حيّة في الذاكرة حتى لا تضيع الضغطات السريعة
/// بين قراءة وأخرى قبل اكتمال الكتابة على القرص.
class TasbihRepository {
  TasbihRepository(this._prefs);

  final SharedPreferences _prefs;

  /// مفتاح قائمة العدّادات.
  static const String countersKey = 'tasbih.counters';

  /// مفتاح الإحصاء اليومي.
  static const String dailyKey = 'tasbih.daily';

  /// أقصى عدد أيام محفوظة في الإحصاء اليومي.
  static const int dailyHistoryDays = 30;

  static final Random _random = Random();
  static int _sequence = 0;

  List<TasbihCounter>? _counters;
  List<TasbihDailyStat>? _daily;

  /// عدّادات أول تشغيل (SPEC §7.4): ثلاثة أهداف 33 و33 و34.
  List<TasbihCounter> defaultCounters() {
    final now = DateTime.now();
    return <TasbihCounter>[
      TasbihCounter(
        id: 'tasbih-1',
        label: 'سبحان الله',
        target: 33,
        updatedAt: now,
      ),
      TasbihCounter(
        id: 'tasbih-2',
        label: 'الحمد لله',
        target: 33,
        updatedAt: now,
      ),
      TasbihCounter(
        id: 'tasbih-3',
        label: 'الله أكبر',
        target: 34,
        updatedAt: now,
      ),
    ];
  }

  /// يقرأ العدّادات المحفوظة — والافتراضية عند أول تشغيل أو تلف البيانات.
  List<TasbihCounter> loadCounters() {
    _counters ??= _readCounters();
    return List<TasbihCounter>.unmodifiable(_counters!);
  }

  /// يحفظ القائمة كاملة (يستبدل النسخة الحيّة أيضاً).
  Future<void> saveCounters(List<TasbihCounter> counters) async {
    _counters = List<TasbihCounter>.of(counters);
    await _persistCounters();
  }

  /// يضيف عدّاداً جديداً ويبقيه في نهاية القائمة.
  Future<TasbihCounter> addCounter(String label, int target) async {
    final now = DateTime.now();
    final counter = TasbihCounter(
      id: _newId(now),
      label: label,
      target: target,
      updatedAt: now,
    );
    final counters = _counters ??= _readCounters();
    counters.add(counter);
    await _persistCounters();
    return counter;
  }

  /// يحدّث عدّاداً موجوداً (بالنص والهدف) مع إبقاء عدّه الحالي.
  Future<void> updateCounter(TasbihCounter counter) async {
    final counters = _counters ??= _readCounters();
    final index = counters.indexWhere((item) => item.id == counter.id);
    if (index < 0) return;
    counters[index] = counter;
    await _persistCounters();
  }

  /// يحذف عدّاداً بمعرّفه.
  Future<void> deleteCounter(String id) async {
    final counters = _counters ??= _readCounters();
    counters.removeWhere((item) => item.id == id);
    await _persistCounters();
  }

  /// يزيد عدّاداً واحداً ويحدّث الإحصاء اليومي، ويرجع العدّاد الجديد.
  Future<TasbihCounter?> increment(String id) async {
    final counters = _counters ??= _readCounters();
    final index = counters.indexWhere((item) => item.id == id);
    if (index < 0) return null;
    final now = DateTime.now();
    final updated = counters[index].copyWith(
      count: counters[index].count + 1,
      updatedAt: now,
    );
    counters[index] = updated;
    await _persistCounters();
    await _bumpDaily(now);
    return updated;
  }

  /// يصفّر عدّاداً واحداً مع إبقاء الإحصاء اليومي كما هو.
  Future<TasbihCounter?> resetCounter(String id) async {
    final counters = _counters ??= _readCounters();
    final index = counters.indexWhere((item) => item.id == id);
    if (index < 0) return null;
    final updated = counters[index].copyWith(
      count: 0,
      updatedAt: DateTime.now(),
    );
    counters[index] = updated;
    await _persistCounters();
    return updated;
  }

  /// مجموع تسبيحات اليوم (٠ إن لم يُسجَّل شيء).
  int tapsToday({DateTime? now}) {
    final key = TasbihDailyStat.dateKeyOf(now ?? DateTime.now());
    final daily = _daily ??= _readDaily();
    for (final stat in daily) {
      if (stat.dateKey == key) return stat.taps;
    }
    return 0;
  }

  /// يقرأ قائمة العدّادات من التخزين، ويعود للافتراضي عند التلف.
  List<TasbihCounter> _readCounters() {
    final raw = _prefs.getString(countersKey);
    if (raw == null) return defaultCounters();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return defaultCounters();
      return <TasbihCounter>[
        for (final item in decoded)
          TasbihCounter.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (_) {
      // قائمة تالفة (JSON غير صالح أو حقول ناقصة) → الافتراضي بلا انهيار.
      return defaultCounters();
    }
  }

  /// يقرأ الإحصاء اليومي، ويعود لقائمة فارغة عند التلف.
  List<TasbihDailyStat> _readDaily() {
    final raw = _prefs.getString(dailyKey);
    if (raw == null) return <TasbihDailyStat>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <TasbihDailyStat>[];
      return <TasbihDailyStat>[
        for (final item in decoded)
          TasbihDailyStat.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } catch (_) {
      return <TasbihDailyStat>[];
    }
  }

  /// يكتب القائمة الحيّة على القرص.
  Future<void> _persistCounters() async {
    final payload = <Map<String, Object?>>[
      for (final counter in _counters ?? const <TasbihCounter>[])
        counter.toJson(),
    ];
    await _prefs.setString(countersKey, jsonEncode(payload));
  }

  /// يزيد إحصاء اليوم ويقصّ السجل إلى آخر [dailyHistoryDays] يوماً.
  Future<void> _bumpDaily(DateTime now) async {
    final daily = _daily ??= _readDaily();
    final key = TasbihDailyStat.dateKeyOf(now);
    final index = daily.indexWhere((stat) => stat.dateKey == key);
    if (index < 0) {
      daily.add(TasbihDailyStat(dateKey: key, taps: 1));
    } else {
      daily[index] = daily[index].copyWith(taps: daily[index].taps + 1);
    }
    daily.sort((a, b) => b.dateKey.compareTo(a.dateKey));
    if (daily.length > dailyHistoryDays) {
      daily.removeRange(dailyHistoryDays, daily.length);
    }
    await _prefs.setString(
      dailyKey,
      jsonEncode(<Map<String, Object?>>[
        for (final stat in daily) stat.toJson(),
      ]),
    );
  }

  /// معرّف محلي بسيط: طابع زمني + تسلسل + لاحقة عشوائية.
  String _newId(DateTime now) =>
      '${now.microsecondsSinceEpoch}-${_sequence++}-${_random.nextInt(1000)}';
}
