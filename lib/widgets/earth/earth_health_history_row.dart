import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:xyz_earth/models/earth/earth_health_history.dart';
import 'package:xyz_earth/services/earth/earth_health_history_source.dart';
import 'package:xyz_earth/widgets/earth/earth_score_rings.dart'
    show EarthScoreColors, earthScoreBandColor;
import 'package:xyz_earth/theme/app_colors.dart';

/// Expandable "Health history" row — the daily Earth Health Score over time.
///
/// COLLAPSED: the current global score, today's delta, and the tracking-start
/// date. EXPANDED: 1/7/30-day delta cards, domain-switch chips, and a line chart
/// drawn over the 4-stop score BANDS (reusing [earthScoreBandColor] so the chart
/// reads in the same red/orange/yellow/green language as the gauge). Early on
/// (<2 days) the deltas are dashed and the header reads "tracking started …".
///
/// Self-loading: pass [history] to inject (tests / a host that already has it),
/// otherwise it reads the live `earth/score/health-history.json` via [source].
/// [compact] is the narrow Earth-View / mobile layout (shorter chart, tighter
/// type); the Data View uses the roomier default.
class EarthHealthHistoryRow extends StatefulWidget {
  const EarthHealthHistoryRow({
    super.key,
    this.history,
    this.source,
    this.compact = false,
  });

  final EarthHealthHistory? history;
  final EarthHealthHistorySource? source;
  final bool compact;

  @override
  State<EarthHealthHistoryRow> createState() => _EarthHealthHistoryRowState();

  /// Domain id → display label for the switch chips (matches the score summary).
  static const domainLabels = <String, String>{
    'air': 'Air Quality',
    'land-cover': 'Forest',
    'ocean': 'Ocean',
    'ocean-acidification': 'Acidification',
    'fire': 'Wildfire',
    'wildfire': 'Wildfire',
    'cryosphere': 'Glaciers',
    'biodiversity': 'Biodiversity',
    // The score doc's protected-area domain ships under the id 'conservation'.
    'conservation': 'Protected',
    'protected-areas': 'Protected',
    'human': 'Human',
  };
}

class _EarthHealthHistoryRowState extends State<EarthHealthHistoryRow> {
  EarthHealthHistory _history = EarthHealthHistory.empty;
  bool _loading = false;
  String _selectedKey = EarthHealthHistory.globalKey;

  @override
  void initState() {
    super.initState();
    final injected = widget.history;
    if (injected != null) {
      _history = injected;
    } else {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final source = widget.source ?? const LiveStorageHealthHistorySource();
    final doc = await source.load();
    if (!mounted) return;
    setState(() {
      _history = doc;
      _loading = false;
    });
  }

  static String _fmtDate(String? ymd) {
    final m = ymd == null
        ? null
        : RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ymd);
    if (m == null) return '—';
    return '${m.group(2)}/${m.group(3)}/${m.group(1)}'; // MM/DD/YYYY
  }

  static String _fmtDelta(double? v) {
    if (v == null) return '—';
    final r = (v.abs() * 10).round() / 10;
    return '${v >= 0 ? '+' : '−'}${r.toStringAsFixed(1)}';
  }

  Color _deltaColor(double? v) =>
      v == null ? Colors.white38 : (v < 0 ? EarthScoreColors.red : EarthScoreColors.green);

  /// Chip keys: Global first, then each domain present in the data (labelled).
  List<({String key, String label})> get _chips => [
        (key: EarthHealthHistory.globalKey, label: 'Global'),
        for (final id in _history.domainIds)
          if (EarthHealthHistoryRow.domainLabels[id] != null)
            (key: id, label: EarthHealthHistoryRow.domainLabels[id]!),
      ];

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final h = _history;
    final latest = h.latest;
    final hasData = latest != null;
    final early = h.dayCount < 2;

    final titleSize = compact ? 13.5 : 14.0;
    final scoreSize = compact ? 19.0 : 21.0;

    final subtitle = !hasData
        ? 'tracking started ${_fmtDate(h.startedOn)}'
        : early
            ? 'tracking started ${_fmtDate(h.startedOn)} · ${h.dayCount} day${h.dayCount == 1 ? '' : 's'}'
            : 'since ${_fmtDate(h.startedOn)}';

