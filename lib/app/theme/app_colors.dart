import 'package:flutter/material.dart';

/// ألوان الهوية المعتمدة — من لوحة «الهوية والشعار» (assets).
class AppColors {
  AppColors._();

  static const Color cream = Color(0xFFF6FCF5); // كريمي — خلفية الوضع الفاتح
  static const Color deepSand = Color(0xFF876A44); // رملي عميق — لون ثانوي
  static const Color sand = Color(0xFFC9B394); // رملي — لمسات دافئة
  static const Color shadow = Color(0xFFCEE0DD); // ظل — حدود وأسطح خفيفة
  static const Color brandTeal = Color(0xFF8FB9C2); // فيروزي الشعار
  static const Color deepTeal = Color(0xFF2F6F7A); // فيروزي عميق — الأساسي

  // ألوان مشتقة لازمة للواجهة وليست في اللوحة الأصلية — تُراجع مع التصميم.
  static const Color ink = Color(
    0xFF1C3B42,
  ); // نص أساسي (مشتق من الفيروزي العميق)
  static const Color inkSoft = Color(0xFF5B7076); // نص ثانوي
  static const Color darkBackground = Color(0xFF10262C); // خلفية الوضع الداكن
  static const Color darkSurface = Color(0xFF16343C); // سطح الوضع الداكن
}
