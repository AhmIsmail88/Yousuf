import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/prefs/shared_preferences_provider.dart';
import '../../../core/widgets/ornament.dart';
import 'mushaf_ornate.dart';

/// أشكال إطار صفحة المصحف — يختار المستخدم ما يحبه (كلها مرسومة برمجياً).
enum MushafFrameStyle {
  // الافتراضي: زخرفة مصحف المدينة (طبعة المجمع) — شريط سماوي بضفيرة.
  ornate('ornate', 'مصحف المدينة المزخرف', 'Madinah ornate'),
  none('none', 'صفحة المصحف (بلا إطار)', 'Plain page'),
  madinah('madinah', 'إطار مذهّب', 'Gilded frame'),
  geometric('geometric', 'زخرفة هندسية', 'Geometric'),
  floral('floral', 'تذهيب نباتي', 'Floral gilding'),
  simple('simple', 'إطار بسيط', 'Simple');

  const MushafFrameStyle(this.id, this.labelAr, this.labelEn);

  final String id;
  final String labelAr;
  final String labelEn;

  String label({required bool arabic}) => arabic ? labelAr : labelEn;

  static MushafFrameStyle fromId(String? id) => values.firstWhere(
    (style) => style.id == id,
    orElse: () => MushafFrameStyle.ornate,
  );
}

/// لون ورق الصفحة.
enum MushafPaper {
  white('white', 'أبيض', 'White'),
  cream('cream', 'كريمي', 'Cream'),
  sepia('sepia', 'عاجي دافئ', 'Warm ivory');

  const MushafPaper(this.id, this.labelAr, this.labelEn);

  final String id;
  final String labelAr;
  final String labelEn;

  String label({required bool arabic}) => arabic ? labelAr : labelEn;

  /// لون الورق في الوضع الفاتح (في الداكن يُستخدم سطح الثيم).
  Color get color => switch (this) {
    MushafPaper.white => Colors.white,
    MushafPaper.cream => const Color(0xFFFBF8EF),
    MushafPaper.sepia => const Color(0xFFF5EBD6),
  };

  static MushafPaper fromId(String? id) => values.firstWhere(
    (paper) => paper.id == id,
    orElse: () => MushafPaper.cream,
  );
}

/// حجم خط المصحف. الأحجام الكبيرة تُبقي الخط مقروءاً (للأطفال وكبار السن)
/// وتُمرَّر الصفحة إن لم تتسع للشاشة؛ «صفحة كاملة» تصغّر الخط حتى تتسع.
enum MushafTextSize {
  page('page', 'صفحة كاملة', 'Whole page', 0),
  medium('medium', 'متوسط', 'Medium', 18),
  large('large', 'كبير', 'Large', 21),
  xlarge('xlarge', 'كبير جداً', 'Extra large', 25);

  const MushafTextSize(this.id, this.labelAr, this.labelEn, this.minPoints);

  final String id;
  final String labelAr;
  final String labelEn;

  /// أصغر حجم يُسمح به لنص الآيات (قبل حجم خط النظام)؛ ٠ = بلا حدّ.
  final double minPoints;

  String label({required bool arabic}) => arabic ? labelAr : labelEn;

  static MushafTextSize fromId(String? id) => values.firstWhere(
    (size) => size.id == id,
    orElse: () => MushafTextSize.large,
  );
}

typedef MushafAppearance = ({
  MushafFrameStyle frame,
  MushafPaper paper,
  MushafTextSize textSize,
});

class MushafAppearanceNotifier extends Notifier<MushafAppearance> {
  static const _frameKey = 'quran.frame_style';
  static const _paperKey = 'quran.paper';
  static const _textSizeKey = 'quran.text_size';

  @override
  MushafAppearance build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return (
      frame: MushafFrameStyle.fromId(prefs.getString(_frameKey)),
      paper: MushafPaper.fromId(prefs.getString(_paperKey)),
      textSize: MushafTextSize.fromId(prefs.getString(_textSizeKey)),
    );
  }

  Future<void> setFrame(MushafFrameStyle frame) async {
    await ref.read(sharedPreferencesProvider).setString(_frameKey, frame.id);
    state = (frame: frame, paper: state.paper, textSize: state.textSize);
  }

  Future<void> setPaper(MushafPaper paper) async {
    await ref.read(sharedPreferencesProvider).setString(_paperKey, paper.id);
    state = (frame: state.frame, paper: paper, textSize: state.textSize);
  }

  Future<void> setTextSize(MushafTextSize size) async {
    await ref.read(sharedPreferencesProvider).setString(_textSizeKey, size.id);
    state = (frame: state.frame, paper: state.paper, textSize: size);
  }
}

final mushafAppearanceProvider =
    NotifierProvider<MushafAppearanceNotifier, MushafAppearance>(
      MushafAppearanceNotifier.new,
    );

