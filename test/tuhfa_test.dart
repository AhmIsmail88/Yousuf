import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:yousuf/core/db/content_db.dart';
import 'package:yousuf/features/kids/data/tuhfa_repository.dart';

/// تحفة الأطفال: المتن كاملاً مع التطبيق، وصوت لكل باب.
void main() {
  test('٦١ بيتاً في ١٠ أبواب، أولها وآخرها كما في المتن', () {
    final content = ContentDb.openFile(
      File('assets/db/content.sqlite').absolute.path,
    );
    addTearDown(content.dispose);
    final sections = readTuhfa(content);
    expect(sections, hasLength(10));
    final verses = [for (final s in sections) ...s.verses];
    expect(verses, hasLength(61));
    expect(verses.first.line1, contains('يَقُــولُ'));
    expect(verses.last.number, 61);
  });

  test('صوت لكل باب وللمتن كاملاً ببصمة', () {
    for (var section = 0; section <= 10; section++) {
      final audio = tuhfaAudioFor(section);
      expect(audio, isNotNull, reason: 'الباب $section');
      expect(audio!.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(audio.url, contains('/tuhfa/'));
    }
  });
}
