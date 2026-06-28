enum EarthWindStatus {
  planned,
  loading,
  available,
  error,
}

final class EarthWindModel {
  const EarthWindModel({
    required this.location,
    required this.speed,
    required this.directionDegrees,
    required this.source,
    required this.observedAt,
  });

  final String location;
  final double? speed;
  final int? directionDegrees;
  final String source;
  final DateTime observedAt;

  String get directionLabel {
    final degrees = directionDegrees;
    if (degrees == null) return 'n/a';

    const labels = [
      'N',
      'NE',
      'E',
      'SE',
      'S',
      'SW',
      'W',
      'NW',
    ];
    final normalized = degrees % 360;
    final index = ((normalized + 22.5) ~/ 45) % labels.length;

    return '${labels[index]} ($normalized deg)';
  }

  String get classification {
    final value = speed;
    if (value == null) return 'unknown';
    if (value < 1) return 'calm';
    if (value < 8) return 'light';
    if (value < 18) return 'breezy';
    if (value < 31) return 'windy';
    return 'strong';
  }

  String get freshness {
    final now = DateTime.now().toUtc();
    final age = now.difference(observedAt.toUtc());
    if (age.inMinutes < 1) return 'fresh';
    if (age.inMinutes < 60) return '${age.inMinutes}m old';
    return '${(age.inMinutes / 60).toStringAsFixed(1)}h old';
  }
}
