import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xyz_earth/theme/app_colors.dart';

/// SHARED Earth health-score ring widgets — defined ONCE here (Earth owns them,
/// §23) and imported by BOTH the Earth View and the Data View. Do not
/// re-implement these elsewhere.
///
/// - [EarthGlobalScoreRing] — a FULL progress ring for the GLOBAL Health Score
///   (always-global, region-independent).
/// - [EarthRegionalScoreHalfRing] — a radial HALF-ring for the REGIONAL Health
///   Score (a specific region; never the global aggregate).
///
/// Both render the score number, a band-coloured arc, a label, and an
/// estimation "i" affordance (tap → [onInfoTap], e.g. the managed estimation
/// explainer box). Colours come from the rk_branding tokens; the arc colour is
/// the health band so it reads honestly as the score moves.

/// The 5-stop health-score ramp — the SINGLE source of truth shared by the
/// Globe rings AND the Data View, so the same value reads the same colour in
/// BOTH views. red <35 · orange 35–50 · yellow 50–70 · green 70–90 · neon ≥90;
/// neutral grey when unknown (null). Thresholds MUST stay identical across
/// views (do not fork). Score hues are deliberately DISTINCT from the earth+
/// FILTER palette (peach/purple/pink/blue/kitt) — and score-red is its own red,
/// NEVER kitt, so a low score can never read as an active filter.
abstract final class EarthScoreColors {
  static const red = Color(0xFFDC3B2C); // <35 (dedicated red, NOT kitt #FF4124)
  static const orange = Color(0xFFF2862F); // 35–50
  static const yellow = Color(0xFFE6B73A); // 50–70
  static const green = Color(0xFF5BA45F); // 70–90
  static const neon = Color.fromRGBO(105, 219, 136, 1); // ≥90
  static const unknown = Color(0xFF878D97); // null — neutral grey
}

/// Health-band accent for a 0–100 score (shared by both rings AND the Data View
/// via [EarthScoreColors]). Accepts null → grey so one helper covers every call
/// site (the non-null double rings, the nullable composite score in the Data View).
Color earthScoreBandColor(num? score) {
  if (score == null) return EarthScoreColors.unknown;
  if (score >= 90) return EarthScoreColors.neon;
  if (score >= 70) return EarthScoreColors.green;
  if (score >= 50) return EarthScoreColors.yellow;
  if (score >= 35) return EarthScoreColors.orange;
  return EarthScoreColors.red;
}

/// Polish-3 (item 3) — fixed IDENTITY colors for the dual-radial chrome so the
/// Global (outer) and Regional (inner) arcs are ALWAYS distinguishable from each
/// other regardless of their health band: Global = periwinkle, Regional = sage.
/// The health-BAND reading (neon/gold/kitt) is carried by the Score Summary
/// breakdown, where both scores are now shown with their band color + status.
const Color earthGlobalScoreColor = AppColors.cardPurp;
const Color earthRegionalScoreColor = AppColors.green;

/// The full progress ring — GLOBAL Health Score.
class EarthGlobalScoreRing extends StatelessWidget {
  const EarthGlobalScoreRing({
    super.key,
    required this.score,
    required this.label,
    this.onInfoTap,
    this.isLive = false,
    this.size = 116,
  });

  final double score;
  final String label;
  final VoidCallback? onInfoTap;
  final bool isLive;
  final double size;

