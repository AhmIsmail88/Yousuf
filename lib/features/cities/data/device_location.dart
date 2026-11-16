import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../prayer/domain/prayer_times_models.dart';
import 'cities_repository.dart';

/// سبب تعذر تحديد الموقع.
enum LocateFailure { denied, unavailable }

/// نتيجة تحديد موقع الجهاز.
class LocateResult {
  const LocateResult._({this.location, this.city, this.failure});

  const LocateResult.success(PrayerLocation location, City city)
    : this._(location: location, city: city);

  const LocateResult.failed(LocateFailure failure) : this._(failure: failure);

  final PrayerLocation? location;
  final City? city;
  final LocateFailure? failure;

  bool get ok => location != null;
}

/// يحدّد موقع الجهاز (بإذن المستخدم) ويعيد إحداثياته الفعلية مع أقرب مدينة
/// (للاسم والمنطقة الزمنية). الموقع لا يغادر الجهاز (SPEC §10).
Future<LocateResult> locateDevice(Ref ref) =>
    _locate(() => ref.read(citiesRepositoryProvider.future));

/// نسخة للواجهات (WidgetRef).
Future<LocateResult> locateDeviceFromWidget(WidgetRef ref) =>
    _locate(() => ref.read(citiesRepositoryProvider.future));

Future<LocateResult> _locate(Future<CitiesRepository> Function() cities) async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const LocateResult.failed(LocateFailure.denied);
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 25),
      ),
    );
    final repository = await cities();
    final city = repository.nearest(position.latitude, position.longitude);
    return LocateResult.success(
      city.atCoordinates(position.latitude, position.longitude),
      city,
    );
  } catch (_) {
    return const LocateResult.failed(LocateFailure.unavailable);
  }
}
