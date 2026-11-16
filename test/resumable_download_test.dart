import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yousuf/core/net/resumable_download.dart';

/// التنزيل يستأنف بـ Range إذا تعلّق الاتصال قبل آخر الملف.
void main() {
  test('خادم يتعلّق بعد نصف الملف: يكتمل الملف بالاستئناف', () async {
    final data = List<int>.generate(10000, (i) => i % 251);
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      final range = request.headers.value('range');
      final response = request.response..bufferOutput = false;
      if (range == null) {
        // أول طلب: نرسل النصف ثم نتعلّق (لا نغلق الاتصال).
        response.contentLength = data.length;
        response.add(data.sublist(0, 5000));
        await response.flush();
        return;
      }
      final from = int.parse(
        RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!,
      );
      response.statusCode = 206;
      response.contentLength = data.length - from;
      response.add(data.sublist(from));
      await response.close();
    });

    final dir = Directory.systemTemp.createTempSync('resume');
    addTearDown(() => dir.deleteSync(recursive: true));
    final part = File('${dir.path}/f.part');
    await downloadResumable(
      url: Uri.parse('http://127.0.0.1:${server.port}/f'),
      part: part,
      expectedBytes: data.length,
      stall: const Duration(milliseconds: 300),
    );
    expect(part.readAsBytesSync(), data);
    expect(requests, 2);
  });
}
