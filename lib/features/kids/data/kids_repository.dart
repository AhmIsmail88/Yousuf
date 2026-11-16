import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/kid_profile.dart';

/// تخزين وضع الأطفال محلياً (SPEC §10): الملفات، الرمز، وإنجاز جزء عمّ.
class KidsRepository {
  KidsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String _profilesKey = 'kids.profiles';
  static const String _activeKey = 'kids.active';
  static const String _pinKey = 'kids.pin';

  static String _progressKey(String profileId) => 'kids.progress.$profileId';

  List<KidProfile> loadProfiles() {
    final raw = _prefs.getString(_profilesKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) KidProfile.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveProfiles(List<KidProfile> profiles) => _prefs.setString(
    _profilesKey,
    jsonEncode([for (final profile in profiles) profile.toJson()]),
  );

  String? activeProfileId() => _prefs.getString(_activeKey);

  Future<void> setActiveProfile(String? id) async {
    if (id == null) {
      await _prefs.remove(_activeKey);
    } else {
      await _prefs.setString(_activeKey, id);
    }
  }

  /// رمز الخروج (٤ أرقام) — null يعني لا رمز.
  String? pin() {
    final value = _prefs.getString(_pinKey);
    return (value == null || value.length != 4) ? null : value;
  }

  Future<void> savePin(String? pin) async {
    if (pin == null || pin.isEmpty) {
      await _prefs.remove(_pinKey);
    } else {
      await _prefs.setString(_pinKey, pin);
    }
  }

  KidProgress loadProgress(String profileId) {
    final raw = _prefs.getString(_progressKey(profileId));
    if (raw == null) return const KidProgress(completedSurahs: {});
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const KidProgress(completedSurahs: {});
      return KidProgress.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const KidProgress(completedSurahs: {});
    }
  }

  Future<void> saveProgress(String profileId, KidProgress progress) =>
      _prefs.setString(_progressKey(profileId), jsonEncode(progress.toJson()));
}
