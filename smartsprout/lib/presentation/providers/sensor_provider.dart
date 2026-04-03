import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/sensor_model.dart';
import '../../data/services/data_service.dart';

// Persistence keys
const _kCalibrationKey = 'smartsprout_calibration_offsets';
const _kTriggersKey = 'smartsprout_trigger_settings';

// ═══════════════════════════════════════════════════════
// Plant Image Provider for Zones
// ═══════════════════════════════════════════════════════
final plantImageProvider =
    StreamProvider.autoDispose.family<String?, String>((ref, zoneId) {
  final firebase = ref.watch(dataServiceProvider);
  if (firebase == null) return Stream.value(null);
  return firebase.zoneImageStream(zoneId);
});

// ═══════════════════════════════════════════════════════
// Per-Zone Pump Loading State (Optimistic UI — Phase 4.8)
// ═══════════════════════════════════════════════════════
class PumpLoadingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  // ignore: use_setters_to_change_properties
  void setLoading(bool value) => state = value;
}

final pumpLoadingProvider =
    NotifierProvider.family<PumpLoadingNotifier, bool, int>(
  (zone) => PumpLoadingNotifier(),
);

// ═══════════════════════════════════════════════════════
// Pending Trigger Settings (Optimistic — persisted locally)
// ═══════════════════════════════════════════════════════
/// Stores the most recently SUBMITTED trigger rules per zone so they survive
/// navigation AND are reflected on ZoneCards before the Pi confirms them.
class TriggerSettings {
  final List<double> startThreshold; // [z1, z2, z3]
  final List<double> targetMoisture; // [z1, z2, z3]
  final List<int> maxPumpRuntime; // [z1, z2, z3]

  const TriggerSettings({
    this.startThreshold = const [50.0, 50.0, 50.0],
    this.targetMoisture = const [65.0, 65.0, 65.0],
    this.maxPumpRuntime = const [30, 30, 30],
  });

  TriggerSettings copyWithZone(
    int zone, {
    double? start,
    double? target,
    int? timeout,
  }) {
    final idx = zone - 1;
    final newStarts = List<double>.from(startThreshold);
    final newTargets = List<double>.from(targetMoisture);
    final newTimeouts = List<int>.from(maxPumpRuntime);
    if (start != null) newStarts[idx] = start;
    if (target != null) newTargets[idx] = target;
    if (timeout != null) newTimeouts[idx] = timeout;
    return TriggerSettings(
      startThreshold: newStarts,
      targetMoisture: newTargets,
      maxPumpRuntime: newTimeouts,
    );
  }

  /// Merge: local wins over remote for any zone where local differs from default.
  TriggerSettings mergeWith(TriggerSettings remote) {
    const d = TriggerSettings();
    final newStarts = List<double>.from(remote.startThreshold);
    final newTargets = List<double>.from(remote.targetMoisture);
    final newTimeouts = List<int>.from(remote.maxPumpRuntime);
    for (int i = 0; i < 3; i++) {
      if (startThreshold[i] != d.startThreshold[i]) {
        newStarts[i] = startThreshold[i];
      }
      if (targetMoisture[i] != d.targetMoisture[i]) {
        newTargets[i] = targetMoisture[i];
      }
      if (maxPumpRuntime[i] != d.maxPumpRuntime[i]) {
        newTimeouts[i] = maxPumpRuntime[i];
      }
    }
    return TriggerSettings(
      startThreshold: newStarts,
      targetMoisture: newTargets,
      maxPumpRuntime: newTimeouts,
    );
  }

  Map<String, dynamic> toJson() => {
        'starts': startThreshold,
        'targets': targetMoisture,
        'timeouts': maxPumpRuntime,
      };

  factory TriggerSettings.fromJson(Map<String, dynamic> json) {
    List<double> parseDoubles(dynamic raw, List<double> fallback) {
      if (raw is List) {
        return raw.map<double>((e) => (e as num).toDouble()).toList();
      }
      return fallback;
    }

    List<int> parseInts(dynamic raw, List<int> fallback) {
      if (raw is List) return raw.map<int>((e) => (e as num).toInt()).toList();
      return fallback;
    }

    const d = TriggerSettings();
    return TriggerSettings(
      startThreshold: parseDoubles(json['starts'], d.startThreshold),
      targetMoisture: parseDoubles(json['targets'], d.targetMoisture),
      maxPumpRuntime: parseInts(json['timeouts'], d.maxPumpRuntime),
    );
  }
}

