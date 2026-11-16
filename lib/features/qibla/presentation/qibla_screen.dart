import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yousuf/core/l10n/formatters.dart';
import 'package:yousuf/core/l10n/tr.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yousuf/core/platform/adhan_channel.dart';
import 'package:yousuf/features/prayer/presentation/prayer_providers.dart';

import '../domain/qibla_math.dart';

/// مصدر قراءات البوصلة — يُستبدل في الاختبارات بقناة وهمية.
final qiblaCompassStreamProvider = Provider<Stream<CompassEvent>?>(
  (ref) => FlutterCompass.events,
);

/// الانحراف المغناطيسي للموقع المختار (بالدرجات، موجب = شرقاً).
///
/// البوصلة على أندرويد تعطي الشمال المغناطيسي، والقبلة محسوبة من الشمال
/// الجغرافي؛ الفرق في مصر ~٤–٥° وقد يتجاوز ١٠° في مناطق أخرى.
final magneticDeclinationProvider = FutureProvider<double>((ref) async {
  final settings = await ref.watch(prayerSettingsProvider.future);
  try {
    return await AdhanChannel().magneticDeclination(
      settings.location.latitude,
      settings.location.longitude,
    );
  } catch (_) {
    return 0;
  }
});

/// حدّ اعتبار الهاتف على القبلة (بالدرجات).
const double kQiblaToleranceDegrees = 5.0;

/// مدة انتظار أول قراءة بوصلة قبل عرض بديل الشمس.
const Duration kCompassSilenceTimeout = Duration(seconds: 3);

/// أقل مدة بين اهتزازين متتاليين.
const Duration kHapticThrottle = Duration(milliseconds: 1500);

/// فرق القراءات الذي يُعدّ تذبذباً يستدعي المعايرة (بالدرجات).
const double kCalibrationJitterDegrees = 25.0;

/// شاشة القبلة — بوصلة حية مع بديل بالشمس عند غياب الحساس (SPEC §7.5).
class QiblaScreen extends ConsumerStatefulWidget {
  const QiblaScreen({super.key});

  @override
  ConsumerState<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends ConsumerState<QiblaScreen> {
  StreamSubscription<CompassEvent>? _subscription;
  Timer? _silenceTimer;
  Timer? _calibrationTimer;
  Timer? _sunRefreshTimer;

  /// أحدث قراءة خام (تُستخدم للاهتزاز وقياس التذبذب).
  double? _heading;

  /// آخر قراءة رُسمت فعلاً — لتقليل إعادة البناء عند الاهتزاز الدقيق.
  double? _paintedHeading;

  /// وقت آخر قراءة، لقياس التذبذب خلال ثانية.
  DateTime? _lastReadingAt;

  /// وقت آخر اهتزاز، لخنق التكرار.
  DateTime? _lastHapticAt;

  /// هل انقضت 3 ثوانٍ بلا أي قراءة بوصلة؟
  bool _compassSilent = false;

  /// هل القراءات متذبذبة الآن؟
  bool _showCalibration = false;

  /// حالة المحاذاة في القراءة السابقة (لكشف الدخول في النطاق).
  bool _wasAligned = false;

  @override
  void initState() {
    super.initState();
    _listenToCompass();
    // زاوية الشمس تتغير ببطء؛ نحدّثها دورياً حين يكون البديل معروضاً.
    _sunRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _compassSilent) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _silenceTimer?.cancel();
    _calibrationTimer?.cancel();
    _sunRefreshTimer?.cancel();
    super.dispose();
  }

  /// يشترك في مجرى البوصلة ويبدأ مؤقّت الصمت.
  void _listenToCompass() {
    _subscription?.cancel();
    _silenceTimer?.cancel();
    _silenceTimer = Timer(kCompassSilenceTimeout, () {
      if (!mounted) return;
      if (_heading == null) setState(() => _compassSilent = true);
    });

    final events = ref.read(qiblaCompassStreamProvider);
    _subscription = events?.listen(
      _onCompassEvent,
      onError: (Object _) => _onCompassUnavailable(),
      onDone: _onCompassUnavailable,
    );
  }

  /// لا قراءات من الحساس (خطأ أو انتهاء المجرى).
  void _onCompassUnavailable() {
    if (!mounted) return;
    if (_heading == null) setState(() => _compassSilent = true);
  }

