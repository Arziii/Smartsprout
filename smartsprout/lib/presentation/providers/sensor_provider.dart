import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/sensor_model.dart';
import '../../data/services/data_service.dart';

// ═══════════════════════════════════════════════════════
// Live Sensor Data Provider (Secure Firebase Sync)
// ═══════════════════════════════════════════════════════
final sensorDataProvider = NotifierProvider<SensorDataNotifier, SensorData>(() {
  return SensorDataNotifier();
});

class SensorDataNotifier extends Notifier<SensorData> {
  StreamSubscription<SensorData>? _firebaseTelemetrySub;
  Timer? _timeoutTimer;

  @override
  SensorData build() {
    // 1. Watch the firebase service so this provider rebuilds when deviceId becomes available
    final firebase = ref.watch(dataServiceProvider);

    // 2. Dispose previous listeners if rebuilding
    _firebaseTelemetrySub?.cancel();
    _timeoutTimer?.cancel();

    // 3. Connect to telemetry stream if authenticated
    if (firebase != null) {
      _firebaseTelemetrySub = firebase.telemetryStream.listen((data) {
        state = data;
        _resetTimeout();
      });
      _startTimeout();
    }

    // 4. Clean up on provider dispose
    ref.onDispose(() {
      _firebaseTelemetrySub?.cancel();
      _timeoutTimer?.cancel();
    });

    // 5. Start with offline state - updates arrive via the listener above
    return const SensorData(
      soilMoisture: [0.0, 0.0, 0.0],
      systemStatus: 'offline',
    );
  }

  /// If no telemetry received for 10 seconds, mark as offline.
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
    
    // Send to Firestore for secure cloud sync and IoT queue processing
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
}
