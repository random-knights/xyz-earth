// NOTE: the standalone viewer keeps only the time-WINDOW vocabulary used by the
// health-score history readout. The private app also hosted an
// `EarthLayerTimeSupport` matrix here that depended on the Earth source/Cesium
// catalog (`earth_source.dart` → `earth_visualization.dart`); that whole subtree
// is out of scope for the keyless globe and was dropped during extraction.

enum EarthTimeState {
  past,
  current,
  forecast,
  unknown,
}

final class EarthTimeWindow {
  const EarthTimeWindow({
    required this.id,
    required this.label,
    required this.state,
    required this.description,
  });

  factory EarthTimeWindow.fromJson(Map<String, dynamic> json) {
    return byId(json['id']?.toString() ?? '');
  }

  static const now = EarthTimeWindow(
    id: 'now',
    label: 'Now',
    state: EarthTimeState.current,
    description: 'Current-state Earth signals only.',
  );

  static const last24Hours = EarthTimeWindow(
    id: 'last-24-hours',
    label: 'Last 24 Hours',
    state: EarthTimeState.past,
    description: 'Recent daily summary where providers already expose it.',
  );

  static const last7Days = EarthTimeWindow(
    id: 'last-7-days',
    label: 'Last 7 Days',
    state: EarthTimeState.past,
    description: 'Short historical window for future supported layers.',
  );

  static const last30Days = EarthTimeWindow(
    id: 'last-30-days',
    label: 'Last 30 Days',
    state: EarthTimeState.past,
    description: 'Local 30-day history where already available.',
  );

  static const thisYear = EarthTimeWindow(
    id: 'this-year',
    label: 'This Year',
    state: EarthTimeState.past,
    description: 'Annual or dataset-release summary where available.',
  );

  static const forecast = EarthTimeWindow(
    id: 'forecast',
    label: 'Forecast / Future',
    state: EarthTimeState.forecast,
    description: 'Forecast or future window where a provider supports it.',
  );

  static const unknown = EarthTimeWindow(
    id: 'unknown',
    label: 'Unknown',
    state: EarthTimeState.unknown,
    description: 'Time window is not known for this signal.',
  );

  static const values = [
    now,
    last24Hours,
    last7Days,
    last30Days,
    thisYear,
    forecast,
  ];

  static EarthTimeWindow byId(String id) {
    for (final window in values) {
      if (window.id == id) return window;
    }
    return unknown;
  }

  final String id;
  final String label;
  final EarthTimeState state;
  final String description;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'state': state.name,
      'description': description,
    };
  }
}

/// Presentation helper: the collapsed earth+ card shows the active timeline as a
/// `MM/DD/YYYY h:mm AM/PM` stamp. `Now` resolves to the current instant; a chosen
/// (relative) window resolves to that window's representative instant relative to
/// now — e.g. Last 7 Days → seven days ago at the same time, This Year → Jan 1,
/// Forecast → a day ahead. Pure + injectable so it is deterministically testable.
abstract final class EarthTimelineStamp {
  /// The representative instant for [window] relative to [now].
  static DateTime instantFor(EarthTimeWindow window, DateTime now) {
    return switch (window.id) {
      'now' => now,
      'last-24-hours' => now.subtract(const Duration(hours: 24)),
      'last-7-days' => now.subtract(const Duration(days: 7)),
      'last-30-days' => now.subtract(const Duration(days: 30)),
      'this-year' => DateTime(now.year, 1, 1),
      'forecast' => now.add(const Duration(hours: 24)),
      _ => now,
    };
  }

  /// `MM/DD/YYYY h:mm AM/PM` for [window] relative to [now].
  static String format(EarthTimeWindow window, DateTime now) {
    final t = instantFor(window, now);
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final yyyy = t.year.toString().padLeft(4, '0');
    var h = t.hour % 12;
    if (h == 0) h = 12;
    final min = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$mm/$dd/$yyyy $h:$min $ap';
  }
}