  void _onCompassEvent(CompassEvent event) {
    final reading = event.heading;
    // بعض الأجهزة ترسل null قبل المعايرة؛ نتجاهلها ولا نعدّها قراءة.
    if (reading == null) return;

    final now = DateTime.now();
    // تصحيح الشمال المغناطيسي إلى الجغرافي.
    final declination = ref.read(magneticDeclinationProvider).value ?? 0;
    final heading = normalizeAngle(reading + declination);
    final previous = _heading;
    final elapsed = _lastReadingAt == null
        ? null
        : now.difference(_lastReadingAt!);
    final step = previous == null
        ? 180.0
        : shortestDelta(previous, heading).abs();

    // تذبذب: قراءتان متتاليتان خلال ثانية بفرق يتجاوز 25°.
    final unstable =
        elapsed != null &&
        elapsed <= const Duration(seconds: 1) &&
        step > kCalibrationJitterDegrees;

    _heading = heading;
    _lastReadingAt = now;

    if (unstable) {
      _showCalibration = true;
      _calibrationTimer?.cancel();
      _calibrationTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showCalibration = false);
      });
    }

    final painted = _paintedHeading;
    final shouldRepaint =
        _compassSilent ||
        unstable ||
        painted == null ||
        shortestDelta(painted, heading).abs() >= 0.5;
    if (shouldRepaint) {
      setState(() {
        _paintedHeading = heading;
        _compassSilent = false;
      });
    }

    _updateAlignment(heading, now);
  }

  /// اهتزاز عند الدخول في نطاق المحاذاة، بحد أدنى 1500ms بين اهتزازين.
  void _updateAlignment(double heading, DateTime now) {
    final location = ref.read(prayerSettingsProvider).value?.location;
    if (location == null) return;
    final bearing = qiblaBearing(location.latitude, location.longitude);
    final aligned =
        shortestDelta(heading, bearing).abs() <= kQiblaToleranceDegrees;

    if (aligned && !_wasAligned) {
      final last = _lastHapticAt;
      if (last == null || now.difference(last) >= kHapticThrottle) {
        _lastHapticAt = now;
        unawaited(HapticFeedback.mediumImpact());
      }
    }
    _wasAligned = aligned;
  }

  /// يعيد تشغيل الاستماع للبوصلة بعد فشل أو توقف.
  void _retry() {
    setState(() {
      _heading = null;
      _paintedHeading = null;
      _lastReadingAt = null;
      _compassSilent = false;
      _showCalibration = false;
      _wasAligned = false;
    });
    _listenToCompass();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(prayerSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('القبلة', 'Qibla'))),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            context.tr(
              'تعذر قراءة الموقع: $error',
              'Could not read location: $error',
            ),
          ),
        ),
        data: (settings) {
          final location = settings.location;
          final bearing = qiblaBearing(location.latitude, location.longitude);
          final heading = _paintedHeading;
          final delta = heading == null
              ? null
              : shortestDelta(heading, bearing);
          final aligned =
              delta != null && delta.abs() <= kQiblaToleranceDegrees;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              _CompassDial(
                heading: heading,
                qiblaBearing: bearing,
                aligned: aligned,
              ),
              const SizedBox(height: 20),
              _Readout(
                bearing: bearing,
                delta: delta,
                hasHeading: heading != null,
              ),
              if (_showCalibration) ...[
                const SizedBox(height: 12),
                _HintCard(
                  icon: Icons.explore_outlined,
                  title: context.tr(
                    'المعايرة: حرّك الهاتف على شكل ٨',
                    'Calibrate: move your phone in a figure 8',
                  ),
                  body: context.tr(
                    'حرّك الهاتف على شكل ٨ في الهواء عدة مرات ثم أعد توجيهه نحو القبلة.',
                    'Move the phone in a figure 8 a few times, then point it to the Qibla again.',
                  ),
                ),
              ],
              if (_compassSilent) ...[
                const SizedBox(height: 12),
                _SunFallbackCard(
                  bearing: bearing,
                  latitude: location.latitude,
                  longitude: location.longitude,
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.tr('إعادة المحاولة', 'Retry')),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr(
                  'دقة البوصلة تعتمد على حساس الجهاز؛ ابتعد عن المعادن والمجالات المغناطيسية. '
                      'الاتجاه مصحَّح للشمال الجغرافي.',
                  'Accuracy depends on the device sensor; keep away from metal and magnets. '
                      'The direction is corrected to true north.',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// نص زاوية القبلة وحالة التوجيه.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.bearing,
    required this.delta,
    required this.hasHeading,
  });

  final double bearing;
  final double? delta;
  final bool hasHeading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final angle = context.tr(
      '${context.digits(bearing.round())}° من الشمال',
      '${bearing.round()}° from north',
    );
    final delta = this.delta;
    final aligned = delta != null && delta.abs() <= kQiblaToleranceDegrees;

    final String status;
    if (!hasHeading || delta == null) {
      status = context.tr('جارٍ قراءة البوصلة…', 'Reading compass…');
    } else if (aligned) {
      status = context.tr('على القبلة', 'Facing the Qibla');
    } else {
      final direction = delta > 0
          ? context.tr('يميناً', 'right')
          : context.tr('يساراً', 'left');
      status = context.tr(
        'أدر الهاتف $direction بـ ${context.digits(delta.abs().round())}°',
        'Turn the phone $direction by ${delta.abs().round()}°',
      );
    }

    return Column(
      children: [
        Text(
          context.tr('زاوية القبلة: $angle', 'Qibla angle: $angle'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontFamily: 'Amiri',
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          status,
          textAlign: TextAlign.center,
          style: aligned
              ? theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'Amiri',
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                )
              : theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
        ),
      ],
    );
  }
}

