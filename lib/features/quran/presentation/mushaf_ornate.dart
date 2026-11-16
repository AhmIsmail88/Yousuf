import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ألوان زخرفة مصحف المدينة (طبعة المجمع ١٤٤٠): أزرق سماوي، كحلي، ووردي.
class MadinahOrnament {
  MadinahOrnament._();

  static const Color sky = Color(0xFF3FB2DD);
  static const Color skyLight = Color(0xFFBFE6F5);
  static const Color navy = Color(0xFF1B2F5C);
  static const Color pink = Color(0xFFD9468F);
  static const Color white = Color(0xFFFFFFFF);

  /// عرض الشريط المزخرف حول الصفحة.
  static const double band = 15;

  /// المسافة من حافة الإطار إلى بداية المحتوى.
  static const double inset = band + 7;
}

/// إطار صفحة مصحف المدينة: شريط سماوي بين خطّين كحليين، فيه ضفيرة متشابكة
/// (أبيض ووردي)، ووردة في كل ركن، وخطّ داخلي رفيع — مرسوم برمجياً بالكامل.
class MadinahOrnateFramePainter extends CustomPainter {
  const MadinahOrnateFramePainter({required this.fill});

  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const band = MadinahOrnament.band;
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = fill);

    final outer = rect.deflate(1);
    final inner = rect.deflate(band + 1);
    final navy = Paint()
      ..style = PaintingStyle.stroke
      ..color = MadinahOrnament.navy;

    // أرضية الشريط.
    final bandPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outer)
      ..addRect(inner);
    canvas.drawPath(bandPath, Paint()..color = MadinahOrnament.sky);

    // الضفيرة على الأضلاع الأربعة (بين الأركان).
    final mid = band / 2 + 1;
    final corner = band + 1;
    canvas.save();
    canvas.clipPath(bandPath);
    _braid(canvas, Offset(corner, mid), Offset(size.width - corner, mid));
    _braid(
      canvas,
      Offset(corner, size.height - mid),
      Offset(size.width - corner, size.height - mid),
    );
    _braid(canvas, Offset(mid, corner), Offset(mid, size.height - corner));
    _braid(
      canvas,
      Offset(size.width - mid, corner),
      Offset(size.width - mid, size.height - corner),
    );
    canvas.restore();

    // الخطوط: كحلي عريض خارجي، كحلي داخلي، ثم خط وردي رفيع وخط كحلي رفيع.
    canvas.drawRect(outer, navy..strokeWidth = 2);
    canvas.drawRect(inner, navy..strokeWidth = 1.4);
    canvas.drawRect(
      inner.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = MadinahOrnament.pink.withValues(alpha: 0.7),
    );
    canvas.drawRect(inner.deflate(5), navy..strokeWidth = 0.7);

    // ورود الأركان.
    for (final c in [
      Offset(mid, mid),
      Offset(size.width - mid, mid),
      Offset(mid, size.height - mid),
      Offset(size.width - mid, size.height - mid),
    ]) {
      _cornerRosette(canvas, c, band / 2 + 1);
    }
  }

  /// ضفيرة: موجتان متعاكستان (بيضاء ووردية) بحدود كحلية + نقاط بينهما.
  void _braid(Canvas canvas, Offset a, Offset b) {
    final length = (b - a).distance;
    if (length <= 0) return;
    final dir = (b - a) / length;
    final normal = Offset(-dir.dy, dir.dx);
    const band = MadinahOrnament.band;
    final amplitude = band * 0.27;
    final period = band * 1.5;
    final count = math.max(1, (length / period).round());
    final step = length / count;

    Path wave(double phase) {
      final path = Path();
      const samples = 10;
      for (var i = 0; i <= count * samples; i++) {
        final t = i / samples * step;
        final y = math.sin(t / step * 2 * math.pi + phase) * amplitude;
        final p = a + dir * t + normal * y;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      return path;
    }

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = MadinahOrnament.navy;
    for (final (phase, color) in [
      (0.0, MadinahOrnament.white),
      (math.pi, MadinahOrnament.pink),
    ]) {
      final path = wave(phase);
      canvas.drawPath(path, outline..strokeWidth = 3.4);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.8
          ..color = color,
      );
    }
    // نقاط بيضاء في عيون الضفيرة.
    final dot = Paint()..color = MadinahOrnament.white;
    for (var i = 0; i < count; i++) {
      final p = a + dir * (step * (i + 0.25)) + normal * 0;
      canvas.drawCircle(p, 1.1, dot);
      final q = a + dir * (step * (i + 0.75));
      canvas.drawCircle(q, 1.1, dot);
    }
  }

  void _cornerRosette(Canvas canvas, Offset c, double r) {
    canvas.drawRect(
      Rect.fromCenter(center: c, width: r * 2, height: r * 2),
      Paint()..color = MadinahOrnament.navy,
    );
    final petal = Paint()..color = MadinahOrnament.skyLight;
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4;
      final p = c + Offset(math.cos(angle), math.sin(angle)) * r * 0.5;
      canvas.drawCircle(p, r * 0.3, petal);
    }
    canvas.drawCircle(c, r * 0.38, Paint()..color = MadinahOrnament.pink);
    canvas.drawCircle(c, r * 0.15, Paint()..color = MadinahOrnament.white);
  }

  @override
  bool shouldRepaint(MadinahOrnateFramePainter old) => old.fill != fill;
}

/// خرطوشة مصحف المدينة (اسم السورة/الجزء في الترويسة، ورقم الصفحة):
/// مستطيل بطرفين مقوّسين، أرضية سماوية فاتحة وحدّ كحلي مزدوج.
class MadinahCartouche extends StatelessWidget {
  const MadinahCartouche({
    super.key,
    required this.child,
    this.compact = false,
  });

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _CartouchePainter(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 18,
          vertical: compact ? 1 : 2,
        ),
        child: child,
      ),
    );
  }
}

class _CartouchePainter extends CustomPainter {
  const _CartouchePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(r),
    );
    canvas.drawRRect(rrect, Paint()..color = MadinahOrnament.skyLight);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = MadinahOrnament.navy;
    canvas.drawRRect(rrect.deflate(0.6), stroke..strokeWidth = 1.2);
    canvas.drawRRect(
      rrect.deflate(2.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = MadinahOrnament.sky,
    );
    // نقطتان ورديتان على الطرفين.
    final dot = Paint()..color = MadinahOrnament.pink;
    canvas.drawCircle(Offset(r * 0.75, r), 1.8, dot);
    canvas.drawCircle(Offset(size.width - r * 0.75, r), 1.8, dot);
  }

  @override
  bool shouldRepaint(_CartouchePainter old) => false;
}
