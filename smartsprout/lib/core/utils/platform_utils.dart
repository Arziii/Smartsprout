// ═══════════════════════════════════════════════════════
// Smart Sprout — Platform Utilities
// Centralized platform detection for the three-tier
// hardware optimization strategy.
// ═══════════════════════════════════════════════════════

import 'dart:io';

/// **Lite Mode** — Formerly for Pi 3B. Disabled for Pi 4 (4GB RAM).
bool get isLiteMode => false;

/// **Premium Mode** — Now enabled universally (Pi 4, iOS, Android, Windows).
bool get isPremiumMode => true;

/// **Desktop Mode** — Windows, macOS, or Linux.
/// Enables mouse/keyboard UX: visible scrollbars, hover states,
/// and right-click context menus.
bool get isDesktopMode =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Returns the asset path for a plant image by filename.
///
/// Currently returns the standard-resolution image for all tiers.
/// To implement a low-res swap for the Pi Lite build in the future,
/// replace the path prefix below:
///
/// ```dart
/// if (isLiteMode) {
///   return 'assets/images/plants_lowres/\$filename';
/// }
/// ```
///
/// Then create a `plants_lowres/` directory with compressed versions
/// of each image (e.g., 128×128 WebP thumbnails) and register it
/// in `pubspec.yaml` under `flutter > assets`.
String getPlantAsset(String filename) {
  // TODO(perf): Swap to low-res assets for Linux/Pi when available.
  // if (isLiteMode) return 'assets/images/plants_lowres/\$filename';
  return 'assets/images/plants/\$filename';
}
