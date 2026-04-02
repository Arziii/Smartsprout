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
  /// Human-friendly display name stored as a field inside the Firestore doc.
  /// Different from [deviceId] which is the permanent, immutable document ID.
  final String? deviceName;
  final String? error;
  final List<SavedDevice> savedDevices;

  AuthState({
    this.isLoading = false,
    this.deviceId,
    this.deviceName,
    this.error,
    this.savedDevices = const [],
  });

  AuthState copyWith({
    bool? isLoading,
    String? deviceId,
    String? deviceName,
    String? error,
    bool clearError = false,
    List<SavedDevice>? savedDevices,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      error: clearError ? null : (error ?? this.error),
      savedDevices: savedDevices ?? this.savedDevices,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  late final FirebaseAuth _auth = FirebaseAuth.instance;
  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  AuthState build() {
    Future.microtask(_init);
    return AuthState();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);

    // Auto-login bypass for Raspberry Pi Kiosk (Linux)
    if (Platform.isLinux) {
      state = AuthState(isLoading: false, deviceId: 'SPROUT_A1B2', deviceName: 'Smart Sprout Kiosk');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedDeviceId = prefs.getString('device_id');
    final savedDeviceName = prefs.getString('device_name');

    // Load saved devices list
    final savedDevicesJson = prefs.getString('saved_devices');
    List<SavedDevice> loadedDevices = [];
    if (savedDevicesJson != null) {
      final List decoded = jsonDecode(savedDevicesJson);
      loadedDevices = decoded.map((e) => SavedDevice.fromJson(e)).toList();
      loadedDevices.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    }

    if (savedDeviceId != null && _auth.currentUser != null) {
      state = AuthState(
        isLoading: false,
        deviceId: savedDeviceId,
        deviceName: savedDeviceName ?? savedDeviceId,
        savedDevices: loadedDevices,
      );
    } else {
      state = AuthState(savedDevices: loadedDevices);
    }
  }

  Future<bool> login(String deviceId, String pin) async {
    if (Platform.isLinux) return true;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }

      final doc = await _firestore
          .collection('devices')
          .doc(deviceId)
          .get(const GetOptions(source: Source.server));

      if (!doc.exists) {
        await _auth.signOut();
        state = state.copyWith(isLoading: false, error: 'Device not found.');
        return false;
      }

      final data = doc.data()!;
      final storedPin = data['hashed_pin'] as String?;

      if (storedPin == pin) {
        // Read the human-friendly display name from cloud; allow it to be null
        final cloudDeviceName = (data['device_name'] as String?)?.isNotEmpty == true
            ? data['device_name'] as String
            : null;

        List<SavedDevice> updatedDevices = List.from(state.savedDevices);
        final existingIndex = updatedDevices.indexWhere((d) => d.deviceId == deviceId);

        String finalNickname;
        if (existingIndex != -1) {
          finalNickname = cloudDeviceName ?? updatedDevices[existingIndex].nickname;
          updatedDevices[existingIndex] = updatedDevices[existingIndex].copyWith(
            nickname: finalNickname,
            lastUsed: DateTime.now(),
          );
        } else {
          finalNickname = cloudDeviceName ?? deviceId;
          updatedDevices.add(SavedDevice(
            deviceId: deviceId,
            nickname: finalNickname,
            pin: pin,
            lastUsed: DateTime.now(),
          ));
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('device_id', deviceId);
        await prefs.setString('device_name', finalNickname);

        updatedDevices.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
        if (updatedDevices.length > 5) {
          updatedDevices = updatedDevices.take(5).toList();
        }

        await prefs.setString(
            'saved_devices', jsonEncode(updatedDevices.map((e) => e.toJson()).toList()));

        state = AuthState(
          isLoading: false,
          deviceId: deviceId,
          deviceName: finalNickname,
          savedDevices: updatedDevices,
        );
        return true;
      } else {
        await _auth.signOut();
        state = state.copyWith(isLoading: false, error: 'Incorrect PIN.');
        return false;
      }
    } catch (e) {
      try {
        await _auth.signOut();
      } catch (_) {}
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  Future<bool> quickSwitch(String deviceId) async {
    final dev = state.savedDevices.firstWhere(
      (d) => d.deviceId == deviceId,
      orElse: () => throw Exception('Device not found'),
    );
    return await login(dev.deviceId, dev.pin);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<void> updateDeviceNickname(String deviceId, String newNickname) async {
    final prefs = await SharedPreferences.getInstance();
    List<SavedDevice> updatedDevices = List.from(state.savedDevices);
    final existingIndex = updatedDevices.indexWhere((d) => d.deviceId == deviceId);

    if (existingIndex != -1) {
      updatedDevices[existingIndex] = updatedDevices[existingIndex].copyWith(nickname: newNickname);
      await prefs.setString(
          'saved_devices', jsonEncode(updatedDevices.map((e) => e.toJson()).toList()));
      state = state.copyWith(savedDevices: updatedDevices);
    }
  }

  Future<void> removeSavedDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    List<SavedDevice> updatedDevices = List.from(state.savedDevices);
    updatedDevices.removeWhere((d) => d.deviceId == deviceId);
    await prefs.setString(
        'saved_devices', jsonEncode(updatedDevices.map((e) => e.toJson()).toList()));

    final currentDevice = state.deviceId;
    state = state.copyWith(savedDevices: updatedDevices);

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

      // Also update the saved device's pin in local storage
      final prefs = await SharedPreferences.getInstance();
      List<SavedDevice> updatedDevices = List.from(state.savedDevices);
      final idx = updatedDevices.indexWhere((d) => d.deviceId == currentDevice);
      if (idx != -1) {
        updatedDevices[idx] = SavedDevice(
          deviceId: updatedDevices[idx].deviceId,
          nickname: updatedDevices[idx].nickname,
          pin: newPin,
          lastUsed: updatedDevices[idx].lastUsed,
        );
        await prefs.setString(
            'saved_devices', jsonEncode(updatedDevices.map((e) => e.toJson()).toList()));
      }

      state = state.copyWith(isLoading: false, savedDevices: updatedDevices);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to update PIN: $e');
      return false;
    }
  }

  /// Renames the device by updating the [device_name] field directly in Firestore.
  /// The document ID (hardware identifier) remains permanent and unchanged.
  /// Requires current PIN for security verification.
  Future<String?> renameDevice(String currentPin, String newDeviceName) async {
    if (Platform.isLinux) return 'Not available on Kiosk';

    final currentDeviceId = state.deviceId;
    if (currentDeviceId == null) return 'Not logged in';

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // 1. Verify current PIN
      final doc = await _firestore.collection('devices').doc(currentDeviceId).get();
      if (!doc.exists) {
        state = state.copyWith(isLoading: false, error: 'Device not found');
        return 'Device not found';
      }
      final storedPin = doc.data()?['hashed_pin'] as String?;
      if (storedPin != currentPin) {
        state = state.copyWith(isLoading: false, error: 'Incorrect PIN');
        return 'Incorrect PIN';
      }

      // 2. Update the device_name field in-place — no copying, no orphan documents
      await _firestore.collection('devices').doc(currentDeviceId).update({
        'device_name': newDeviceName,
      });

      // 3. Update local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', newDeviceName);

      // 4. Update saved devices list nickname
      List<SavedDevice> updatedDevices = List.from(state.savedDevices);
      final idx = updatedDevices.indexWhere((d) => d.deviceId == currentDeviceId);
      if (idx != -1) {
        updatedDevices[idx] = updatedDevices[idx].copyWith(nickname: newDeviceName);
        await prefs.setString(
            'saved_devices', jsonEncode(updatedDevices.map((e) => e.toJson()).toList()));
      }

      state = state.copyWith(
        isLoading: false,
        deviceName: newDeviceName,
        savedDevices: updatedDevices,
      );
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
    await prefs.remove('device_name');
    await _auth.signOut();
    state = AuthState(savedDevices: state.savedDevices);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
