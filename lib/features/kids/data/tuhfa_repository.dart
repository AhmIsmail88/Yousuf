import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/net/resumable_download.dart';

import '../../../core/db/content_db.dart';
import '../../quran/presentation/quran_providers.dart';

/// «تحفة الأطفال والغلمان» للجمزوري: النص مع التطبيق (جدولا tuhfa_section
/// وtuhfa_verse)، والصوت (محمد عبد الرحمن الحوفي) يُنزَّل لكل باب من
/// Hugging Face ويُتحقق من بصمته. تُبنى بـ `tools/content_builder/tuhfa.py`.

/// مكان ملفات الصوت — `--dart-define=KIDS_MEDIA_URL=...`.
const String kidsMediaBaseUrl = String.fromEnvironment(
  'KIDS_MEDIA_URL',
  defaultValue:
      'https://huggingface.co/datasets/Ahm20/yousuf-kids/resolve/main/',
);

class TuhfaAudio {
  const TuhfaAudio({
    required this.section,
    required this.file,
    required this.bytes,
    required this.seconds,
    required this.sha256,
  });

  /// رقم الباب؛ ٠ = المتن كاملاً.
  final int section;
  final String file;
  final int bytes;
  final int seconds;
  final String sha256;

  String get url => '${kidsMediaBaseUrl}tuhfa/$file';
}

/// ناتج `tuhfa.py --audio` (tuhfa_audio.json).
const List<TuhfaAudio> tuhfaAudio = [
  TuhfaAudio(
    section: 1,
    file: '01.mp3',
    bytes: 1420160,
    seconds: 89,
    sha256: 'c05c385210f9cdadfc8619706fc3c23cffeb2e9fb2b6d712a1f6d00f669e12a3',
  ),
  TuhfaAudio(
    section: 2,
    file: '02.mp3',
    bytes: 2390951,
    seconds: 149,
    sha256: 'b5fd1147f08fbc078236e0520ca26b94f50c1b52054d7733404c6d3f8f0bbca6',
  ),
  TuhfaAudio(
    section: 3,
    file: '03.mp3',
    bytes: 324254,
    seconds: 20,
    sha256: '7804d00f9b683285e48f64334c68aa6df0f7b80246df5a44d5f8e9cddd7eced8',
  ),
  TuhfaAudio(
    section: 4,
    file: '04.mp3',
    bytes: 1329558,
    seconds: 83,
    sha256: 'caeb6e565d893985e9e464ac47f53c9ae36ff48734a2972b6aa602dc02fe6291',
  ),
  TuhfaAudio(
    section: 5,
    file: '05.mp3',
    bytes: 1306520,
    seconds: 82,
    sha256: '57a4c3052b5696c3b6f7a925ea72c1361d3ef3d4221bce28b115a0a3005c73f0',
  ),
  TuhfaAudio(
    section: 6,
    file: '06.mp3',
    bytes: 1176371,
    seconds: 74,
    sha256: 'cb23561f1465e9979352e71c7b0baaefa415f56cddd1426cba19e9d92ac2d494',
  ),
  TuhfaAudio(
    section: 7,
    file: '07.mp3',
    bytes: 1515013,
    seconds: 95,
    sha256: '29c0f7bbf285efda3e62b71f14d4f90428b9679382fb9092b6214fd90c0a5c58',
  ),
  TuhfaAudio(
    section: 8,
    file: '08.mp3',
    bytes: 1288453,
    seconds: 80,
    sha256: 'd12857baae7dd51ed086d3baddc708f3eb09ee5edb7d78db0d07548cda193af7',
  ),
  TuhfaAudio(
    section: 9,
    file: '09.mp3',
    bytes: 2019602,
    seconds: 126,
    sha256: 'd928197f4d7059e88cf55e8bad4ef6c1868fff464e523137cd9989c645ac463a',
  ),
  TuhfaAudio(
    section: 10,
    file: '10.mp3',
    bytes: 877568,
    seconds: 55,
    sha256: '969146a931423acfe0ca53e59aadd74e11ec35096e6a0d935700a4048f9bff0c',
  ),
  TuhfaAudio(
    section: 0,
    file: 'full.mp3',
    bytes: 13673265,
    seconds: 854,
    sha256: '9ddb38382a1aa9b75d6bdf3f5ca9976634a8a66e0eaeb0eeba3efd54272ba84e',
  ),
];

