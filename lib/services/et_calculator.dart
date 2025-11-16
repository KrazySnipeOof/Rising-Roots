import 'dart:math';
import 'package:intl/intl.dart';

/// FAO-56 Penman–Monteith reference ET0 calculator.
///
/// All units follow FAO-56 conventions:
/// - Temperature: °C
/// - Wind speed: m/s at 2 m
/// - Relative humidity: %
/// - Solar radiation: MJ/m²/day
/// - Altitude: m above sea level
/// - Latitude: decimal degrees
/// - Result: mm/day
class EtCalculator {
  const EtCalculator._();

  static double computeETo({
    required DateTime date,
    required double tMinC,
    required double tMaxC,
    required double rhMean,
    required double windSpeedMs,
    required double solarRadMjM2,
    required double latitudeDeg,
    double altitudeM = 200,
  }) {
    final tMean = (tMinC + tMaxC) / 2.0;
    final latRad = latitudeDeg * pi / 180.0;

    final delta = _slopeSaturationVapourPressureCurve(tMean);
    final p = _atmosphericPressure(altitudeM);
    final gamma = 0.000665 * p;

    final es = (_saturationVapourPressure(tMaxC) + _saturationVapourPressure(tMinC)) / 2.0;
    final ea = es * rhMean.clamp(0, 100) / 100.0;

    final j = int.parse(DateFormat('D').format(date));
    final ra = _extraterrestrialRadiation(latRad, j);
    final rso = _clearSkyRadiation(ra, altitudeM);
    final rs = solarRadMjM2;
    final rns = 0.77 * rs; // (1 - albedo) * Rs, albedo ≈ 0.23
    final rnl = _netLongWaveRadiation(tMinC, tMaxC, rs, rso, ea);
    final rn = rns - rnl;

    final u2 = windSpeedMs;
    final etoNumerator = 0.408 * delta * rn + gamma * (900 / (tMean + 273)) * u2 * (es - ea);
    final etoDenominator = delta + gamma * (1 + 0.34 * u2);

    if (etoDenominator == 0) return 0;
    final eto = etoNumerator / etoDenominator;
    if (eto.isNaN || !eto.isFinite) return 0;
    return eto.clamp(0, 20); // sanity bounds
  }

  static double _saturationVapourPressure(double tempC) {
    return 0.6108 * exp((17.27 * tempC) / (tempC + 237.3));
  }

  static double _slopeSaturationVapourPressureCurve(double tempC) {
    final es = _saturationVapourPressure(tempC);
    return 4098 * es / pow(tempC + 237.3, 2);
  }

  static double _atmosphericPressure(double altitudeM) {
    return 101.3 * pow((293 - 0.0065 * altitudeM) / 293, 5.26);
  }

  static double _extraterrestrialRadiation(double latRad, int j) {
    final dr = 1 + 0.033 * cos(2 * pi / 365 * j);
    final delta = 0.409 * sin(2 * pi / 365 * j - 1.39);
    final omegaS = acos(-tan(latRad) * tan(delta));
    const gsc = 0.0820; // MJ m-2 min-1
    return (24 * 60 / pi) * gsc * dr * (omegaS * sin(latRad) * sin(delta) + cos(latRad) * cos(delta) * sin(omegaS));
  }

  static double _clearSkyRadiation(double ra, double altitudeM) {
    return (0.75 + 2e-5 * altitudeM) * ra;
  }

  static double _netLongWaveRadiation(
    double tMinC,
    double tMaxC,
    double rs,
    double rso,
    double ea,
  ) {
    const sigma = 4.903e-9; // MJ K-4 m-2 day-1
    final tMinK = tMinC + 273.16;
    final tMaxK = tMaxC + 273.16;
    final term1 = (pow(tMaxK, 4) + pow(tMinK, 4)) / 2.0;
    final term2 = 0.34 - 0.14 * sqrt(ea);
    final term3 = 1.35 * (rs / (rso == 0 ? rs : rso)).clamp(0.3, 1.0) - 0.35;
    return sigma * term1 * term2 * term3;
  }
}