class TriggerSettingsNotifier extends Notifier<TriggerSettings> {
  @override
  TriggerSettings build() {
    _load();
    return const TriggerSettings();
  }

  /// Call when user taps SET TRIGGER RULES.
  void updateZone(
    int zone, {
    required double start,
    required double target,
    required int timeout,
  }) {
    state = state.copyWithZone(zone,
        start: start, target: target, timeout: timeout);
    _persist();
  }

  /// Called from SensorDataNotifier when Pi confirms new values.
  /// Uses local-wins merge so pending user changes are never overwritten.
  void mergeRemote(TriggerSettings remote) {
    state = state.mergeWith(remote);
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kTriggersKey);
      if (raw != null) {
        state =
            TriggerSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTriggersKey, jsonEncode(state.toJson()));
    } catch (_) {}
  }
}

final triggerSettingsProvider =
    NotifierProvider<TriggerSettingsNotifier, TriggerSettings>(
  TriggerSettingsNotifier.new,
);

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
    final firebase = ref.watch(dataServiceProvider);

    _firebaseTelemetrySub?.cancel();
    _timeoutTimer?.cancel();

    _loadPersistedCalibration();

    if (firebase != null) {
      _firebaseTelemetrySub = firebase.telemetryStream.listen(
        (data) {
          // Merge incoming telemetry with locally persisted calibration.
          final mergedOffsets = _mergeCalibration(
            data.soilOffsets,
            _localCalibration,
          );

          // Notify trigger provider — local values win over remote.
          final remoteSettings = TriggerSettings(
            startThreshold: data.startThreshold,
            targetMoisture: data.targetMoisture,
            maxPumpRuntime: data.maxPumpRuntime,
          );
          ref
              .read(triggerSettingsProvider.notifier)
              .mergeRemote(remoteSettings);

          // Read merged trigger values back into sensorData.
          final triggers = ref.read(triggerSettingsProvider);
          state = data.copyWith(
            soilOffsets: mergedOffsets,
            startThreshold: triggers.startThreshold,
            targetMoisture: triggers.targetMoisture,
            maxPumpRuntime: triggers.maxPumpRuntime,
          );
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

    ref.onDispose(() {
      _firebaseTelemetrySub?.cancel();
      _timeoutTimer?.cancel();
    });

    return SensorData(
      soilMoisture: const [0.0, 0.0, 0.0],
      soilOffsets: List<double>.from(_localCalibration),
      systemStatus: 'offline',
    );
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    // DEFENSE OPTIMIZATION: Set to 25s (previously 45s).
    // With a 10s heartbeat, 25s allows for just 2 missed packets before "Offline",
    // giving the exact feel of a 5s heartbeat without burning quota.
    _timeoutTimer = Timer(const Duration(seconds: 25), () {
      if (!state.isOffline) {
        state = state.copyWith(systemStatus: 'offline');
      }
    });
  }

  void _resetTimeout() {
    _timeoutTimer?.cancel();
    _startTimeout();
  }

  Future<void> forceWater(int zone, {int durationSeconds = 10}) async {
    if (state.pumpLocked) return;
    final firebase = ref.read(dataServiceProvider);
    if (firebase != null) {
      await firebase.forceWaterZone(zone, durationSeconds: durationSeconds);
    }
  }

  Future<void> emergencyStop() async {
    final firebase = ref.read(dataServiceProvider);
    if (firebase != null) {
      await firebase.emergencyStop();
    }
  }

  void updateCalibration(int zone, double value) {
    if (zone >= 1 && zone <= _localCalibration.length) {
      _localCalibration[zone - 1] = value;
    }
    _persistCalibration();
    state = state.copyWith(soilOffsets: List<double>.from(_localCalibration));
  }

  List<double> _mergeCalibration(List<double> remote, List<double> local) {
    final merged = <double>[];
    for (int i = 0; i < 3; i++) {
      final r = i < remote.length ? remote[i] : 0.0;
      final l = i < local.length ? local[i] : 0.0;
      merged.add(l != 0.0 ? l : r);
    }
    return merged;
  }

  Future<void> _loadPersistedCalibration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCalibrationKey);
      if (raw != null) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _localCalibration =
            decoded.map<double>((e) => (e as num).toDouble()).toList();
        state =
            state.copyWith(soilOffsets: List<double>.from(_localCalibration));
      }
    } catch (_) {}
  }

  Future<void> _persistCalibration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCalibrationKey, jsonEncode(_localCalibration));
    } catch (_) {}
  }
}
