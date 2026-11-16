import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// ينزّل [url] إلى [part] ويستأنف من حيث توقف إذا تعلّق الاتصال.
///
/// بعض الشبكات تُعلّق الاتصال بالـ CDN قرب آخر الملف (لوحظ على جهاز حقيقي:
/// ٩٦٪ ثم لا شيء). بدل الفشل نطلب الباقي بـ `Range` ونكمل الملف نفسه.
/// [expectedBytes] حجم الملف الكامل (من الفهرس) لحساب التقدّم والتحقق.
Future<void> downloadResumable({
  required Uri url,
  required File part,
  required int expectedBytes,
  void Function(double progress)? onProgress,
  int attempts = 4,
  Duration stall = const Duration(seconds: 20),
}) async {
  if (part.existsSync()) part.deleteSync();
  final client = http.Client();
  try {
    for (var attempt = 1; ; attempt++) {
      final have = part.existsSync() ? part.lengthSync() : 0;
      if (have >= expectedBytes) return;
      try {
        final request = http.Request('GET', url);
        if (have > 0) request.headers['Range'] = 'bytes=$have-';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        final resumed = response.statusCode == 206;
        if (response.statusCode != 200 && !resumed) {
          throw HttpException('HTTP ${response.statusCode}');
        }
        // الخادم تجاهل Range وأعاد الملف من أوله: نبدأ من جديد.
        final sink = part.openWrite(
          mode: resumed ? FileMode.append : FileMode.write,
        );
        var received = resumed ? have : 0;
        try {
          await for (final chunk in response.stream.timeout(stall)) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received / expectedBytes);
          }
        } finally {
          await sink.close();
        }
        if (part.lengthSync() >= expectedBytes) return;
        throw const HttpException('انقطع الاتصال قبل اكتمال الملف');
      } on Object {
        if (attempt >= attempts) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
  } finally {
    client.close();
  }
}
