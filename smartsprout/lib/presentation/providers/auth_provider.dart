import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ═══════════════════════════════════════════════════════
// SavedDevice Model
// PIN field removed — Custom Token sessions replace PIN replay.
// ═══════════════════════════════════════════════════════
class SavedDevice {
  final String deviceId;
  final String nickname;
  final DateTime lastUsed;

  SavedDevice({
    required this.deviceId,
    required this.nickname,
    required this.lastUsed,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'nickname': nickname,
        'lastUsed': lastUsed.toIso8601String(),
      };

  factory SavedDevice.fromJson(Map<String, dynamic> json) {
    return SavedDevice(
      deviceId: json['deviceId'],
      nickname: json['nickname'] ?? json['deviceId'],
      lastUsed: DateTime.parse(json['lastUsed']),
    );
  }

  SavedDevice copyWith({String? nickname, DateTime? lastUsed}) {
    return SavedDevice(
      deviceId: deviceId,
      nickname: nickname ?? this.nickname,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}

// ═══════════════════════════════════════════════════════
// AuthState
// ═══════════════════════════════════════════════════════
class AuthState {
  final bool isLoading;
  final String? deviceId;
  final String? deviceName;
  final String? error;
  final List<SavedDevice> savedDevices;

  // Pi-Bouncer rate-limit state
  final bool isRateLimited;
  final DateTime? rateLimitExpiry;

  AuthState({
    this.isLoading = false,
    this.deviceId,
    this.deviceName,
    this.error,
    this.savedDevices = const [],
    this.isRateLimited = false,
    this.rateLimitExpiry,
  });

  AuthState copyWith({
    bool? isLoading,
    String? deviceId,
    String? deviceName,
    String? error,
    bool clearError = false,
    List<SavedDevice>? savedDevices,
    bool? isRateLimited,
    DateTime? rateLimitExpiry,
    bool clearRateLimit = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      error: clearError ? null : (error ?? this.error),
      savedDevices: savedDevices ?? this.savedDevices,
      isRateLimited: clearRateLimit ? false : (isRateLimited ?? this.isRateLimited),
      rateLimitExpiry: clearRateLimit ? null : (rateLimitExpiry ?? this.rateLimitExpiry),
    );
  }
}

// ═══════════════════════════════════════════════════════
// AuthNotifier — Pi-Bouncer Architecture
// ═══════════════════════════════════════════════════════
class AuthNotifier extends Notifier<AuthState> {
  late final FirebaseAuth _auth = FirebaseAuth.instance;
  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const _uuid = Uuid();

  // Timeout before showing "Hardware Offline"
  static const _piTimeoutSeconds = 15;

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

    // Option B: if a valid Firebase session exists, restore state directly
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

  // ─────────────────────────────────────────────────────
  // Pi-Bouncer Login Flow
  // ─────────────────────────────────────────────────────
  Future<bool> login(String deviceId, String pin) async {
    if (Platform.isLinux) return true;

    state = state.copyWith(isLoading: true, clearError: true, clearRateLimit: true);

    final requestId = _uuid.v4();
    StreamSubscription<DocumentSnapshot>? listener;
    Timer? timeoutTimer;
    bool completed = false;

    // Cleanup helper — always called once
    Future<void> cleanup({bool deleteDoc = true}) async {
      timeoutTimer?.cancel();
      listener?.cancel();
      if (deleteDoc) {
        try {
          await _firestore.collection('login_requests').doc(requestId).delete();
        } catch (_) {}
      }
    }

    try {
      // Step 1: Write the login request to Firestore
      await _firestore.collection('login_requests').doc(requestId).set({
        'deviceId':  deviceId,
        'pin':       pin,
        'status':    'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      final Completer<bool> completer = Completer();

      // Step 2: Start 15-second hardware offline timeout
      timeoutTimer = Timer(const Duration(seconds: _piTimeoutSeconds), () async {
        if (completed) return;
        completed = true;
        await cleanup();
        state = state.copyWith(
          isLoading: false,
          error: 'Hardware Offline. Is your Garden powered on?',
        );
        if (!completer.isCompleted) completer.complete(false);
      });

      // Step 3: Listen for Pi's response on the request document
      listener = _firestore
          .collection('login_requests')
          .doc(requestId)
          .snapshots()
          .listen((snap) async {
        if (completed) return;
        if (!snap.exists) return;

        final data = snap.data() as Map<String, dynamic>?;
        if (data == null) return;

        final responseStatus = data['status'] as String? ?? 'pending';
        if (responseStatus == 'pending') return; // Still processing

        completed = true;
        timeoutTimer?.cancel();
        listener?.cancel();

        switch (responseStatus) {
          case 'approved':
            final token = data['token'] as String?;
            if (token != null && token.isNotEmpty) {
              try {
                await _auth.signInWithCustomToken(token);
                await cleanup(); // Delete the request doc
                _onLoginSuccess(deviceId, data);
                if (!completer.isCompleted) completer.complete(true);
              } catch (e) {
                state = state.copyWith(isLoading: false, error: 'Auth failed: $e');
                await cleanup();
                if (!completer.isCompleted) completer.complete(false);
              }
            } else {
              state = state.copyWith(isLoading: false, error: 'Token missing. Try again.');
              await cleanup();
              if (!completer.isCompleted) completer.complete(false);
            }
            break;

          case 'rate_limited':
            final lockedUntilEpoch = data['locked_until'] as int?;
            final errorMsg = data['error'] as String? ?? 'Too many attempts. Wait 15 minutes.';
            DateTime? expiry;
            if (lockedUntilEpoch != null) {
              expiry = DateTime.fromMillisecondsSinceEpoch(lockedUntilEpoch * 1000);
            }
            state = state.copyWith(
              isLoading: false,
              isRateLimited: true,
              rateLimitExpiry: expiry,
              error: errorMsg,
            );
            await cleanup();
            if (!completer.isCompleted) completer.complete(false);
            break;

          case 'error':
          default:
            final errorMsg = data['error'] as String? ?? 'Incorrect PIN.';
            state = state.copyWith(isLoading: false, error: errorMsg);
            await cleanup();
            if (!completer.isCompleted) completer.complete(false);
            break;
        }
      });

      return await completer.future;

    } catch (e) {
      timeoutTimer?.cancel();
      listener?.cancel();
      try {
        await _firestore.collection('login_requests').doc(requestId).delete();
      } catch (_) {}
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  // ─────────────────────────────────────────────────────
  // Option B: Quick Switch
  // If Firebase session is still valid with matching UID → skip Pi round-trip.
  // Otherwise signal UI to show login form with deviceId pre-filled.
  // ─────────────────────────────────────────────────────
  Future<bool> quickSwitch(String deviceId) async {
    if (Platform.isLinux) return true;

    final user = _auth.currentUser;
    if (user != null && user.uid == deviceId) {
      // Session is still valid — restore local state, no Pi round-trip
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString('device_name') ?? deviceId;

      final updatedDevices = List<SavedDevice>.from(state.savedDevices);
      final idx = updatedDevices.indexWhere((d) => d.deviceId == deviceId);
      if (idx != -1) {
        updatedDevices[idx] = updatedDevices[idx].copyWith(lastUsed: DateTime.now());
        updatedDevices.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
        await prefs.setString(
            'saved_devices', jsonEncode(updatedDevices.map((e) => e.toJson()).toList()));
      }

      state = AuthState(
        isLoading: false,
        deviceId: deviceId,
        deviceName: savedName,
        savedDevices: updatedDevices,
      );
      return true;
    }

    // Session expired — signal UI to show login form (returns false)
    // The HardwareLoginScreen handles this by pre-filling the Device ID
    return false;
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void clearRateLimit() {
    state = state.copyWith(clearRateLimit: true, clearError: true);
  }

  // ─────────────────────────────────────────────────────
  // Post-login persistence
  // ─────────────────────────────────────────────────────
  Future<void> _onLoginSuccess(String deviceId, Map<String, dynamic> responseData) async {
    // Fetch device name from Firestore devices doc
    String finalNickname = deviceId;
    try {
      final doc = await _firestore.collection('devices').doc(deviceId).get();
      if (doc.exists) {
        final cloudName = doc.data()?['device_name'] as String?;
        if (cloudName != null && cloudName.isNotEmpty) finalNickname = cloudName;
      }
    } catch (_) {}

    List<SavedDevice> updatedDevices = List.from(state.savedDevices);
    final existingIndex = updatedDevices.indexWhere((d) => d.deviceId == deviceId);

    if (existingIndex != -1) {
      finalNickname = updatedDevices[existingIndex].nickname.isNotEmpty
          ? updatedDevices[existingIndex].nickname
          : finalNickname;
      updatedDevices[existingIndex] = updatedDevices[existingIndex].copyWith(
        lastUsed: DateTime.now(),
      );
    } else {
      updatedDevices.add(SavedDevice(
        deviceId: deviceId,
        nickname: finalNickname,
        lastUsed: DateTime.now(),
      ));
    }

    updatedDevices.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    if (updatedDevices.length > 5) {
      updatedDevices = updatedDevices.take(5).toList();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_id', deviceId);
    await prefs.setString('device_name', finalNickname);
    await prefs.setString(
        'saved_devices', jsonEncode(updatedDevices.map((e) => e.toJson()).toList()));

    state = AuthState(
      isLoading: false,
      deviceId: deviceId,
      deviceName: finalNickname,
      savedDevices: updatedDevices,
    );
  }

  // ─────────────────────────────────────────────────────
  // Device Management (unchanged behaviour, PIN removed)
  // ─────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────
  // Change PIN — now routes through Pi-Bouncer
  // The Pi writes the new hash; Flutter just requests it via Firestore command.
  // ─────────────────────────────────────────────────────
  Future<bool> changePin(String currentPin, String newPin) async {
    final currentDevice = state.deviceId;
    if (currentDevice == null) return false;
    if (Platform.isLinux) return false;

    try {
      state = state.copyWith(isLoading: true, clearError: true);

      // Write a change_pin command via the authenticated commands subcollection
      await _firestore
          .collection('devices')
          .doc(currentDevice)
          .collection('commands')
          .add({
        'command':     'change_pin',
        'current_pin': currentPin,
        'new_pin':     newPin,
        'processed':   false,
        'createdAt':   FieldValue.serverTimestamp(),
      });

      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to update PIN: $e');
      return false;
    }
  }

  /// Renames the device by updating the [device_name] field directly in Firestore.
  Future<String?> renameDevice(String currentPin, String newDeviceName) async {
    if (Platform.isLinux) return 'Not available on Kiosk';

    final currentDeviceId = state.deviceId;
    if (currentDeviceId == null) return 'Not logged in';

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _firestore.collection('devices').doc(currentDeviceId).update({
        'device_name': newDeviceName,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', newDeviceName);

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
      return null;
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
