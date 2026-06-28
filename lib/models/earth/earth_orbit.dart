import 'dart:math' as math;

/// AMBIENT, educational orbit model (mobility lane — Space mode). Parses a
/// two-line element set (TLE) and propagates it with a SIMPLIFIED Keplerian
/// model + J2 secular drift (the dominant perturbation) to the sub-satellite
/// geodetic point (lat/lon) and altitude.
///
/// This is DELIBERATELY approximate — it shows orbit-band footprints and roughly
/// where named satellites are, NOT precise per-object tracking (governance:
/// non-trackable, ambient). It is not full SGP4; positions drift over weeks as
/// the bundled elements age. Pure Dart so it unit-tests against analytic values.

/// Gravitational parameter of Earth (km³/s²).
const double _kMu = 398600.4418;

/// Earth equatorial radius (km, WGS-84).
const double _kEarthRadiusKm = 6378.137;

/// Second zonal harmonic (J2) — drives the dominant secular nodal/apsidal drift.
const double _kJ2 = 0.00108262998905;

const double _deg2rad = math.pi / 180.0;
const double _rad2deg = 180.0 / math.pi;
const double _twoPi = 2 * math.pi;

/// A parsed two-line element set (mean orbital elements at [epoch]).
class EarthTle {
  const EarthTle({
    required this.name,
    required this.catalogNumber,
    required this.epoch,
    required this.inclinationDeg,
    required this.raanDeg,
    required this.eccentricity,
    required this.argPerigeeDeg,
    required this.meanAnomalyDeg,
    required this.meanMotionRevPerDay,
  });

  final String name;
  final int catalogNumber;

  /// UTC instant the mean elements are valid at.
  final DateTime epoch;

  final double inclinationDeg;
  final double raanDeg;
  final double eccentricity;
  final double argPerigeeDeg;
  final double meanAnomalyDeg;
  final double meanMotionRevPerDay;

  /// Mean motion in rad/s.
  double get meanMotionRadPerSec => meanMotionRevPerDay * _twoPi / 86400.0;

  /// Semi-major axis (km) from Kepler's third law (a = (µ / n²)^(1/3)).
  double get semiMajorAxisKm =>
      math.pow(_kMu / (meanMotionRadPerSec * meanMotionRadPerSec), 1 / 3)
          .toDouble();

  /// Orbital period (minutes).
  double get periodMinutes => _twoPi / meanMotionRadPerSec / 60.0;

  /// Parse the standard fixed-column TLE (a name line + the two element lines).
  /// Throws [FormatException] on a malformed set.
  factory EarthTle.parse(String name, String line1, String line2) {
    if (line1.length < 64 || line2.length < 63) {
      throw const FormatException('TLE lines too short');
    }
    double col(String l, int start, int end) =>
        double.parse(l.substring(start, end).trim());
    // Line 1: epoch year (cols 19-20) + fractional day-of-year (cols 21-32).
    final yy = int.parse(line1.substring(18, 20).trim());
    final year = yy < 57 ? 2000 + yy : 1900 + yy;
    final dayOfYear = double.parse(line1.substring(20, 32).trim());
    // dayOfYear is 1.0 at Jan 1 00:00 UTC.
    final epoch = DateTime.utc(year, 1, 1).add(
      Duration(milliseconds: ((dayOfYear - 1.0) * 86400000.0).round()),
    );
    return EarthTle(
      name: name.trim(),
      catalogNumber: int.parse(line2.substring(2, 7).trim()),
      epoch: epoch,
      inclinationDeg: col(line2, 8, 16),
      raanDeg: col(line2, 17, 25),
      eccentricity: double.parse('0.${line2.substring(26, 33).trim()}'),
      argPerigeeDeg: col(line2, 34, 42),
      meanAnomalyDeg: col(line2, 43, 51),
      meanMotionRevPerDay: col(line2, 52, 63),
    );
  }
}

/// A propagated sub-satellite point (the geodetic point directly below the
/// satellite) + its altitude.
class EarthSatellitePosition {
  const EarthSatellitePosition({
    required this.latDeg,
    required this.lonDeg,
    required this.altitudeKm,
  });

  final double latDeg;
  final double lonDeg;
  final double altitudeKm;
}

abstract final class EarthOrbitPropagator {
  /// Solve Kepler's equation M = E − e·sinE for the eccentric anomaly E (rad).
  static double solveKepler(double meanAnomaly, double e) {
    var m = meanAnomaly % _twoPi;
    if (m < 0) m += _twoPi;
    final ecc = e < 0 ? 0.0 : (e > 0.999 ? 0.999 : e);
    var eAnom = ecc < 0.8 ? m : math.pi;
    for (var i = 0; i < 30; i++) {
      final dE =
          (eAnom - ecc * math.sin(eAnom) - m) / (1 - ecc * math.cos(eAnom));
      eAnom -= dE;
      if (dE.abs() < 1e-10) break;
    }
    return eAnom;
  }

