/// خطة الختمة المخططة (SPEC §7.3، م2).
///
/// التقدّم يُحسب من **الصفحات المقروءة فعلاً** لا من آخر صفحة فُتحت:
/// فتح صفحة ٦٠٠ للبحث لا يجعل الختمة ٩٩٪، والرجوع للخلف لا يُنقص التقدّم.
/// الصفحة تُعدّ مقروءة عند المكوث عليها مدة كافية في المصحف، أو بتعليمها
/// يدوياً، أو بزر «قرأت ورد اليوم».
library;

/// خطة ختمة: عدد الأيام، وصفحة البداية، وتاريخ البدء.
class KhatmaPlan {
  const KhatmaPlan({
    required this.days,
    required this.startPage,
    required this.startDate,
  });

  final int days;
  final int startPage;
  final DateTime startDate;

  /// آخر صفحة في المصحف.
  static const int lastPage = 604;

  int get totalPages => lastPage - startPage + 1;

  /// الأيام المنقضية منذ البدء (٠ في يوم البدء).
  int elapsedDays(DateTime now) {
    final today = DateTime.utc(now.year, now.month, now.day);
    final start = DateTime.utc(startDate.year, startDate.month, startDate.day);
    return today.difference(start).inDays;
  }

  Map<String, Object?> toJson() => {
    'days': days,
    'startPage': startPage,
    'startDate': startDate.toIso8601String(),
  };

  factory KhatmaPlan.fromJson(Map<String, dynamic> json) => KhatmaPlan(
    days: (json['days'] as num).toInt(),
    startPage: (json['startPage'] as num?)?.toInt() ?? 1,
    startDate:
        DateTime.tryParse(json['startDate'] as String? ?? '') ?? DateTime.now(),
  );
}

/// تقدّم الخطة.
class KhatmaProgress {
  const KhatmaProgress({
    required this.pagesRead,
    required this.totalPages,
    required this.remainingPages,
    required this.daysLeft,
    required this.todayTarget,
    required this.todayRead,
    required this.nextPage,
    required this.finished,
  });

  final int pagesRead;
  final int totalPages;
  final int remainingPages;

  /// الأيام المتبقية (١ على الأقل).
  final int daysLeft;

  /// ورد اليوم بالصفحات — محسوب من المتبقي في بداية اليوم، فيُعاد توزيعه
  /// تلقائياً إن فات يوم، ولا يتغيّر أثناء اليوم بالقراءة.
  final int todayTarget;

  /// الصفحات المقروءة اليوم (ضمن الخطة).
  final int todayRead;

  /// أول صفحة لم تُقرأ بعد في الخطة (للمتابعة).
  final int nextPage;

  final bool finished;

  /// ما تبقّى من ورد اليوم.
  int get todayRemaining => (todayTarget - todayRead).clamp(0, remainingPages);

  double get percent => totalPages == 0 ? 0 : pagesRead / totalPages;
}

/// يحسب التقدّم من الصفحات المقروءة.
///
/// [readPages] كل الصفحات المقروءة منذ بدء الخطة، و[readToday] ما قُرئ
/// منها اليوم.
KhatmaProgress computeKhatma({
  required KhatmaPlan plan,
  required Set<int> readPages,
  required Set<int> readToday,
  required DateTime now,
}) {
  bool inPlan(int page) =>
      page >= plan.startPage && page <= KhatmaPlan.lastPage;

  final total = plan.totalPages;
  final read = readPages.where(inPlan).length;
  final today = readToday.where(inPlan).length;
  final remaining = total - read;
  final remainingAtDayStart = remaining + today;
  final elapsed = plan.elapsedDays(now).clamp(0, plan.days);
  final daysLeft = (plan.days - elapsed).clamp(1, plan.days);
  final target = remainingAtDayStart == 0
      ? 0
      : (remainingAtDayStart / daysLeft).ceil();

  var next = plan.startPage;
  while (next <= KhatmaPlan.lastPage && readPages.contains(next)) {
    next++;
  }

  return KhatmaProgress(
    pagesRead: read,
    totalPages: total,
    remainingPages: remaining,
    daysLeft: daysLeft,
    todayTarget: target,
    todayRead: today,
    nextPage: next.clamp(plan.startPage, KhatmaPlan.lastPage),
    finished: remaining == 0,
  );
}

/// الصفحات التالية غير المقروءة (لزر «قرأت ورد اليوم»).
List<int> nextUnreadPages({
  required KhatmaPlan plan,
  required Set<int> readPages,
  required int count,
}) {
  final result = <int>[];
  for (
    var page = plan.startPage;
    page <= KhatmaPlan.lastPage && result.length < count;
    page++
  ) {
    if (!readPages.contains(page)) result.add(page);
  }
  return result;
}
