import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/sensor_model.dart';
import '../../data/services/data_service.dart';

// Key for persisting calibration offsets locally
const _kCalibrationKey = 'smartsprout_calibration_offsets';

// ═══════════════════════════════════════════════════════
// Live Sensor Data Provider (Secure Firebase Sync)
// ═══════════════════════════════════════════════════════
final sensorDataProvider = NotifierProvider<SensorDataNotifier, SensorData>(() {
  return SensorDataNotifier();
});

class SensorDataNotifier extends Notifier<SensorData> {
  StreamSubscription<SensorData>? _firebaseTelemetrySub;
  Timer? _timeoutTimer;

  /// Locally persisted calibration values (survives rebuilds + app restarts).
  List<double> _localCalibration = [0.0, 0.0, 0.0];

  @override
  SensorData build() {
    // 1. Watch the firebase service so this provider rebuilds when deviceId becomes available
    final firebase = ref.watch(dataServiceProvider);

    // 2. Dispose previous listeners if rebuilding
    _firebaseTelemetrySub?.cancel();
    _timeoutTimer?.cancel();

    // 3. Load persisted calibration values synchronously (best-effort)
    _loadPersistedCalibration();

    // 4. Connect to telemetry stream if authenticated
    if (firebase != null) {
      _firebaseTelemetrySub = firebase.telemetryStream.listen(
        (data) {
          // Merge incoming telemetry with locally persisted calibration.
          // The Pi may not have processed the latest set_offset yet,
          // so we always overlay local values if they're non-zero.
          final mergedOffsets = _mergeCalibration(
            data.soilOffsets,
            _localCalibration,
          );
          state = data.copyWith(soilOffsets: mergedOffsets);
          _resetTimeout();
        },
        onError: (error) {
          state = state.copyWith(systemStatus: 'offline');
        },
        onDone: () {
          state = state.copyWith(systemStatus: 'offline');
        },
      );
      _startTimeout();
    }

    // 5. Clean up on provider dispose
    ref.onDispose(() {
      _firebaseTelemetrySub?.cancel();
      _timeoutTimer?.cancel();
    });

    // 6. Start with offline state but include persisted calibration
    return SensorData(
      soilMoisture: const [0.0, 0.0, 0.0],
      soilOffsets: List<double>.from(_localCalibration),
      systemStatus: 'offline',
    );
  }

  /// If no telemetry received for 15 seconds, mark as offline.
  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!state.isOffline) {
        state = state.copyWith(systemStatus: 'offline');
      }
    });
  }

  void _resetTimeout() {
    _timeoutTimer?.cancel();
    _startTimeout();
  }

  /// Manually trigger a watering cycle on a specific zone.
  Future<void> forceWater(int zone, {int durationSeconds = 10}) async {
    if (state.pumpLocked) return; // Respect safety lock
    
    final firebase = ref.read(dataServiceProvider);
    if (firebase != null) {
      await firebase.forceWaterZone(zone, durationSeconds: durationSeconds);
    }
  }

  /// Emergency stop all watering.
  Future<void> emergencyStop() async {
    final firebase = ref.read(dataServiceProvider);
    if (firebase != null) {
      await firebase.emergencyStop();
    }
  }

  /// Optimistically update the calibration offset for a specific zone.
  /// Persists locally and updates the Dashboard state immediately.
  void updateCalibration(int zone, double value) {
    if (zone >= 1 && zone <= _localCalibration.length) {
      _localCalibration[zone - 1] = value;
    }
    _persistCalibration();
    state = state.copyWith(soilOffsets: List<double>.from(_localCalibration));
  }

  /// Merge remote + local calibration: prefer the local value when it's non-zero,
  /// because the Pi may not have processed the latest set_offset command yet.
  List<double> _mergeCalibration(List<double> remote, List<double> local) {
    final merged = <double>[];
    for (int i = 0; i < 3; i++) {
      final r = i < remote.length ? remote[i] : 0.0;
      final l = i < local.length ? local[i] : 0.0;
      // Use local if set, otherwise use whatever the Pi sent
      merged.add(l != 0.0 ? l : r);
    }
    return merged;
  }

  /// Load persisted calibration from SharedPreferences.
  Future<void> _loadPersistedCalibration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCalibrationKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _localCalibration = decoded.map<double>((e) => (e as num).toDouble()).toList();
        // Apply to current state
        state = state.copyWith(soilOffsets: List<double>.from(_localCalibration));
      }
    } catch (_) {
      // Ignore errors — will default to [0, 0, 0]
    }
  }

  /// Save calibration to SharedPreferences.
  Future<void> _persistCalibration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCalibrationKey, jsonEncode(_localCalibration));
    } catch (_) {
      // Ignore write errors
    }
  }
}