  @override
  Widget build(BuildContext context) {
    final band = earthScoreBandColor(score);
    return Column(
      key: const Key('earth-global-score-ring'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: size,
          width: size,
          child: CustomPaint(
            painter: _EarthFullRingPainter(
              fraction: score.clamp(0, 100) / 100,
              color: band,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    score.toStringAsFixed(1),
                    key: const Key('earth-global-score-value'),
                    style: TextStyle(
                      color: band,
                      fontSize: size * 0.3,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                  Text('/ 100',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: math.max(8.0, size * 0.092),
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _EarthScoreLabel(
          label: label,
          onInfoTap: onInfoTap,
          isLive: isLive,
          infoKey: const Key('earth-global-score-info'),
        ),
      ],
    );
  }
}

/// The radial half-ring — REGIONAL Health Score.
class EarthRegionalScoreHalfRing extends StatelessWidget {
  const EarthRegionalScoreHalfRing({
    super.key,
    required this.score,
    required this.label,
    this.onInfoTap,
    this.isLive = false,
    this.width = 132,
  });

  final double score;
  final String label;
  final VoidCallback? onInfoTap;
  final bool isLive;
  final double width;

  @override
  Widget build(BuildContext context) {
    final band = earthScoreBandColor(score);
    // A half-ring occupies ~half its width in height plus room for the value.
    final h = width * 0.6;
    return Column(
      key: const Key('earth-regional-score-half-ring'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: width,
          height: h,
          child: CustomPaint(
            painter: _EarthHalfRingPainter(
              fraction: score.clamp(0, 100) / 100,
              color: band,
            ),
            child: Padding(
              padding: EdgeInsets.only(top: h * 0.36),
              child: Center(
                child: Text(
                  '${score.toStringAsFixed(1)}%',
                  key: const Key('earth-regional-score-value'),
                  style: TextStyle(
                    color: band,
                    fontSize: width * 0.2,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _EarthScoreLabel(
          label: label,
          onInfoTap: onInfoTap,
          isLive: isLive,
          infoKey: const Key('earth-regional-score-info'),
        ),
      ],
    );
  }
}

/// Fallback A dual-radial (polish-2): ONE fixed box TOP-RIGHT, Global on the
/// outer arc and Regional on the inner arc (nested 2-stripe). Added ADDITIVELY
/// (§23) — Data View continues using [EarthGlobalScoreRing] and
/// [EarthRegionalScoreHalfRing] unchanged.
class EarthDualRadialScoreWidget extends StatelessWidget {
  const EarthDualRadialScoreWidget({
    super.key,
    required this.globalScore,
    required this.globalLabel,
    required this.regionalScore,
    required this.regionalLabel,
    this.globalIsLive = false,
    this.regionalIsLive = false,
    this.onGlobalInfoTap,
    this.onRegionalInfoTap,
    this.size = 128,
  });

  final double globalScore;
  final String globalLabel;
  final double regionalScore;
  final String regionalLabel;
  final bool globalIsLive;
  final bool regionalIsLive;
  final VoidCallback? onGlobalInfoTap;
  final VoidCallback? onRegionalInfoTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    // LOCKDOWN (#5): the two GLOBE RINGS now read the 4-stop health-band ramp
    // ([earthScoreBandColor]) — the SAME colour the Data View bars + the gauge
    // value use — so a ring and its bar match at the same value (was the fixed
    // periwinkle/sage identity colours). Global vs Regional stays obvious from
    // the outer/inner position, the G/R centre tags, and the labels.
    final gBand = earthScoreBandColor(globalScore);
    final rBand = earthScoreBandColor(regionalScore);
    return Column(
      key: const Key('earth-dual-radial-score'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _EarthDualRingPainter(
              outerFraction: globalScore.clamp(0, 100) / 100,
              outerColor: gBand,
              innerFraction: regionalScore.clamp(0, 100) / 100,
              innerColor: rBand,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _EarthDualCenterValue(
                    valueKey: const Key('earth-dual-global-score-value'),
                    tag: 'G',
                    score: globalScore,
                    color: gBand,
                    // Polish-4 (item 1): smaller so tag + number fit inside the
                    // inner radial arc (no overflow past the ring).
                    fontSize: size * 0.16,
                  ),
                  SizedBox(height: size * 0.015),
                  _EarthDualCenterValue(
                    valueKey: const Key('earth-dual-regional-score-value'),
                    tag: 'R',
                    score: regionalScore,
                    color: rBand,
                    fontSize: size * 0.125,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _EarthDualScoreLabel(
          label: globalLabel,
          accentColor: gBand,
          onInfoTap: onGlobalInfoTap,
          infoKey: const Key('earth-dual-global-score-info'),
        ),
        const SizedBox(height: 2),
        _EarthDualScoreLabel(
          label: regionalLabel,
          accentColor: rBand,
          onInfoTap: onRegionalInfoTap,
          infoKey: const Key('earth-dual-regional-score-info'),
        ),
      ],
    );
  }
}

/// Centre value for the dual-radial score: a small colour-keyed tag (G / R) +
/// the score, so the stacked numbers can't be confused for one another.
class _EarthDualCenterValue extends StatelessWidget {
  const _EarthDualCenterValue({
    required this.valueKey,
    required this.tag,
    required this.score,
    required this.color,
    required this.fontSize,
  });

  final Key valueKey;
  final String tag;
  final double score;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          tag,
          style: TextStyle(
            color: color.withValues(alpha: 0.85),
            fontSize: fontSize * 0.6,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(width: fontSize * 0.18),
        Text(
          score.toStringAsFixed(1),
          key: valueKey,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

class _EarthDualScoreLabel extends StatelessWidget {
  const _EarthDualScoreLabel({
    required this.label,
    required this.accentColor,
    required this.onInfoTap,
    required this.infoKey,
  });

  final String label;
  final Color accentColor;
  final VoidCallback? onInfoTap;
  final Key infoKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textLight,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 3),
        InkWell(
          key: infoKey,
          onTap: onInfoTap,
          borderRadius: BorderRadius.circular(999),
          child: const Padding(
            padding: EdgeInsets.all(2),
            child: Icon(Icons.info_outline, size: 11, color: Colors.white54),
          ),
        ),
      ],
    );
  }
}

class _EarthDualRingPainter extends CustomPainter {
  _EarthDualRingPainter({
    required this.outerFraction,
    required this.outerColor,
    required this.innerFraction,
    required this.innerColor,
  });

  final double outerFraction;
  final Color outerColor;
  final double innerFraction;
  final Color innerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final short = size.shortestSide;
    final stroke = short * 0.09;
    final outerRadius = short / 2 - stroke / 2 - 2;
    final innerRadius = outerRadius - stroke * 1.9;
    final trackColor = Colors.white.withValues(alpha: 0.12);

    void ring(double radius, double fraction, Color color) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect, 0, 2 * math.pi, false,
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawArc(
        rect, -math.pi / 2, 2 * math.pi * fraction.clamp(0, 1), false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    ring(outerRadius, outerFraction, outerColor);
    ring(innerRadius, innerFraction, innerColor);
  }

  @override
  bool shouldRepaint(covariant _EarthDualRingPainter old) =>
      old.outerFraction != outerFraction ||
      old.outerColor != outerColor ||
      old.innerFraction != innerFraction ||
      old.innerColor != innerColor;
}

/// Shared label row: "<label>" + estimation "i" + optional live/representative.
class _EarthScoreLabel extends StatelessWidget {
  const _EarthScoreLabel({
    required this.label,
    required this.onInfoTap,
    required this.isLive,
    required this.infoKey,
  });

  final String label;
  final VoidCallback? onInfoTap;
  final bool isLive;
  final Key infoKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textLight,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 1),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'estimation',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              key: infoKey,
              onTap: onInfoTap,
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.info_outline, size: 12, color: Colors.white54),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EarthFullRingPainter extends CustomPainter {
  _EarthFullRingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.1;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2 + 2);
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    // Full 360° track; progress sweeps clockwise from the top (−90°).
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, track);
    canvas.drawArc(arcRect, -math.pi / 2, 2 * math.pi * fraction.clamp(0, 1),
        false, progress);
  }

  @override
  bool shouldRepaint(covariant _EarthFullRingPainter old) =>
      old.fraction != fraction || old.color != color;
}

class _EarthHalfRingPainter extends CustomPainter {
  _EarthHalfRingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.1;
    // Top semicircle: centre on the bottom edge, arc from π (left) to 2π (right).
    final center = Offset(size.width / 2, size.height - stroke);
    final radius = size.width / 2 - stroke / 2 - 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, math.pi, math.pi, false, track);
    canvas.drawArc(
        arcRect, math.pi, math.pi * fraction.clamp(0, 1), false, progress);
  }

  @override
  bool shouldRepaint(covariant _EarthHalfRingPainter old) =>
      old.fraction != fraction || old.color != color;
}
