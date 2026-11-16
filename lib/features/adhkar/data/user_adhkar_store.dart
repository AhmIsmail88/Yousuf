import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/user_dhikr.dart';

/// تخزين أذكار المستخدم في SharedPreferences (JSON).
///
/// بيانات شخصية تبقى على الجهاز ولا تُرسل لأي سيرفر (SPEC §10).
/// عند تلف المحفوظ نرجع لقائمة فارغة بدل الانهيار.
class UserAdhkarStore {
  UserAdhkarStore(this._prefs);

  final SharedPreferences _prefs;

  static const String key = 'adhkar.user';

  List<UserDhikr> load() {
    final raw = _prefs.getString(key);
    if (raw == null) return const <UserDhikr>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <UserDhikr>[];
      return <UserDhikr>[
        for (final item in decoded)
          if (item is Map) UserDhikr.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const <UserDhikr>[];
    }
  }

  Future<void> save(List<UserDhikr> items) => _prefs.setString(
    key,
    jsonEncode(<Map<String, Object?>>[for (final item in items) item.toJson()]),
  );
}