    return Container(
      key: const ValueKey('earth-health-history-row'),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(
            hasData: hasData,
            latest: latest,
            subtitle: subtitle,
            titleSize: titleSize,
            scoreSize: scoreSize,
            compact: compact,
          ),
          // ALWAYS EXPANDED — no collapse affordance; the full chart + deltas +
          // chips always render below the header.
          Padding(
            padding: EdgeInsets.fromLTRB(
                compact ? 12 : 14, 4, compact ? 12 : 14, compact ? 12 : 14),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.kitt),
                        ),
                      ),
                    ),
                  )
                : _buildBody(compact: compact, early: early),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({
    required bool hasData,
    required EarthHealthHistoryPoint? latest,
    required String subtitle,
    required double titleSize,
    required double scoreSize,
    required bool compact,
  }) {
    final todayDelta = _history.todayDelta(_selectedKey);
    final displayScore = hasData
        ? (latest!.valueFor(_selectedKey) ?? latest.global).round()
        : null;
    // Static header (no collapse toggle) — the body is always shown.
    return Padding(
      key: const ValueKey('earth-health-history-header'),
      padding:
          EdgeInsets.fromLTRB(compact ? 12 : 14, 11, compact ? 12 : 14, 11),
      child: Row(
          children: [
            const Icon(Icons.timeline, color: EarthScoreColors.green, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Health history',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: displayScore != null ? '$displayScore' : '—',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: scoreSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const TextSpan(
                        text: '/100',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (!compact)
                  Text(
                    '${_fmtDelta(todayDelta)} today',
                    style: TextStyle(color: _deltaColor(todayDelta), fontSize: 11),
                  ),
              ],
            ),
          ],
        ),
      );
  }

  Widget _buildBody({required bool compact, required bool early}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _deltaCard('1-day', _history.delta(_selectedKey, 1), compact),
            const SizedBox(width: compactGap),
            _deltaCard('7-day', _history.delta(_selectedKey, 7), compact),
            const SizedBox(width: compactGap),
            _deltaCard('30-day', _history.delta(_selectedKey, 30), compact),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in _chips)
              _chip(c.key, c.label),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: compact ? 168 : 224,
          child: _buildChart(),
        ),
        const SizedBox(height: 10),
        Text(
          'methodology v${_history.methodologyVersion.isEmpty ? '0.6' : _history.methodologyVersion} · '
          'daily 06:10 UTC · bands red <35 · orange 35–50 · yellow 50–70 · green 70–90 · neon ≥90',
          style: const TextStyle(color: Colors.white38, fontSize: 10.5, height: 1.4),
        ),
      ],
    );
  }

  static const double compactGap = 8;

  Widget _deltaCard(String label, double? value, bool compact) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              _fmtDelta(value),
              style: TextStyle(
                color: _deltaColor(value),
                fontSize: compact ? 16 : 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String key, String label) {
    final on = _selectedKey == key;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _selectedKey = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: on ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: on ? Colors.white54 : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: on ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildChart() {
    final series = _history.series(_selectedKey);
    if (series.isEmpty) {
      return const Center(
        child: Text('No data yet', style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }
    final spots = <FlSpot>[
      for (var i = 0; i < series.length; i++) FlSpot(i.toDouble(), series[i].value),
    ];
    // 5-stop score bands behind the line (reuse the gauge's band colours).
    List<HorizontalRangeAnnotation> bands() => [
          for (final b in const [[0.0, 35.0], [35.0, 50.0], [50.0, 70.0], [70.0, 90.0], [90.0, 100.0]])
            HorizontalRangeAnnotation(
              y1: b[0],
              y2: b[1],
              color: earthScoreBandColor((b[0] + b[1]) / 2).withValues(alpha: 0.13),
            ),
        ];
    final maxX = (series.length - 1).toDouble();
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX <= 0 ? 1 : maxX,
        minY: 0,
        maxY: 100,
        rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: bands()),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: Colors.white.withValues(alpha: 0.06), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 25,
              reservedSize: 28,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: Colors.white.withValues(alpha: 0.88),
            barWidth: 2,
            dotData: FlDotData(show: spots.length == 1),
          ),
        ],
      ),
    );
  }
}
