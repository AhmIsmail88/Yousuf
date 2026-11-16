import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/prefs/shared_preferences_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // تلاوة القرآن في الخلفية: إشعار بأزرار تشغيل/إيقاف/التالي وشاشة القفل.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'app.yousuf.quran_audio',
    androidNotificationChannelName: 'تلاوة القرآن',
    androidNotificationOngoing: true,
    androidNotificationIcon: 'drawable/ic_stat_yousuf',
  );
  // تحميل التفضيلات قبل أول إطار: يحدد اللغة وهل اكتمل الترحيب.
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const YousufApp(),
    ),
  );
}
