/// حسابات القبلة وزاوية الشمس — Dart خالص بلا اعتماد على Flutter (SPEC §7.5).
///
/// كل الزوايا هنا بالدرجات، والشمال الحقيقي هو الصفر، والاتجاه موجب مع عقارب
/// الساعة (شرق = 90، جنوب = 180، غرب = 270).
library;

import 'dart:math' as math;

/// خط عرض الكعبة (مكة المكرمة).
const double kaabaLatitude = 21.4225;

/// خط طول الكعبة (مكة المكرمة).
const double kaabaLongitude = 39.8262;

/// عدد الأيام بين 1970-01-01 و J2000.0 (2000-01-01 12:00 UT).
const double _daysToJ2000 = 10957.5;

const double _degreesPerRadian = 180.0 / math.pi;
const double _radiansPerDegree = math.pi / 180.0;

/// الاتجاه الابتدائي لدائرة عظمى من الموقع إلى الكعبة، بالدرجات من الشمال
/// الحقيقي باتجاه عقارب الساعة.
///
/// تُستخدم صيغة الاتجاه الابتدائي (initial great-circle bearing) مباشرة، فهي
/// أدق من حساب زاوية المستوى عند المسافات الطويلة.
double qiblaBearing(double lat, double lng) {
  final phi1 = lat * _radiansPerDegree;
  final phi2 = kaabaLatitude * _radiansPerDegree;
  final deltaLng = (kaabaLongitude - lng) * _radiansPerDegree;

  final y = math.sin(deltaLng) * math.cos(phi2);
  final x =
      math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(deltaLng);

  // عند وقوف المستخدم في الكعبة نفسها يكون الاتجاه غير معرّف؛ نعيد 0.
  if (x == 0 && y == 0) return 0;

  return normalizeAngle(math.atan2(y, x) * _degreesPerRadian);
}

/// يطبع زاوية بالدرجات إلى المدى 0..360.
///
/// معامل `%` في Dart يُرجع قيمة غير سالبة دائماً عند مقسوم عليه موجب، لذا
/// تكفي عملية واحدة (−90 ← 270).
double normalizeAngle(double degrees) => degrees % 360.0;

/// أقصر فرق زاوي من `fromDeg` إلى `toDeg`، في المدى −180..180.
///
/// الإشارة الموجبة تعني أن الهدف في اتجاه عقارب الساعة (إلى اليمين عند
/// النظر إلى قرص البوصلة)، والسلبية تعني عكسه.
double shortestDelta(double fromDeg, double toDeg) {
  final delta = (toDeg - fromDeg) % 360.0; // 0..360
  return delta > 180.0 ? delta - 360.0 : delta;
}

/// زاوية الشمس عن الشمال الحقيقي (0..360) في اللحظة `utc`.
///
/// الطريقة: حساب الميل الشمسي ومعادلة الزمن من عناصر مدارية تقريبية للشمس،
/// ثم الزاوية الساعية من التوقيت الشمسي الحقيقي، وأخيراً التحويل إلى الإحداثيات
/// الأفقية. الدقة نحو ±0.1° لسنوات هذا القرن، وهي كافية لبديل الشمس (±1°).
///
/// [utc] يُحوَّل داخلياً إلى UTC، و[lat]/[lng] بالدرجات (شرق موجب).
double sunAzimuth({
  required double lat,
  required double lng,
  required DateTime utc,
}) {
  final instant = utc.toUtc();
  final days =
      instant.millisecondsSinceEpoch / Duration.millisecondsPerDay -
      _daysToJ2000;

  // العناصر المدارية المتوسطة للشمس (Meeus، دقة منخفضة).
  final meanLongitude = (280.460 + 0.9856474 * days) % 360.0;
  final meanAnomaly = (357.528 + 0.9856003 * days) * _radiansPerDegree;
  final eclipticLongitude =
      (meanLongitude +
          1.915 * math.sin(meanAnomaly) +
          0.020 * math.sin(2 * meanAnomaly)) *
      _radiansPerDegree;
  // ميل محور الأرض.
  final obliquity = (23.439 - 0.0000004 * days) * _radiansPerDegree;

  final sinDeclination = math.sin(obliquity) * math.sin(eclipticLongitude);
  final declination = math.asin(sinDeclination.clamp(-1.0, 1.0));
  final rightAscension = math.atan2(
    math.cos(obliquity) * math.sin(eclipticLongitude),
    math.cos(eclipticLongitude),
  );

  // معادلة الزمن بالدقائق: موجبة حين تسبق الشمسُ الحقيقيةُ المتوسطةَ
  // (الظهيرة الشمسية قبل الظهيرة المدنية).
  final equationOfTimeMinutes =
      _signedDegrees(meanLongitude - rightAscension * _degreesPerRadian) * 4.0;

  // التوقيت الشمسي الحقيقي = UTC + خط الطول + معادلة الزمن.
  final utcHours =
      instant.hour +
      instant.minute / 60.0 +
      instant.second / 3600.0 +
      instant.millisecond / 3600000.0;
  final hourAngleDegrees =
      (utcHours + lng / 15.0 + equationOfTimeMinutes / 60.0 - 12.0) * 15.0;
  final hourAngle = hourAngleDegrees * _radiansPerDegree;

  final phi = lat * _radiansPerDegree;
  final cosDeclination = math.cos(declination);
  // الصيغة القياسية للزاوية عن الجنوب، ثم نضيف 180 لنقيسها من الشمال.
  final azimuthFromSouth = math.atan2(
    cosDeclination * math.sin(hourAngle),
    cosDeclination * math.cos(hourAngle) * math.sin(phi) -
        sinDeclination * math.cos(phi),
  );

  return normalizeAngle(azimuthFromSouth * _degreesPerRadian + 180.0);
}

/// يطبع فرقاً بالدرجات إلى المدى −180..180.
double _signedDegrees(double degrees) {
  final wrapped = degrees % 360.0;
  return wrapped > 180.0 ? wrapped - 360.0 : wrapped;
}
