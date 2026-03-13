import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/sensor_model.dart';
import '../../data/services/firebase_service.dart';

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
    // Start with offline state
    final initialData = const SensorData(
      soilMoisture: [0.0, 0.0, 0.0],
      systemStatus: 'offline',
    );

    // Auto-connect to Firebase stream on build
    _connectAndListen();

    ref.onDispose(() {
      _firebaseTelemetrySub?.cancel();
      _timeoutTimer?.cancel();
    });

    return initialData;
  }

  void _connectAndListen() {
    final firebase = ref.read(firebaseServiceProvider);

    // 1. Setup Firebase Listener (Cloud source of truth & offline cache)
    if (firebase != null) {
      _firebaseTelemetrySub?.cancel();
      _firebaseTelemetrySub = firebase.telemetryStream.listen((data) {
        state = data;
        _resetTimeout();
      });
      _startTimeout();
    }
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
    final firebase = ref.read(firebaseServiceProvider);
    if (firebase != null) {
      await firebase.forceWater(zone, durationSeconds: durationSeconds);
    }
  }

  /// Emergency stop all watering.
  Future<void> emergencyStop() async {
    final firebase = ref.read(firebaseServiceProvider);
    if (firebase != null) {
      await firebase.emergencyStop();
    }
  }
}
