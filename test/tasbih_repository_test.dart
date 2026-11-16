import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/features/tasbih/data/tasbih_repository.dart';
import 'package:yousuf/features/tasbih/domain/tasbih_models.dart';

/// اختبارات مستودع مسبحة على تخزين وهمي (SharedPreferences mock).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late TasbihRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    repository = TasbihRepository(prefs);
  });

  test('أول تشغيل: ثلاثة عدّادات بأهداف ٣٣ و٣٣ و٣٤', () {
    final counters = repository.loadCounters();

    expect(counters.length, 3);
    expect(counters.map((counter) => counter.target).toList(), [33, 33, 34]);
    expect(counters.map((counter) => counter.label).toList(), [
      'سبحان الله',
      'الحمد لله',
      'الله أكبر',
    ]);
    expect(counters.every((counter) => counter.count == 0), isTrue);
    expect(repository.tapsToday(), 0);
  });

  test('increment يزيد العدّاد ويحدّث الإحصاء اليومي', () async {
    final first = repository.loadCounters().first;

    final once = await repository.increment(first.id);
    expect(once, isNotNull);
    expect(once!.count, 1);
    expect(repository.loadCounters().first.count, 1);
    expect(repository.tapsToday(), 1);

    await repository.increment(first.id);
    expect(repository.loadCounters().first.count, 2);
    expect(repository.tapsToday(), 2);

    // محفوظة فعلاً في التخزين لا في الذاكرة فقط.
    final stored = jsonDecode(
      prefs.getString(TasbihRepository.countersKey)!,
    ) as List<dynamic>;
    expect((stored.first as Map<String, dynamic>)['count'], 2);
  });

  test('reset يصفّر العدّ ولا يمسّ إحصاء اليوم', () async {
    final first = repository.loadCounters().first;
    await repository.increment(first.id);
    await repository.increment(first.id);
    expect(repository.tapsToday(), 2);

    final reset = await repository.resetCounter(first.id);
    expect(reset, isNotNull);
    expect(reset!.count, 0);
    expect(repository.loadCounters().first.count, 0);
    expect(repository.tapsToday(), 2, reason: 'الإحصاء اليومي تراكمي');
  });

  test('add/update/delete يعملان على القائمة المحفوظة', () async {
    final created = await repository.addCounter('استغفار', 100);
    expect(created.count, 0);
    expect(created.target, 100);
    expect(repository.loadCounters().length, 4);
    expect(repository.loadCounters().last.label, 'استغفار');

    await repository.updateCounter(
      created.copyWith(label: 'أستغفر الله', target: 33),
    );
    final updated = repository.loadCounters().firstWhere(
      (item) => item.id == created.id,
    );
    expect(updated.label, 'أستغفر الله');
    expect(updated.target, 33);
    expect(updated.count, 0);

    await repository.deleteCounter(created.id);
    expect(
      repository.loadCounters().any((item) => item.id == created.id),
      isFalse,
    );
    expect(repository.loadCounters().length, 3);
  });

  test('قائمة عدّادات تالفة ترجع للافتراضي بلا انهيار', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      TasbihRepository.countersKey: '{ليس JSON صالحاً',
    });
    final corruptPrefs = await SharedPreferences.getInstance();
    final corrupt = TasbihRepository(corruptPrefs);
    final counters = corrupt.loadCounters();
    expect(counters.length, 3);
    expect(counters.first.label, 'سبحان الله');

    // قائمة عناصرها ليست خرائط (أنواع خاطئة) → الافتراضي أيضاً.
    SharedPreferences.setMockInitialValues(<String, Object>{
      TasbihRepository.countersKey: '[1, 2, 3]',
    });
    final badPrefs = await SharedPreferences.getInstance();
    expect(TasbihRepository(badPrefs).loadCounters().length, 3);
  });

  test('الإحصاء اليومي يحتفظ بآخر ٣٠ يوماً فقط', () async {
    final now = DateTime.now();
    final history = <TasbihDailyStat>[
      for (var day = 1; day <= 30; day++)
        TasbihDailyStat(
          dateKey: TasbihDailyStat.dateKeyOf(now.subtract(Duration(days: day))),
          taps: day,
        ),
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      TasbihRepository.dailyKey: jsonEncode(<Map<String, Object?>>[
        for (final stat in history) stat.toJson(),
      ]),
    });
    final trimPrefs = await SharedPreferences.getInstance();
    final trimmed = TasbihRepository(trimPrefs);

    final first = trimmed.loadCounters().first;
    await trimmed.increment(first.id);

    final stored = jsonDecode(
      trimPrefs.getString(TasbihRepository.dailyKey)!,
    ) as List<dynamic>;
    expect(stored.length, 30);
    expect(trimmed.tapsToday(), 1);
  });
}
