import 'package:flutter/material.dart';

import 'package:yousuf/app/theme/app_colors.dart';

/// مدة حركة شاشة البداية كاملة — تنتظرها جاهزية التطبيق (`AppReadyNotifier`).
const Duration kSplashAnimation = Duration(milliseconds: 4200);

/// مدة بقاء شاشة البداية كاملة بعد انتهاء الحركة — ليُقرأ «رفيقك في الطاعة».
const Duration kSplashHold = Duration(milliseconds: 1300);

/// شاشة البداية المتحركة — على تصميم assets/شاشة البداية.png ولوحة الهوية:
///
/// ١. الشعار المزخرف يظهر في منتصف الشاشة (تلاشٍ وتكبير خفيف).
/// ٢. يصعد إلى أعلى الصفحة ويصغر قليلاً.
/// ٣. يظهر تحته شريط «YOUSUF» بخط Cinzel على اللون الرملي (#C9B394).
/// ٤. ثم «رفيقك في الطاعة» بخط Amiri، وتحته السطر الإنجليزي.
/// ٥. وأخيراً النقاط و«صدقة جارية — فكرة يوسف».
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kSplashAnimation,
  )..forward();

  Animation<double> _phase(
    double begin,
    double end, [
    Curve curve = Curves.easeOut,
  ]) => CurvedAnimation(
    parent: _controller,
    curve: Interval(begin, end, curve: curve),
  );

  late final Animation<double> _logoIn = _phase(0.0, 0.22, Curves.easeOutBack);
  late final Animation<double> _logoUp = _phase(
    0.28,
    0.52,
    Curves.easeInOutCubic,
  );
  late final Animation<double> _banner = _phase(0.48, 0.66);
  late final Animation<double> _tagline = _phase(0.62, 0.80);
  late final Animation<double> _english = _phase(0.72, 0.88);
  late final Animation<double> _footer = _phase(0.82, 1.0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// يظهر مع انزلاق خفيف للأعلى.
  Widget _reveal(Animation<double> animation, Widget child) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) => Opacity(
      opacity: animation.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 18 * (1 - animation.value)),
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;
            final logoWidth = (width * 0.68).clamp(180.0, 320.0);
            final logoHeight = logoWidth * 408 / 768; // نسبة الصورة
            // الموضع: منتصف الشاشة ← ربعها العلوي.
            final startTop = (height - logoHeight) / 2;
            final endTop = height * 0.16;
            const endScale = 0.86;
            final textTop = endTop + logoHeight * endScale + 28;

            return Stack(
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final up = _logoUp.value;
                    final scaleIn = 0.86 + 0.14 * _logoIn.value;
                    final scale = scaleIn * (1 - (1 - endScale) * up);
                    return Positioned(
                      top: startTop + (endTop - startTop) * up,
                      left: (width - logoWidth) / 2,
                      width: logoWidth,
                      height: logoHeight,
                      child: Opacity(
                        opacity: _logoIn.value.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: scale,
                          alignment: Alignment.topCenter,
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: Image.asset(
                    'assets/brand/logo_splash.png',
                    fit: BoxFit.contain,
                    semanticLabel: 'يوسف',
                  ),
                ),
                Positioned(
                  top: textTop,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      _reveal(
                        _banner,
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 10,
                          ),
                          color: AppColors.sand,
                          child: const Text(
                            'YOUSUF',
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 26,
                              letterSpacing: 7,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      _reveal(
                        _tagline,
                        const Text(
                          'رفيقك في الطاعة',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontFamily: 'Amiri',
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: AppColors.deepTeal,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _reveal(
                        _english,
                        const Text(
                          'Your daily companion in faith',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 14,
                            letterSpacing: 1.2,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: _reveal(
                    _footer,
                    const Column(
                      children: [
                        _Dots(),
                        SizedBox(height: 14),
                        Text(
                          'صدقة جارية — فكرة يوسف',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final color in const [
          AppColors.shadow,
          AppColors.brandTeal,
          AppColors.deepTeal,
        ])
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
      ],
    );
  }
}
