import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/adhan_channel.dart';

/// حالة تشغيل الأذان — لعرض زر إيقاف داخل التطبيق.
///
/// الأذان يعمل في خدمة أمامية مستقلة عن الواجهة؛ المحرك يبثّ الحالة عبر
/// قناة الأحداث `yousuf/adhan_events` لحظة تغيّرها (بلا استعلام دوري).
final adhanPlayingProvider = StreamProvider<bool>(
  (ref) => AdhanChannel.playingStream(),
);