/// إطار الصفحة حسب الشكل المختار.
class MushafPageFrame extends StatelessWidget {
  const MushafPageFrame({
    super.key,
    required this.style,
    required this.paper,
    required this.child,
    required this.padding,
    this.minHeight,
  });

  final MushafFrameStyle style;
  final Color paper;
  final Widget child;
  final EdgeInsets padding;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gold = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFC9B394)
        : const Color(0xFF876A44);
    Widget content = Padding(
      padding: padding,
      child: minHeight == null
          ? child
          : ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight!),
              child: child,
            ),
    );
    switch (style) {
      case MushafFrameStyle.ornate:
        return CustomPaint(
          painter: MadinahOrnateFramePainter(fill: paper),
          child: Padding(
            padding: const EdgeInsets.all(MadinahOrnament.inset),
            child: content,
          ),
        );
      case MushafFrameStyle.madinah:
        return OrnamentFrame(
          fill: paper,
          color: gold,
          padding: padding,
          minHeight: minHeight,
          child: child,
        );
      case MushafFrameStyle.none:
        return ColoredBox(color: paper, child: content);
      case MushafFrameStyle.simple:
      case MushafFrameStyle.geometric:
      case MushafFrameStyle.floral:
        return CustomPaint(
          painter: _StylePainter(
            style: style,
            color: gold,
            accent: scheme.primary,
            fill: paper,
          ),
          child: Padding(
            padding: style == MushafFrameStyle.simple
                ? EdgeInsets.zero
                : const EdgeInsets.all(10),
            child: content,
          ),
        );
    }
  }
}

class _StylePainter extends CustomPainter {
  const _StylePainter({
    required this.style,
    required this.color,
    required this.accent,
    required this.fill,
  });

  final MushafFrameStyle style;
  final Color color;
  final Color accent;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      Paint()..color = fill,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..color = color;

    if (style == MushafFrameStyle.simple) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(14)),
        line..strokeWidth = 1.2,
      );
      return;
    }

    // شريط حدود بعرض ١٠ بين خطين.
    const band = 10.0;
    final outer = rect.deflate(1.5);
    final inner = rect.deflate(band + 1.5);
    canvas.drawRect(outer, line..strokeWidth = 1.6);
    canvas.drawRect(inner, line..strokeWidth = 1.0);

    final ornament = Paint()..color = color.withValues(alpha: 0.85);
    final accentPaint = Paint()..color = accent.withValues(alpha: 0.55);

    // نقاط مكررة على طول الشريط.
    Iterable<Offset> along(Offset a, Offset b, double step) sync* {
      final length = (b - a).distance;
      final count = math.max(1, (length / step).floor());
      for (var i = 0; i <= count; i++) {
        yield Offset.lerp(a, b, i / count)!;
      }
    }

    final mid = band / 2 + 1.5;
    final edges = [
      (Offset(mid, mid), Offset(size.width - mid, mid)),
      (
        Offset(mid, size.height - mid),
        Offset(size.width - mid, size.height - mid),
      ),
      (Offset(mid, mid), Offset(mid, size.height - mid)),
      (
        Offset(size.width - mid, mid),
        Offset(size.width - mid, size.height - mid),
      ),
    ];

    for (final (a, b) in edges) {
      for (final p in along(a, b, 16)) {
        if (style == MushafFrameStyle.geometric) {
          _star(canvas, p, 3.6, ornament);
        } else {
          _leaf(canvas, p, 3.4, ornament, accentPaint);
        }
      }
    }

    // ورود الأركان.
    for (final c in [
      Offset(mid, mid),
      Offset(size.width - mid, mid),
      Offset(mid, size.height - mid),
      Offset(size.width - mid, size.height - mid),
    ]) {
      canvas.drawCircle(c, band / 2 + 1, Paint()..color = fill);
      canvas.drawCircle(c, band / 2, line..strokeWidth = 1.2);
      canvas.drawCircle(c, 2.2, accentPaint);
    }
  }

  /// نجمة ثمانية صغيرة (مربعان متراكبان).
  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    for (final angle in [0.0, math.pi / 4]) {
      final path = Path();
      for (var i = 0; i < 4; i++) {
        final a = angle + i * math.pi / 2;
        final p = c + Offset(math.cos(a), math.sin(a)) * r;
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  /// ورقة نباتية: بيضاوي صغير بنقطة لون ثانٍ.
  void _leaf(Canvas canvas, Offset c, double r, Paint paint, Paint accent) {
    canvas.drawOval(
      Rect.fromCenter(center: c, width: r * 2.4, height: r * 1.3),
      paint,
    );
    canvas.drawCircle(c, r * 0.35, accent);
  }

  @override
  bool shouldRepaint(_StylePainter old) =>
      old.style != style ||
      old.color != color ||
      old.fill != fill ||
      old.accent != accent;
}