  /// Greenwich Mean Sidereal Time (radians) at UTC instant [t].
  static double gmstRad(DateTime t) {
    final jd = 2440587.5 + t.toUtc().millisecondsSinceEpoch / 86400000.0;
    final d = jd - 2451545.0; // days since J2000.0
    final tc = d / 36525.0; // Julian centuries
    var deg = 280.46061837 +
        360.98564736629 * d +
        0.000387933 * tc * tc -
        tc * tc * tc / 38710000.0;
    deg %= 360.0;
    if (deg < 0) deg += 360.0;
    return deg * _deg2rad;
  }

  /// Propagate [tle] to UTC instant [t] → sub-satellite geodetic point.
  static EarthSatellitePosition propagate(EarthTle tle, DateTime t) {
    final n0 = tle.meanMotionRadPerSec; // rad/s
    final a = tle.semiMajorAxisKm;
    final e = tle.eccentricity;
    final inc = tle.inclinationDeg * _deg2rad;
    final dt = t.toUtc().difference(tle.epoch).inMilliseconds / 1000.0; // s

    // J2 secular drift of the node (RAAN) and argument of perigee (rad/s).
    final p = a * (1 - e * e);
    final f = 1.5 * _kJ2 * (_kEarthRadiusKm / p) * (_kEarthRadiusKm / p) * n0;
    final raan = tle.raanDeg * _deg2rad - f * math.cos(inc) * dt;
    final argp = tle.argPerigeeDeg * _deg2rad + f * (2 - 2.5 * _sin2(inc)) * dt;

    final m = tle.meanAnomalyDeg * _deg2rad + n0 * dt;
    final eAnom = solveKepler(m, e);
    final nu = math.atan2(
      math.sqrt(1 - e * e) * math.sin(eAnom),
      math.cos(eAnom) - e,
    );
    final r = a * (1 - e * math.cos(eAnom));

    // Perifocal → ECI (Rz(raan)·Rx(inc)·Rz(argp)).
    final xp = r * math.cos(nu);
    final yp = r * math.sin(nu);
    final cosO = math.cos(raan), sinO = math.sin(raan);
    final cosi = math.cos(inc), sini = math.sin(inc);
    final cosw = math.cos(argp), sinw = math.sin(argp);
    final x = xp * (cosO * cosw - sinO * sinw * cosi) -
        yp * (cosO * sinw + sinO * cosw * cosi);
    final y = xp * (sinO * cosw + cosO * sinw * cosi) -
        yp * (sinO * sinw - cosO * cosw * cosi);
    final z = xp * (sinw * sini) + yp * (cosw * sini);

    // ECI → ECEF by GMST, then geocentric sub-satellite lat/lon (adequate for
    // an ambient display) + altitude above the spherical Earth.
    final gmst = gmstRad(t);
    final xe = x * math.cos(gmst) + y * math.sin(gmst);
    final ye = -x * math.sin(gmst) + y * math.cos(gmst);
    final ze = z;
    var lon = math.atan2(ye, xe) * _rad2deg;
    lon = ((lon + 180) % 360 + 360) % 360 - 180; // normalise to [-180,180)
    final lat = math.atan2(ze, math.sqrt(xe * xe + ye * ye)) * _rad2deg;
    final altKm = math.sqrt(x * x + y * y + z * z) - _kEarthRadiusKm;
    return EarthSatellitePosition(latDeg: lat, lonDeg: lon, altitudeKm: altKm);
  }

  static double _sin2(double a) => math.sin(a) * math.sin(a);
}

/// Orbit altitude bands for the ambient ring display.
enum EarthOrbitBand { leo, meo, geo }

extension EarthOrbitBandLabel on EarthOrbitBand {
  String get id => switch (this) {
        EarthOrbitBand.leo => 'leo',
        EarthOrbitBand.meo => 'meo',
        EarthOrbitBand.geo => 'geo',
      };
  String get label => switch (this) {
        EarthOrbitBand.leo => 'LEO',
        EarthOrbitBand.meo => 'MEO',
        EarthOrbitBand.geo => 'GEO',
      };

  static EarthOrbitBand fromId(String id) => switch (id) {
        'meo' => EarthOrbitBand.meo,
        'geo' => EarthOrbitBand.geo,
        _ => EarthOrbitBand.leo,
      };
}
