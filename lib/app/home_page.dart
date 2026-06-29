import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:xyz_earth/models/earth/earth_live_health_score.dart';
import 'package:xyz_earth/services/earth/earth_live_health_score_source.dart';
import 'package:xyz_earth/theme/app_colors.dart';
import 'package:xyz_earth/widgets/earth/earth_health_history_row.dart';
import 'package:xyz_earth/widgets/earth/earth_score_rings.dart';
import 'package:xyz_earth/widgets/earth2d/earth2d_globe_view.dart';

/// One selectable layer in a slot (label + the renderer id, or null for "Off").
typedef _Layer = ({String label, String? id});

/// Home stage: the keyless living globe with a layer-toggle bar, the Planet
/// Health Score ring, and an expandable health-history panel.
///
/// Everything renders offline from bundled representatives; where a public live
/// object exists, the extracted sources fetch it over plain HTTPS and upgrade in
/// place (see the live*/representative pattern in services/earth/*).
class EarthHomePage extends StatefulWidget {
  const EarthHomePage({super.key});

  @override
  State<EarthHomePage> createState() => _EarthHomePageState();
}

class _EarthHomePageState extends State<EarthHomePage> {
  // Curated layer catalog (ids match the resolver's slot maps). Kept lean so the
  // open viewer is approachable; every id below is wired in Earth2dGlobeView.
  static const _flowLayers = <_Layer>[
    (label: 'Off', id: null),
    (label: 'Wind', id: 'wind'),
    (label: 'Ocean currents', id: 'ocean-currents'),
    (label: 'Waves', id: 'waves'),
  ];

  static const _overlayLayers = <_Layer>[
    (label: 'Off', id: null),
    (label: 'Air quality', id: 'air-quality'),
    (label: 'Particulates', id: 'particulates'),
    (label: 'Sea-surface temp', id: 'sst'),
    (label: 'SST anomaly', id: 'ssta'),
    (label: 'Forest', id: 'forest'),
    (label: 'Human modification', id: 'human-modification'),
    (label: 'Protected areas', id: 'protected-areas'),
    (label: 'Carbon', id: 'carbon'),
  ];

  static const _pointLayers = <_Layer>[
    (label: 'Off', id: null),
    (label: 'Wildfires', id: 'wildfires'),
    (label: 'Biodiversity', id: 'biodiversity-habitat'),
    (label: 'Glaciers', id: 'glaciers'),
    (label: 'Power plants', id: 'power-plants'),
    (label: 'Flights', id: 'flights'),
    (label: 'Boats', id: 'boats'),
  ];

  String? _animateId = 'wind';
  String? _overlayId = 'sst';
  String? _annotationId = 'wildfires';
  bool _hd = false;
  bool _spin = true;
  bool _showHistory = false;

