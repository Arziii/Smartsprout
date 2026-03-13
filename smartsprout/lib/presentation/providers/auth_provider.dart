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
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  AuthState build() {
    // Start the asynchronous initialization without blocking build.
    Future.microtask(_init);
    return AuthState();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
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

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_id');
    await _auth.signOut();
    state = AuthState(); 
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
