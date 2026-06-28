import 'package:flutter/painting.dart';

/// Minimal colour tokens inlined from the private `rk_branding` package.
///
/// The standalone globe references only these five `AppColors` constants (the
/// score rings + the health-history row). The full brand palette and brand
/// assets remain reserved (see LICENSE / NOTICE) — this file carries ONLY the
/// exact tokens the open viewer needs so it builds with zero private deps.
abstract final class AppColors {
  /// Sage green — health "good" band + history timeline accent.
  static const green = Color.fromRGBO(130, 172, 124, 1);

  /// rand0m signature red ("kitt") — loading spinner accent.
  static const kitt = Color.fromRGBO(255, 65, 36, 1);

  /// Light neutral text on dark cards.
  static const textLight = Color(0xFFB1B4C0);

  /// Dark card surface.
  static const cardDark = Color.fromRGBO(43, 43, 43, 1);

  /// Periwinkle — Global score identity accent.
  static const cardPurp = Color.fromRGBO(187, 168, 255, 1);
}
