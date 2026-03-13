import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/sensor_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/providers/auth_provider.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String deviceId;

  FirebaseService(this.deviceId);

  /// Streams the latest telemetry from the device's main document.
  Stream<SensorData> get telemetryStream {
    return _firestore.collection('devices').doc(deviceId).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return const SensorData(systemStatus: 'offline');
      }
      final data = snapshot.data()!;
      // Use the sensor data parsing logic, mapped from the Firestore schema
      // The Pi script updates the main doc with all telemetry data now.
      return SensorData.fromJson(data);
    });
  }

  /// Sends a command to the device's `commands` subcollection.
  /// Firestore handles offline queuing automatically!
  Future<void> sendCommand(Map<String, dynamic> commandPayload) async {
    try {
      await _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('commands')
          .add({
        ...commandPayload,
        'timestamp': FieldValue.serverTimestamp(),
        'processed': false,
      });
      debugPrint('[FIREBASE_SERVICE] Command queued/sent: \$commandPayload');
    } catch (e) {
      debugPrint('[FIREBASE_SERVICE] Failed to send command: \$e');
    }
  }

  /// Convenience wrapper for force_water
  Future<void> forceWater(int zone, {int durationSeconds = 10}) async {
    await sendCommand({
      'command': 'force_water',
      'zone': zone,
      'duration_seconds': durationSeconds,
    });
  }

  /// Convenience wrapper for stop_all
  Future<void> emergencyStop() async {
    await sendCommand({
      'command': 'stop_all',
    });
  }
}

final firebaseServiceProvider = Provider<FirebaseService?>((ref) {
  final authState = ref.watch(authProvider);
  if (authState.deviceId != null) {
    return FirebaseService(authState.deviceId!);
  }
  return null;
});
