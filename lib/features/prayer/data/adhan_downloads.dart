import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../domain/adhan_sounds.dart';

/// تحميل أصوات الأذان الإضافية إلى الجهاز (لا تُضمَّن في الحزمة).
///
/// الملف يُحفظ في `<appSupport>/adhan/<id>.mp3` — وهو `filesDir/adhan` على
/// أندرويد، المجلد نفسه الذي يقرأ منه محرك الأذان الأصلي (`AdhanService`).
/// لا يُرسل أي بيان عن المستخدم: طلب GET عادي للملف فقط.
class AdhanDownloads extends Notifier<Map<String, double>> {
  /// أصغر حجم مقبول — ما دونه تحميل ناقص (يطابق الحد في `AdhanService`).
  static const int minBytes = 100000;

  @override
  Map<String, double> build() => const {};

  static Future<File> fileFor(String id) async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/adhan',
    );
    return File('${dir.path}/$id.mp3');
  }

  bool isDownloading(String id) => state.containsKey(id);

  /// يحمّل الصوت ويُبلغ بالتقدّم (٠–١). يرمي استثناءً عند الفشل.
  Future<void> download(AdhanSound sound) async {
    final url = sound.downloadUrl;
    if (url == null || isDownloading(sound.id)) return;
    state = {...state, sound.id: 0};
    final client = http.Client();
    final target = await fileFor(sound.id);
    final part = File('${target.path}.part');
    try {
      await target.parent.create(recursive: true);
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = part.openWrite();
      try {
        // مهلة بين الأجزاء لا على التحميل كله — الخادم بطيء أحياناً.
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 45),
        )) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) state = {...state, sound.id: received / total};
        }
      } finally {
        await sink.close();
      }
      if (received < minBytes || (total > 0 && received < total)) {
        throw const HttpException('تحميل ناقص');
      }
      await part.rename(target.path);
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client.close();
      state = {...state}..remove(sound.id);
    }
  }

  Future<void> delete(String id) async {
    final file = await fileFor(id);
    if (await file.exists()) await file.delete();
  }
}

final adhanDownloadsProvider =
    NotifierProvider<AdhanDownloads, Map<String, double>>(AdhanDownloads.new);
