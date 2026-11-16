import 'package:flutter/material.dart';

import 'package:yousuf/app/theme/app_colors.dart';

/// إطار صفحة مصحف مزخرف — على نمط مصحف المدينة (خطوط مزدوجة + زخارف أركان).
class OrnamentFrame extends StatelessWidget {
  const OrnamentFrame({
    super.key,
    required this.child,
    this.color = AppColors.deepSand,
    this.fill,
    this.radius = 24,
    this.strokeWidth = 2.2,
    this.padding = const EdgeInsets.fromLTRB(22, 18, 22, 26),
    this.minHeight,
  });

  final Widget child;
  final Color color;
  final Color? fill;
  final double radius;
  final double strokeWidth;
  final EdgeInsets padding;

  /// أدنى ارتفاع للصفحة — لتظهر كصفحة مصحف كاملة ولو كان النص قصيراً.
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FramePainter(
        color: color,
        fill: fill ?? Theme.of(context).colorScheme.surface,
        radius: radius,
        strokeWidth: strokeWidth,
      ),
      child: Padding(
        padding: padding,
        child: minHeight == null
            ? child
            : ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight!),
                child: child,
              ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter({
    required this.color,
    required this.fill,
    required this.radius,
    required this.strokeWidth,
  });

  final Color color;
  final Color fill;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );

    canvas.drawRRect(outer, Paint()..color = fill);
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = color,
    );

    final inner = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth + 4),
      Radius.circular(radius - 5),
    );
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = color.withValues(alpha: 0.5),
    );

    _paintCorners(canvas, size);
    _paintMidDiamonds(canvas, size);
  }

  /// زخرفة ركن: قوسان متوازيان + نقطة.
  void _paintCorners(Canvas canvas, Size size) {
    const arm = 18.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.9);
    final dot = Paint()..color = color.withValues(alpha: 0.8);

    final inset = strokeWidth + 5;
    final corners = <(Offset, double, double)>[
      (Offset(inset, inset), 1, 1),
      (Offset(size.width - inset, inset), -1, 1),
      (Offset(inset, size.height - inset), 1, -1),
      (Offset(size.width - inset, size.height - inset), -1, -1),
    ];

    for (final (origin, dx, dy) in corners) {
      final outer = Path()
        ..moveTo(origin.dx + dx * arm, origin.dy)
        ..quadraticBezierTo(
          origin.dx,
          origin.dy,
          origin.dx,
          origin.dy + dy * arm,
        );
      final inner = Path()
        ..moveTo(origin.dx + dx * (arm + 5), origin.dy)
        ..quadraticBezierTo(
          origin.dx,
          origin.dy,
          origin.dx,
          origin.dy + dy * (arm + 5),
        );
      canvas.drawPath(outer, paint);
      canvas.drawPath(inner, paint);
      canvas.drawCircle(
        Offset(origin.dx + dx * 7, origin.dy + dy * 7),
        1.6,
        dot,
      );
    }
  }

  /// معيّن صغير في منتصف كل ضلع.
  void _paintMidDiamonds(Canvas canvas, Size size) {
    void diamond(Offset center) {
      final path = Path()
        ..moveTo(center.dx, center.dy - 3.4)
        ..lineTo(center.dx + 3.4, center.dy)
        ..lineTo(center.dx, center.dy + 3.4)
        ..lineTo(center.dx - 3.4, center.dy)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.75));
    }

    diamond(Offset(size.width / 2, strokeWidth + 4));
    diamond(Offset(size.width / 2, size.height - strokeWidth - 4));
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) =>
      color != oldDelegate.color ||
      fill != oldDelegate.fill ||
      radius != oldDelegate.radius ||
      strokeWidth != oldDelegate.strokeWidth;
}

/// فاصل زخرفي: خط رفيع ينتهي بمعيّنين ونقطة في المنتصف.
class OrnamentDivider extends StatelessWidget {
  const OrnamentDivider({
    super.key,
    this.color = AppColors.deepSand,
    this.width = double.infinity,
  });

  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 14,
      child: CustomPaint(painter: _DividerPainter(color)),
    );
  }
}

class _DividerPainter extends CustomPainter {
  const _DividerPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1;

    canvas.drawLine(Offset(0, mid), Offset(size.width * 0.42, mid), paint);
    canvas.drawLine(
      Offset(size.width * 0.58, mid),
      Offset(size.width, mid),
      paint,
    );

    final center = Offset(size.width / 2, mid);
    canvas.drawCircle(center, 2.4, Paint()..color = color);
    for (final dx in [-8.0, 8.0]) {
      final path = Path()
        ..moveTo(center.dx + dx, mid - 3)
        ..lineTo(center.dx + dx + 3, mid)
        ..lineTo(center.dx + dx, mid + 3)
        ..lineTo(center.dx + dx - 3, mid)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(_DividerPainter oldDelegate) => color != oldDelegate.color;
}

/// لوحة اسم السورة المزخرفة — شريط بقوس مركزي ومعيّنات على الطرفين.
class SurahHeaderBand extends StatelessWidget {
  const SurahHeaderBand({
    super.key,
    required this.title,
    required this.subtitle,
    this.fontScale = 1,
  });

  final String title;
  final String subtitle;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return CustomPaint(
      painter: _HeaderPainter(
        color: AppColors.deepSand,
        fill: AppColors.shadow.withValues(alpha: 0.55),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 26 * fontScale,
          vertical: 9 * fontScale,
        ),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                fontFamily: 'Amiri',
                fontSize: (textTheme.titleLarge?.fontSize ?? 22) * fontScale,
                color: AppColors.deepTeal,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(
                color: AppColors.deepSand,
                fontSize: 10 * fontScale,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderPainter extends CustomPainter {
  const _HeaderPainter({required this.color, required this.fill});

  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas.drawRRect(rrect, Paint()..color = fill);
    canvas.drawRRect(
      rrect.deflate(0.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color,
    );
    canvas.drawRRect(
      rrect.deflate(5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = color.withValues(alpha: 0.55),
    );

    // خطان قصيران على الطرفين حول اسم السورة.
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..strokeWidth = 0.9;
    final y = size.height / 2;
    canvas.drawLine(Offset(16, y), Offset(40, y), linePaint);
    canvas.drawLine(
      Offset(size.width - 40, y),
      Offset(size.width - 16, y),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(_HeaderPainter oldDelegate) =>
      color != oldDelegate.color || fill != oldDelegate.fill;
}

/// زخرفة صغيرة تُرسم حول البسملة (خطّان + معيّن).
class BasmalaOrnament extends StatelessWidget {
  const BasmalaOrnament({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(child: OrnamentDivider(color: AppColors.deepSand)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: child,
        ),
        Expanded(child: OrnamentDivider(color: AppColors.deepSand)),
      ],
    );
  }
}