/// بطاقة إرشادية عامة (المعايرة).
class _HintCard extends StatelessWidget {
  const _HintCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// بديل الشمس: يُعرض حين لا تصل أي قراءة بوصلة خلال 3 ثوانٍ.
class _SunFallbackCard extends StatelessWidget {
  const _SunFallbackCard({
    required this.bearing,
    required this.latitude,
    required this.longitude,
  });

  final double bearing;
  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sun = sunAzimuth(lat: latitude, lng: longitude, utc: DateTime.now());
    // زاوية الدوران المطلوبة من اتجاه الشمس إلى اتجاه القبلة.
    final turn = shortestDelta(sun, bearing);
    final turnText = turn.abs() <= kQiblaToleranceDegrees
        ? context.tr(
            'الشمس الآن في اتجاه القبلة تقريباً.',
            'The sun is roughly in the Qibla direction now.',
          )
        : context.tr(
            'قف والشمس أمامك ثم استدر ${turn > 0 ? 'يميناً' : 'يساراً'} بـ ${context.digits(turn.abs().round())}°.',
            'Face the sun, then turn ${turn > 0 ? 'right' : 'left'} by ${turn.abs().round()}°.',
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.wb_sunny_outlined,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr('بديل الشمس', 'Sun fallback'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(
              'زاوية الشمس الآن: ${context.digits(sun.round())}° من الشمال',
              'Sun angle now: ${sun.round()}° from north',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
              'زاوية القبلة: ${context.digits(bearing.round())}° من الشمال',
              'Qibla angle: ${bearing.round()}° from north',
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(turnText, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            context.tr(
              'قراءة تقريبية تتغير خلال النهار؛ الشمال في القرص أعلى الشاشة.',
              'Approximate reading that changes during the day; north is at the top of the dial.',
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// قرص البوصلة: الشمال أعلى، القرص يدور بعكس اتجاه الجهاز.
class _CompassDial extends StatelessWidget {
  const _CompassDial({
    required this.heading,
    required this.qiblaBearing,
    required this.aligned,
  });

  final double? heading;
  final double qiblaBearing;
  final bool aligned;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
        child: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(
            painter: _CompassDialPainter(
              headingDegrees: heading,
              qiblaDegrees: qiblaBearing,
              aligned: aligned,
              faceColor: scheme.surface,
              borderColor: scheme.outline,
              tickColor: scheme.onSurfaceVariant,
              labelColor: scheme.onSurface,
              northColor: scheme.primary,
              needleColor: aligned ? scheme.primary : scheme.secondary,
              arabic: context.isArabic,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _CompassDialPainter extends CustomPainter {
  const _CompassDialPainter({
    required this.headingDegrees,
    required this.qiblaDegrees,
    required this.aligned,
    required this.faceColor,
    required this.borderColor,
    required this.tickColor,
    required this.labelColor,
    required this.northColor,
    required this.needleColor,
    this.arabic = true,
  });

  /// اتجاه أعلى الجهاز؛ null يعني قرصاً ثابتاً (الشمال أعلى) لبديل الشمس.
  final double? headingDegrees;
  final double qiblaDegrees;
  final bool aligned;
  final Color faceColor;
  final Color borderColor;
  final Color tickColor;
  final Color labelColor;
  final Color northColor;
  final Color needleColor;

  /// أسماء الجهات بلغة الواجهة.
  final bool arabic;

  static const _cardinalsAr = <int, String>{
    0: 'ش',
    90: 'ق',
    180: 'ج',
    270: 'غ',
  };
  static const _cardinalsEn = <int, String>{
    0: 'N',
    90: 'E',
    180: 'S',
    270: 'W',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 2;
    if (radius <= 0) return;

    canvas.drawCircle(center, radius, Paint()..color = faceColor);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = borderColor,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    // القرص يدور بعكس اتجاه الجهاز ليبقى الشمال في موضعه الحقيقي.
    final rotation = headingDegrees == null
        ? 0.0
        : -headingDegrees! * math.pi / 180.0;
    canvas.rotate(rotation);

    _paintTicks(canvas, radius);
    _paintCardinals(canvas, radius);

    // عقرب القبلة.
    final needleAngle = qiblaDegrees * math.pi / 180.0;
    canvas.save();
    canvas.rotate(needleAngle);
    final needlePaint = Paint()
      ..color = needleColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(0, -radius * 0.58), needlePaint);
    // رأس العقرب.
    final head = Path()
      ..moveTo(0, -radius * 0.66)
      ..lineTo(-6, -radius * 0.55)
      ..lineTo(6, -radius * 0.55)
      ..close();
    canvas.drawPath(head, Paint()..color = needleColor);
    // علامة الكعبة عند الطرف.
    canvas.drawCircle(
      Offset(0, -radius * 0.72),
      radius * 0.045,
      Paint()..color = needleColor,
    );
    canvas.restore();

    // نقطة المركز.
    canvas.drawCircle(Offset.zero, 5, Paint()..color = needleColor);
    canvas.restore();

    // مؤشر أعلى الشاشة = اتجاه نظر المستخدم (ثابت لا يدور).
    final marker = Path()
      ..moveTo(center.dx, center.dy - radius + 12)
      ..lineTo(center.dx - 8, center.dy - radius + 1)
      ..lineTo(center.dx + 8, center.dy - radius + 1)
      ..close();
    canvas.drawPath(marker, Paint()..color = northColor);
  }

  void _paintTicks(Canvas canvas, double radius) {
    final majorPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final minorPaint = Paint()
      ..color = tickColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 8; i++) {
      final angle = i * 45.0 * math.pi / 180.0;
      final isMajor = i.isEven;
      final inner = radius * (isMajor ? 0.82 : 0.87);
      final outer = radius * 0.95;
      final direction = Offset(math.sin(angle), -math.cos(angle));
      canvas.drawLine(
        direction * inner,
        direction * outer,
        isMajor ? majorPaint : minorPaint,
      );
    }
  }

  void _paintCardinals(Canvas canvas, double radius) {
    // خط الشمال أطول وأوضح.
    final northPaint = Paint()
      ..color = northColor
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, -radius * 0.95),
      Offset(0, -radius * 0.74),
      northPaint,
    );

    for (final entry in (arabic ? _cardinalsAr : _cardinalsEn).entries) {
      final angle = entry.key * math.pi / 180.0;
      final painter = TextPainter(
        text: TextSpan(
          text: entry.value,
          style: TextStyle(
            color: entry.key == 0 ? northColor : labelColor,
            fontSize: radius * 0.11,
            fontWeight: entry.key == 0 ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
      )..layout();
      final position = Offset(
        math.sin(angle) * radius * 0.66,
        -math.cos(angle) * radius * 0.66,
      );
      painter.paint(
        canvas,
        position - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_CompassDialPainter oldDelegate) {
    return headingDegrees != oldDelegate.headingDegrees ||
        qiblaDegrees != oldDelegate.qiblaDegrees ||
        aligned != oldDelegate.aligned ||
        faceColor != oldDelegate.faceColor ||
        borderColor != oldDelegate.borderColor ||
        tickColor != oldDelegate.tickColor ||
        labelColor != oldDelegate.labelColor ||
        northColor != oldDelegate.northColor ||
        needleColor != oldDelegate.needleColor;
  }
}
