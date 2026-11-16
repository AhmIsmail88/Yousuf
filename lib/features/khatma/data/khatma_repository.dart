import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/arabic_dates.dart';
import '../domain/khatma_plan.dart';

/// تخزين خطة الختمة والصفحات المقروءة محلياً (SPEC §10).
class KhatmaRepository {
  KhatmaRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String key = 'khatma.plan';
  static const String readKey = 'khatma.read_pages';
  static const String todayKey = 'khatma.read_today';

  KhatmaPlan? load() {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return KhatmaPlan.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// خطة جديدة تبدأ بسجل قراءة فارغ.
  Future<void> save(KhatmaPlan plan) async {
    await _prefs.setString(key, jsonEncode(plan.toJson()));
    await _prefs.remove(readKey);
    await _prefs.remove(todayKey);
  }

  Future<void> clear() async {
    await _prefs.remove(key);
    await _prefs.remove(readKey);
    await _prefs.remove(todayKey);
  }

  /// كل الصفحات المقروءة.
  Set<int> readPages() => _parse(_prefs.getString(readKey));

  /// الصفحات المقروءة في [day] (فارغة إن كان المحفوظ ليوم آخر).
  Set<int> readOn(DateTime day) {
    final raw = _prefs.getString(todayKey);
    if (raw == null) return <int>{};
    final sep = raw.indexOf('|');
    if (sep < 0 || raw.substring(0, sep) != dayKey(day)) return <int>{};
    return _parse(raw.substring(sep + 1));
  }

  /// يعلّم صفحات كمقروءة اليوم.
  Future<void> markRead(Iterable<int> pages, DateTime day) async {
    final all = readPages()..addAll(pages);
    final today = readOn(day)..addAll(pages);
    await _prefs.setString(readKey, _format(all));
    await _prefs.setString(todayKey, '${dayKey(day)}|${_format(today)}');
  }

  /// يلغي تعليم صفحة.
  Future<void> unmark(int page, DateTime day) async {
    final all = readPages()..remove(page);
    final today = readOn(day)..remove(page);
    await _prefs.setString(readKey, _format(all));
    await _prefs.setString(todayKey, '${dayKey(day)}|${_format(today)}');
  }

  static Set<int> _parse(String? raw) {
    if (raw == null || raw.isEmpty) return <int>{};
    return raw.split(',').map(int.tryParse).whereType<int>().toSet();
  }

  static String _format(Set<int> pages) => (pages.toList()..sort()).join(',');
}