TuhfaAudio? tuhfaAudioFor(int section) {
  for (final audio in tuhfaAudio) {
    if (audio.section == section) return audio;
  }
  return null;
}

class TuhfaSection {
  const TuhfaSection(this.id, this.title, this.verses);

  final int id;
  final String title;
  final List<TuhfaVerse> verses;
}

class TuhfaVerse {
  const TuhfaVerse(this.number, this.line1, this.line2);

  final int number;
  final String line1;
  final String line2;
}

/// قراءة المتن من قاعدة المحتوى.
List<TuhfaSection> readTuhfa(ContentDb content) {
  final verses = <int, List<TuhfaVerse>>{};
  for (final row in content.db.select(
    'SELECT number, section_id, line1, line2 FROM tuhfa_verse ORDER BY number',
  )) {
    (verses[row['section_id'] as int] ??= []).add(
      TuhfaVerse(
        row['number'] as int,
        row['line1'] as String,
        row['line2'] as String,
      ),
    );
  }
  return [
    for (final row in content.db.select(
      'SELECT id, title FROM tuhfa_section ORDER BY id',
    ))
      TuhfaSection(
        row['id'] as int,
        row['title'] as String,
        verses[row['id'] as int] ?? const [],
      ),
  ];
}

final tuhfaProvider = FutureProvider<List<TuhfaSection>>((ref) async {
  return readTuhfa(await ref.watch(contentDbProvider.future));
});

/// ملفات الصوت المنزَّلة: `<appSupport>/kids/tuhfa/<file>`.
class TuhfaAudioStore {
  TuhfaAudioStore._();

  static Future<File> fileFor(TuhfaAudio audio) async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/kids/tuhfa',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/${audio.file}');
  }

  static Future<Set<int>> downloaded() async {
    final result = <int>{};
    for (final audio in tuhfaAudio) {
      final file = await fileFor(audio);
      if (file.existsSync() && file.lengthSync() == audio.bytes) {
        result.add(audio.section);
      }
    }
    return result;
  }

  /// ينزّل الملف ويتحقق من بصمته. يرمي استثناءً عند الفشل.
  static Future<void> download(
    TuhfaAudio audio, {
    void Function(double progress)? onProgress,
  }) async {
    final target = await fileFor(audio);
    final part = File('${target.path}.part');
    try {
      await downloadResumable(
        url: Uri.parse(audio.url),
        part: part,
        expectedBytes: audio.bytes,
        onProgress: onProgress,
      );
      final digest = (await sha256.bind(part.openRead()).first).toString();
      if (digest != audio.sha256) throw StateError('بصمة الملف غير مطابقة');
      await part.rename(target.path);
    } finally {
      if (part.existsSync()) part.deleteSync();
    }
  }
}

final tuhfaDownloadedProvider = FutureProvider<Set<int>>(
  (ref) => TuhfaAudioStore.downloaded(),
);

/// تنزيلات جارية: الباب ← التقدّم (٠–١).
class TuhfaDownloads extends Notifier<Map<int, double>> {
  @override
  Map<int, double> build() => const {};

  Future<void> download(TuhfaAudio audio) async {
    if (state.containsKey(audio.section)) return;
    state = {...state, audio.section: 0};
    try {
      await TuhfaAudioStore.download(
        audio,
        onProgress: (p) => state = {...state, audio.section: p},
      );
    } finally {
      state = {...state}..remove(audio.section);
      ref.invalidate(tuhfaDownloadedProvider);
    }
  }
}

final tuhfaDownloadsProvider =
    NotifierProvider<TuhfaDownloads, Map<int, double>>(TuhfaDownloads.new);