  EarthLiveHealthScore? _score;
  bool _scoreLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScore();
  }

  Future<void> _loadScore() async {
    // Public live score → bundled representative fallback (keyless).
    final doc = await const LiveStorageHealthScoreSource().load();
    if (!mounted) return;
    setState(() {
      _score = doc;
      _scoreLoading = false;
    });
  }

  bool get _historyOpen => _showHistory;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final narrow = media.size.width < 720;
    return Scaffold(
      body: Stack(
        children: [
          // The living globe fills the stage. Any open overlay box freezes the
          // globe's camera input (overlayOpen) so scrolling a panel can't spin it.
          Positioned.fill(
            child: Earth2dGlobeView(
              animateLayerId: _animateId,
              overlayLayerId: _overlayId,
              annotationLayerId: _annotationId,
              hd: _hd,
              spin: _spin,
              reducedMotion: media.disableAnimations,
              overlayOpen: _historyOpen,
            ),
          ),
          if (!kIsWeb) const _NonWebNotice(),
          // Title + score, top-left.
          Positioned(
            top: media.padding.top + 12,
            left: 16,
            child: _ScorePanel(loading: _scoreLoading, score: _score),
          ),
          // Layer + motion controls, bottom.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ControlBar(
              narrow: narrow,
              flowLayers: _flowLayers,
              overlayLayers: _overlayLayers,
              pointLayers: _pointLayers,
              animateId: _animateId,
              overlayId: _overlayId,
              annotationId: _annotationId,
              hd: _hd,
              spin: _spin,
              showHistory: _showHistory,
              onAnimate: (v) => setState(() => _animateId = v),
              onOverlay: (v) => setState(() => _overlayId = v),
              onAnnotation: (v) => setState(() => _annotationId = v),
              onHd: (v) => setState(() => _hd = v),
              onSpin: (v) => setState(() => _spin = v),
              onToggleHistory: () =>
                  setState(() => _showHistory = !_showHistory),
            ),
          ),
          // Health-history panel (slides in from the right when toggled).
          if (_showHistory)
            Positioned(
              top: media.padding.top + 12,
              right: 12,
              bottom: 120,
              width: narrow ? media.size.width - 24 : 380,
              child: _HistoryPanel(
                onClose: () => setState(() => _showHistory = false),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScorePanel extends StatelessWidget {
  const _ScorePanel({required this.loading, required this.score});

  final bool loading;
  final EarthLiveHealthScore? score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Planet Health Score',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          if (loading)
            const SizedBox(
              height: 116,
              width: 116,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.kitt),
                ),
              ),
            )
          else if (score != null)
            EarthGlobalScoreRing(
              score: score!.global.score,
              label: score!.label.isEmpty ? 'Global' : score!.label,
              isLive: score!.isLive,
            )
          else
            const Text('—', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 4),
          Text(
            score?.isLive == true ? 'live' : 'representative',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'Earth Health — history',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Self-loading: reads the public health-history.json, fail-soft.
            const Expanded(
              child: SingleChildScrollView(
                child: EarthHealthHistoryRow(compact: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.narrow,
    required this.flowLayers,
    required this.overlayLayers,
    required this.pointLayers,
    required this.animateId,
    required this.overlayId,
    required this.annotationId,
    required this.hd,
    required this.spin,
    required this.showHistory,
    required this.onAnimate,
    required this.onOverlay,
    required this.onAnnotation,
    required this.onHd,
    required this.onSpin,
    required this.onToggleHistory,
  });

  final bool narrow;
  final List<_Layer> flowLayers;
  final List<_Layer> overlayLayers;
  final List<_Layer> pointLayers;
  final String? animateId;
  final String? overlayId;
  final String? annotationId;
  final bool hd;
  final bool spin;
  final bool showHistory;
  final ValueChanged<String?> onAnimate;
  final ValueChanged<String?> onOverlay;
  final ValueChanged<String?> onAnnotation;
  final ValueChanged<bool> onHd;
  final ValueChanged<bool> onSpin;
  final VoidCallback onToggleHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _LayerDropdown(
              label: 'Animate',
              layers: flowLayers,
              value: animateId,
              onChanged: onAnimate,
            ),
            _LayerDropdown(
              label: 'Overlay',
              layers: overlayLayers,
              value: overlayId,
              onChanged: onOverlay,
            ),
            _LayerDropdown(
              label: 'Points',
              layers: pointLayers,
              value: annotationId,
              onChanged: onAnnotation,
            ),
            _ToggleChip(label: 'HD', on: hd, onTap: () => onHd(!hd)),
            _ToggleChip(label: 'Spin', on: spin, onTap: () => onSpin(!spin)),
            _ToggleChip(
              label: 'History',
              on: showHistory,
              icon: Icons.timeline,
              onTap: onToggleHistory,
            ),
          ],
        ),
      ),
    );
  }
}

class _LayerDropdown extends StatelessWidget {
  const _LayerDropdown({
    required this.label,
    required this.layers,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<_Layer> layers;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label  ',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          DropdownButton<String?>(
            value: value,
            isDense: true,
            underline: const SizedBox.shrink(),
            dropdownColor: const Color(0xFF15171F),
            iconEnabledColor: Colors.white70,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            items: [
              for (final l in layers)
                DropdownMenuItem<String?>(value: l.id, child: Text(l.label)),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.on,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on
              ? AppColors.cardPurp.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: on ? AppColors.cardPurp : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: on ? Colors.white : Colors.white70),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: on ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NonWebNotice extends StatelessWidget {
  const _NonWebNotice();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'The earth2d globe renders on web.\nRun with: flutter run -d chrome',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
        ),
      ),
    );
  }
}
