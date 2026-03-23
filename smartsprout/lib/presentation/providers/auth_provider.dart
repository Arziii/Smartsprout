import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthState {
  final bool isLoading;
  final String? deviceId;
  final String? error;

  AuthState({
    this.isLoading = false,
    this.deviceId,
    this.error,
  });

  AuthState copyWith({
    bool? isLoading,
    String? deviceId,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      deviceId: deviceId ?? this.deviceId,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  // Use lazy initialization so these instances are NEVER evaluated on Linux Kiosk.
  // Using `late final` ensures they are only created if actually accessed.
  late final FirebaseAuth _auth = FirebaseAuth.instance;
  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  AuthState build() {
    // Start the asynchronous initialization without blocking build.
    Future.microtask(_init);
    return AuthState();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    
    // Auto-login bypass for Raspberry Pi Kiosk (Linux)
    if (Platform.isLinux) {
      state = AuthState(isLoading: false, deviceId: 'SPROUT_A1B2');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedDeviceId = prefs.getString('device_id');
    
    // Check if Firebase Auth has an anonymous session and we have a saved device
    if (savedDeviceId != null && _auth.currentUser != null) {
      state = AuthState(isLoading: false, deviceId: savedDeviceId);
    } else {
      state = AuthState();
    }
  }

  Future<bool> login(String deviceId, String pin) async {
    if (Platform.isLinux) return true; // Bypass on local Pi

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // 1. Sign in anonymously FIRST to get Firestore read permission
      await _auth.signInAnonymously();

      // 2. Fetch device document from Firestore (force server read to bypass emulator cache)
      final doc = await _firestore.collection('devices').doc(deviceId).get(const GetOptions(source: Source.server));
      
      if (!doc.exists) {
        await _auth.signOut();
        state = state.copyWith(isLoading: false, error: 'Device not found.');
        return false;
      }

      final data = doc.data()!;
      final storedPin = data['hashed_pin'] as String?;

      if (storedPin == pin) {
        // PIN valid — save device ID locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('device_id', deviceId);

        state = AuthState(isLoading: false, deviceId: deviceId);
        return true;
      } else {
        await _auth.signOut();
        state = state.copyWith(isLoading: false, error: 'Incorrect PIN.');
        return false;
      }
    } catch (e) {
      try { await _auth.signOut(); } catch (_) {}
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> changePin(String newPin) async {
    final currentDevice = state.deviceId;
    if (currentDevice == null) return false;

    if (Platform.isLinux) return false;

    try {
      state = state.copyWith(isLoading: true, clearError: true);
      await _firestore.collection('devices').doc(currentDevice).update({
        'hashed_pin': newPin,
      });
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to update PIN: $e');
      return false;
    }
  }

  /// Renames the device: copies Firestore data to new doc, sends SYNC_CONFIG to Pi, updates local state.
  /// Requires current PIN for safety.
  Future<String?> renameDevice(String currentPin, String newDeviceId) async {
    if (Platform.isLinux) return 'Not available on Kiosk';

    final oldDeviceId = state.deviceId;
    if (oldDeviceId == null) return 'Not logged in';

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // 1. Verify current PIN
      final oldDoc = await _firestore.collection('devices').doc(oldDeviceId).get();
      if (!oldDoc.exists) {
        state = state.copyWith(isLoading: false, error: 'Device not found');
        return 'Device not found';
      }
      final storedPin = oldDoc.data()?['hashed_pin'] as String?;
      if (storedPin != currentPin) {
        state = state.copyWith(isLoading: false, error: 'Incorrect PIN');
        return 'Incorrect PIN';
      }

      // 2. Check that new ID doesn't already exist
      final newDoc = await _firestore.collection('devices').doc(newDeviceId).get();
      if (newDoc.exists) {
        state = state.copyWith(isLoading: false, error: 'Device ID already taken');
        return 'Device ID already taken';
      }

      // 3. Copy essential data to new document
      final oldData = oldDoc.data()!;
      await _firestore.collection('devices').doc(newDeviceId).set(oldData);

      // 4. Send SYNC_CONFIG command to the OLD doc so the Pi picks it up
      await _firestore
          .collection('devices')
          .doc(oldDeviceId)
          .collection('commands')
          .add({
        'command': 'SYNC_CONFIG',
        'new_device_id': newDeviceId,
        'processed': false,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 5. Update local SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_id', newDeviceId);

      // 6. Update auth state
      state = AuthState(isLoading: false, deviceId: newDeviceId);
      return null; // success
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Rename failed: $e');
      return e.toString();
    }
  }

  Future<void> logout() async {
    if (Platform.isLinux) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_id');
    await _auth.signOut();
    state = AuthState(); 
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
