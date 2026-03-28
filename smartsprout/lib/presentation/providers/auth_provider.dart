import 'dart:io';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedDevice {
  final String deviceId;
  final String nickname;
  final String pin;
  final DateTime lastUsed;

  SavedDevice({
    required this.deviceId,
    required this.nickname,
    required this.pin,
    required this.lastUsed,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'nickname': nickname,
        'pin': pin,
        'lastUsed': lastUsed.toIso8601String(),
      };

  factory SavedDevice.fromJson(Map<String, dynamic> json) {
    return SavedDevice(
      deviceId: json['deviceId'],
      nickname: json['nickname'] ?? json['deviceId'],
      pin: json['pin'],
      lastUsed: DateTime.parse(json['lastUsed']),
    );
  }

  SavedDevice copyWith({String? nickname, DateTime? lastUsed}) {
    return SavedDevice(
      deviceId: deviceId,
      nickname: nickname ?? this.nickname,
      pin: pin,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}

class AuthState {
  final bool isLoading;
  final String? deviceId;
  final String? error;
  final List<SavedDevice> savedDevices;

  AuthState({
    this.isLoading = false,
    this.deviceId,
    this.error,
    this.savedDevices = const [],
  });

  AuthState copyWith({
    bool? isLoading,
    String? deviceId,
    String? error,
    bool clearError = false,
    List<SavedDevice>? savedDevices,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      deviceId: deviceId ?? this.deviceId,
      error: clearError ? null : (error ?? this.error),
      savedDevices: savedDevices ?? this.savedDevices,
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
    
    // Load saved devices list
    final savedDevicesJson = prefs.getString('saved_devices');
    List<SavedDevice> loadedDevices = [];
    if (savedDevicesJson != null) {
      final List decoded = jsonDecode(savedDevicesJson);
      loadedDevices = decoded.map((e) => SavedDevice.fromJson(e)).toList();
      // Sort by last used (newest first)
      loadedDevices.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    }
    
    // Check if Firebase Auth has an anonymous session and we have a saved device
    if (savedDeviceId != null && _auth.currentUser != null) {
      state = AuthState(isLoading: false, deviceId: savedDeviceId, savedDevices: loadedDevices);
    } else {
      state = AuthState(savedDevices: loadedDevices);
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

        // Update saved devices list
        List<SavedDevice> updatedDevices = List.from(state.savedDevices);
        final existingIndex = updatedDevices.indexWhere((d) => d.deviceId == deviceId);
        
        if (existingIndex != -1) {
          updatedDevices[existingIndex] = updatedDevices[existingIndex].copyWith(lastUsed: DateTime.now());
        } else {
          updatedDevices.add(SavedDevice(
            deviceId: deviceId,
            nickname: deviceId, // default nickname
            pin: pin,
            lastUsed: DateTime.now(),
          ));
        }
        
        // Ensure max 5 devices
        updatedDevices.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
        if (updatedDevices.length > 5) {
          updatedDevices = updatedDevices.take(5).toList();
        }
        
        await prefs.setString('saved_devices', jsonEncode(updatedDevices.map((e) => e.toJson()).toList()));

        state = AuthState(isLoading: false, deviceId: deviceId, savedDevices: updatedDevices);
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

  Future<bool> quickSwitch(String deviceId) async {
    final dev = state.savedDevices.firstWhere((d) => d.deviceId == deviceId, orElse: () => throw Exception('Device not found'));
    return await login(dev.deviceId, dev.pin);
  }

  Future<void> updateDeviceNickname(String deviceId, String newNickname) async {
    final prefs = await SharedPreferences.getInstance();
    List<SavedDevice> updatedDevices = List.from(state.savedDevices);
    final existingIndex = updatedDevices.indexWhere((d) => d.deviceId == deviceId);
    
    if (existingIndex != -1) {
      updatedDevices[existingIndex] = updatedDevices[existingIndex].copyWith(nickname: newNickname);
      await prefs.setString('saved_devices', jsonEncode(updatedDevices.map((e) => e.toJson()).toList()));
      state = state.copyWith(savedDevices: updatedDevices);
    }
  }

  Future<void> removeSavedDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    List<SavedDevice> updatedDevices = List.from(state.savedDevices);
    updatedDevices.removeWhere((d) => d.deviceId == deviceId);
    await prefs.setString('saved_devices', jsonEncode(updatedDevices.map((e) => e.toJson()).toList()));
    
    final currentDevice = state.deviceId;
    state = state.copyWith(savedDevices: updatedDevices);
    
    // If the user removed the actively logged in device
    if (currentDevice == deviceId) {
       await logout();
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
    // Keep saved devices when logging out
    state = AuthState(savedDevices: state.savedDevices); 
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
