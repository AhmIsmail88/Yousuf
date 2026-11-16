import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';

/// ترجمة النصوص داخل الكود: العربية أولاً (SPEC §1) والإنجليزية بجانبها.
///
/// يُختار النص حسب لغة الواجهة الحالية. نُبقي النص العربي ظاهراً في موضع
/// استخدامه ليسهل قراءة الكود ومراجعته، بدل مفاتيح ARB مجرّدة.
extension TrContext on BuildContext {
  /// هل لغة الواجهة عربية؟
  ///
  /// تتبع لغة ترجمات التطبيق نفسه؛ خارجها (ودجت معزولة) العربية افتراضاً
  /// كما في SPEC §1 — لا لغة `MaterialApp` الافتراضية (en_US).
  bool get isArabic {
    final l10n = AppLocalizations.of(this);
    if (l10n == null) return true;
    return l10n.localeName.startsWith('ar');
  }

  /// يعيد [ar] أو [en] حسب لغة الواجهة.
  String tr(String ar, String en) => isArabic ? ar : en;
}
