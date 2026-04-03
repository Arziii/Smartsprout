import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/analytics_model.dart';
import '../../data/services/data_service.dart';

// ═══════════════════════════════════════════════════════
// Analytics Provider — PHASE 1: 1-Hour Cache
// ═══════════════════════════════════════════════════════
// Previously used FutureProvider.autoDispose, which triggered a full
// Firestore read every single time the Analytics tab was opened.
// Now uses an AsyncNotifier with a 1-hour in-memory cache:
//   - First open: fetches from Firestore (costs reads)
//   - Subsequent opens within 1 hour: returns cached data instantly (0 reads)
//   - After 1 hour: auto-invalidates and re-fetches on next open

class AnalyticsNotifier extends AsyncNotifier<List<DailyAnalytics>> {
  List<DailyAnalytics>? _cachedData;
  DateTime? _cacheTime;

  static const _cacheDuration = Duration(hours: 1);

  @override
  Future<List<DailyAnalytics>> build() async {
    return await _fetchWithCache();
  }

  Future<List<DailyAnalytics>> _fetchWithCache() async {
    // Return cached data if it's still fresh
    if (_cachedData != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedData!;
    }

    final firebase = ref.read(dataServiceProvider);
    if (firebase == null) {
      return List.generate(
        7,
        (i) => DailyAnalytics(dayIndex: i, avgMoisture: 0, avgTemp: 0),
      );
    }

    final data = await firebase.fetchWeeklyAnalytics();
    _cachedData = data;
    _cacheTime = DateTime.now();
    return data;
  }

  /// Call this to force a refresh (e.g., a manual pull-to-refresh gesture).
  Future<void> refresh() async {
    _cachedData = null;
    _cacheTime = null;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetchWithCache);
  }
}

final analyticsProvider =
    AsyncNotifierProvider<AnalyticsNotifier, List<DailyAnalytics>>(
  AnalyticsNotifier.new,
);
