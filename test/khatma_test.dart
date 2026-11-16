import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yousuf/features/khatma/data/khatma_repository.dart';
import 'package:yousuf/features/khatma/domain/khatma_plan.dart';

/// حساب الختمة المخططة وتخزينها (SPEC §7.3) — التقدّم من الصفحات المقروءة.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime(2026, 11, 1);

  KhatmaPlan planWith({int days = 30, int startPage = 1}) =>
      KhatmaPlan(days: days, startPage: startPage, startDate: start);

  Set<int> range(int from, int to) => {for (var p = from; p <= to; p++) p};

  group('حساب التقدّم', () {
    test('اليوم الأول بلا قراءة: الهدف = الصفحات / الأيام', () {
      final progress = computeKhatma(
        plan: planWith(),
        readPages: const {},
        readToday: const {},
        now: start,
      );
      expect(progress.totalPages, 604);
      expect(progress.pagesRead, 0);
      expect(progress.todayTarget, 21); // 604 / 30 = 20.1 → 21
      expect(progress.todayRemaining, 21);
      expect(progress.nextPage, 1);
      expect(progress.finished, isFalse);
    });

    test('فتح صفحة بعيدة لا يحسب ما قبلها مقروءاً', () {
      final progress = computeKhatma(
        plan: planWith(),
        readPages: {600},
        readToday: {600},
        now: start,
      );
      expect(progress.pagesRead, 1);
      expect(progress.nextPage, 1);
    });

    test('قراءة اليوم لا تغيّر هدف اليوم بل تنقص المتبقي منه', () {
      final progress = computeKhatma(
        plan: planWith(),
        readPages: range(1, 10),
        readToday: range(1, 10),
        now: start,
      );
      expect(progress.todayTarget, 21);
      expect(progress.todayRead, 10);
      expect(progress.todayRemaining, 11);
      expect(progress.nextPage, 11);
    });

    test('التقدّم يحسب من صفحة البداية فقط', () {
      final progress = computeKhatma(
        plan: planWith(startPage: 100),
        readPages: range(50, 149),
        readToday: const {},
        now: start,
      );
      expect(progress.totalPages, 505);
      expect(progress.pagesRead, 50);
    });

    test('الختمة تكتمل بقراءة كل صفحاتها', () {
      final progress = computeKhatma(
        plan: planWith(days: 10, startPage: 600),
        readPages: range(600, 604),
        readToday: const {},
        now: start,
      );
      expect(progress.percent, 1);
      expect(progress.finished, isTrue);
      expect(progress.todayRemaining, 0);
    });

    test('إعادة التوزيع بعد فوات أيام', () {
      final progress = computeKhatma(
        plan: planWith(),
        readPages: range(1, 301),
        readToday: const {},
        now: DateTime(2026, 11, 16), // ١٥ يوماً انقضت
      );
      expect(progress.daysLeft, 15);
      expect(progress.remainingPages, 303);
      expect(progress.todayTarget, 21); // 303 / 15 ≈ 20.2
    });

    test('الخطة المنتهية: daysLeft = ١ على الأقل', () {
      final progress = computeKhatma(
        plan: planWith(days: 5),
        readPages: range(1, 10),
        readToday: const {},
        now: DateTime(2026, 12, 1),
      );
      expect(progress.daysLeft, 1);
      expect(progress.todayTarget, greaterThan(0));
    });

    test('nextUnreadPages يتخطى المقروء', () {
      final pages = nextUnreadPages(
        plan: planWith(),
        readPages: {1, 2, 4},
        count: 3,
      );
      expect(pages, [3, 5, 6]);
    });
  });

  group('التخزين', () {
    test('حفظ واسترجاع الخطة', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = KhatmaRepository(prefs);

      expect(repository.load(), isNull);

      await repository.save(
        KhatmaPlan(days: 60, startPage: 3, startDate: start),
      );

      final loaded = repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.days, 60);
      expect(loaded.startPage, 3);

      await repository.clear();
      expect(repository.load(), isNull);
    });

    test('سجل القراءة: اليوم يُصفَّر في يوم جديد ويبقى الإجمالي', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = KhatmaRepository(prefs);

      await repository.markRead([1, 2, 3], start);
      expect(repository.readPages(), {1, 2, 3});
      expect(repository.readOn(start), {1, 2, 3});

      final tomorrow = DateTime(2026, 11, 2);
      expect(repository.readOn(tomorrow), isEmpty);
      await repository.markRead([4], tomorrow);
      expect(repository.readPages(), {1, 2, 3, 4});
      expect(repository.readOn(tomorrow), {4});

      await repository.unmark(2, tomorrow);
      expect(repository.readPages(), {1, 3, 4});
    });

    test('بيانات تالفة ترجع null بلا انهيار', () async {
      SharedPreferences.setMockInitialValues({'khatma.plan': 'not json'});
      final prefs = await SharedPreferences.getInstance();
      expect(KhatmaRepository(prefs).load(), isNull);
    });
  });
}
