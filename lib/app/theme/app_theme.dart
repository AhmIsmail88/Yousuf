import 'package:flutter/material.dart';

import '../../core/utils/arabic_digits.dart';
import 'app_colors.dart';

/// ثيم التطبيق: فاتح وداكن، مبني على ألوان الهوية وخطوطها الثلاثة.
///
/// المخطط اللوني يُولَّد من الفيروزي العميق (Material 3) ثم تُثبَّت ألوان
/// الهوية الأساسية، فتحصل كل الأسطح (surfaceContainer…) ودرجات الحاويات
/// على قيم متناسقة في الوضعين — الشاشات تستخدم `colorScheme` لا ألواناً ثابتة.
class AppTheme {
  AppTheme._();

  /// خط الواجهة الأساسي.
  static const String uiFont = 'IBM Plex Sans Arabic';

  /// خط العناوين والآيات.
  static const String displayFont = 'Amiri';

  /// خط نص القرآن: خط مجمع الملك فهد بنسخة Tanzil، ونص Tanzil كما هو.
  static const String quranFont = 'Hafs';

  /// ما لا يغطيه خط المصحف (﴿ ﴾ والأقواس…) يُرسم بالأميري.
  static const List<String> quranFallback = ['Amiri'];

  /// خط الاسم اللاتيني YOUSUF.
  static const String latinFont = 'Cinzel';

  static ThemeData get light => _theme(Brightness.light);

  static ThemeData get dark => _theme(Brightness.dark);

  /// ثيم بلون وصيغة أرقام محددة — تغيير الصيغة يُعيد بناء الواجهة فوراً
  /// (لأن الثيم InheritedWidget تعتمد عليه كل الشاشات).
  static ThemeData of(Brightness brightness, DigitStyle digitStyle) =>
      _theme(brightness, digitStyle: digitStyle);

  static ColorScheme scheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.deepTeal,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    return isLight
        ? base.copyWith(
            primary: AppColors.deepTeal,
            onPrimary: Colors.white,
            secondary: AppColors.deepSand,
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFFF1E6D3),
            onSecondaryContainer: const Color(0xFF4A3920),
            tertiaryContainer: const Color(0xFFE3EFE6),
            onTertiaryContainer: const Color(0xFF1F4A3A),
            surface: AppColors.cream,
            onSurface: AppColors.ink,
            onSurfaceVariant: AppColors.inkSoft,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: Colors.white,
            surfaceContainer: const Color(0xFFEFF6F3),
            surfaceContainerHigh: const Color(0xFFE6F0ED),
            surfaceContainerHighest: AppColors.shadow,
            outlineVariant: AppColors.shadow,
          )
        : base.copyWith(
            primary: AppColors.brandTeal,
            onPrimary: AppColors.darkBackground,
            primaryContainer: const Color(0xFF1F4F58),
            onPrimaryContainer: const Color(0xFFCFE8EE),
            secondary: AppColors.sand,
            onSecondary: AppColors.darkBackground,
            secondaryContainer: const Color(0xFF3B3222),
            onSecondaryContainer: const Color(0xFFF0E2C8),
            tertiaryContainer: const Color(0xFF24433A),
            onTertiaryContainer: const Color(0xFFD3EEE0),
            surface: AppColors.darkBackground,
            onSurface: const Color(0xFFE6F0EE),
            onSurfaceVariant: const Color(0xFFAFC4C6),
            surfaceContainerLowest: const Color(0xFF0B1D22),
            surfaceContainerLow: AppColors.darkSurface,
            surfaceContainer: const Color(0xFF1A3A42),
            surfaceContainerHigh: const Color(0xFF214650),
            surfaceContainerHighest: const Color(0xFF29525C),
            outline: const Color(0xFF5E7E84),
            outlineVariant: const Color(0xFF2C4F57),
          );
  }

  static ThemeData _theme(
    Brightness brightness, {
    DigitStyle digitStyle = DigitStyle.hindi,
  }) {
    final colorScheme = scheme(brightness);
    final baseText = ThemeData(brightness: brightness).textTheme;

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: [DigitsTheme(digitStyle)],
      scaffoldBackgroundColor: colorScheme.surface,
      fontFamily: uiFont,
      textTheme: baseText.copyWith(
        displayLarge: baseText.displayLarge?.copyWith(fontFamily: displayFont),
        displayMedium: baseText.displayMedium?.copyWith(
          fontFamily: displayFont,
        ),
        displaySmall: baseText.displaySmall?.copyWith(fontFamily: displayFont),
        headlineLarge: baseText.headlineLarge?.copyWith(
          fontFamily: displayFont,
        ),
        headlineMedium: baseText.headlineMedium?.copyWith(
          fontFamily: displayFont,
        ),
        headlineSmall: baseText.headlineSmall?.copyWith(
          fontFamily: displayFont,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),
      chipTheme: ChipThemeData(
        selectedColor: colorScheme.primaryContainer,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),
    );
  }
}

/// امتداد ثيم يحمل صيغة الأرقام — يضمن إعادة بناء الشاشات عند تغييرها
/// بدل الانتظار حتى إعادة تشغيل التطبيق.
class DigitsTheme extends ThemeExtension<DigitsTheme> {
  const DigitsTheme(this.style);

  final DigitStyle style;

  @override
  DigitsTheme copyWith({DigitStyle? style}) => DigitsTheme(style ?? this.style);

  @override
  DigitsTheme lerp(ThemeExtension<DigitsTheme>? other, double t) {
    if (other is! DigitsTheme) return this;
    return t < 0.5 ? this : other;
  }
}
