import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/sensor_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../presentation/providers/auth_provider.dart';
import '../../data/models/analytics_model.dart';

class DataService {
  // Lazy getter — only accessed inside non-Linux (else) code paths.
  // DO NOT convert back to an eager field: Firebase is not initialized
  // on Linux, so calling FirebaseFirestore.instance at construction time
  // throws "No Firebase App" and puts every dependent provider in error state.
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  final String deviceId;
  final String _projectId = 'smartsproutadmin';
  final String _apiKey = 'AIzaSyANlBxYFTPv0t7_RuGlRApt_aCtI8M-s44';

  /// Cached auth token for REST API calls on Linux
  String? _authToken;
  DateTime? _tokenExpiry;

  DataService(this.deviceId);

  String get _baseUrl =>
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/devices/$deviceId';

  // ═══════════════════════════════════════════════════════
  // Firebase Auth REST API - Anonymous Sign-In for Linux
  // ═══════════════════════════════════════════════════════

  /// Gets a valid auth token, refreshing if expired
  Future<String?> _getAuthToken() async {
    // Return cached token if still valid (with 5-min buffer)
    if (_authToken != null &&
        _tokenExpiry != null &&
        DateTime.now()
            .isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      return _authToken;
    }

    try {
      final url = Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'returnSecureToken': true}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _authToken = data['idToken'];
        // Tokens expire in 3600 seconds (1 hour)
        final expiresIn = int.tryParse(data['expiresIn'] ?? '3600') ?? 3600;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
        debugPrint('[REST_AUTH] Anonymous sign-in successful');
        return _authToken;
      } else {
        debugPrint('[REST_AUTH] Failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('[REST_AUTH] Error: $e');
    }
    return null;
  }

  /// Makes an authenticated GET request to Firestore REST API
  Future<http.Response> _authenticatedGet(String url) async {
    final token = await _getAuthToken();
    final headers = <String, String>{};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return http.get(Uri.parse(url), headers: headers);
  }

  /// Makes an authenticated POST request to Firestore REST API
  Future<http.Response> _authenticatedPost(
      String url, Map<String, dynamic> body) async {
    final token = await _getAuthToken();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return http.post(Uri.parse(url), headers: headers, body: json.encode(body));
  }

  // ═══════════════════════════════════════════════════════
  // Telemetry Stream
  // ═══════════════════════════════════════════════════════

  /// Streams the latest telemetry.
  ///
  /// - **Linux kiosk (Pi):** Reads the local `/tmp/smartsprout_telemetry.json`
  ///   cache file that `main.py` writes on every 3s sensor cycle.
  ///   This gives true live data with ZERO Firebase quota usage.
  ///   Falls back to offline state if the file is missing.
  ///
  /// - **Mobile (Android/iOS):** Uses a native Firestore real-time listener
  ///   (.snapshots()) for live cloud-pushed updates.
  Stream<SensorData> get telemetryStream {
    if (Platform.isLinux) {
      // Read the local telemetry cache written by main.py every 3 seconds.
      // No internet required — direct sensor data, zero quota cost.
      //
      // Uses a StreamController to emit IMMEDIATELY on first subscription
      // (avoiding a 3-second blank screen on kiosk startup), then repeats
      // every 3 seconds via a periodic Timer.
      late StreamController<SensorData> controller;
      Timer? timer;

      Future<SensorData> readCache() async {
        try {
          final file = File('/tmp/smartsprout_telemetry.json');
          if (!await file.exists()) {
            return const SensorData(systemStatus: 'offline');
          }
          final contents = await file.readAsString();
          final data = json.decode(contents) as Map<String, dynamic>;
          final parsed = SensorData.fromJson(data);
          if (parsed.isControllerDisconnected) {
            return parsed.copyWith(systemStatus: 'offline');
          }
          return parsed;
        } catch (e) {
          debugPrint('[LOCAL_TELEMETRY] Failed to read cache: $e');
          return const SensorData(systemStatus: 'offline');
        }
      }

      controller = StreamController<SensorData>(
        onListen: () async {
          // Emit immediately so the UI is populated on first frame.
          controller.add(await readCache());
          // Then poll every 3 seconds.
          timer = Timer.periodic(const Duration(seconds: 3), (_) async {
            if (!controller.isClosed) {
              controller.add(await readCache());
            }
          });
        },
        onCancel: () {
          timer?.cancel();
          controller.close();
        },
      );
      return controller.stream;
    } else {
      // Native Firebase on Mobile — real-time Firestore listener.
      return _firestore
          .collection('devices')
          .doc(deviceId)
          .snapshots()
          .map((snapshot) {
        if (!snapshot.exists || snapshot.data() == null) {
          return const SensorData(systemStatus: 'offline');
        }
        final data = SensorData.fromJson(snapshot.data()!);
        if (data.isControllerDisconnected) {
          return data.copyWith(systemStatus: 'offline');
        }
        return data;
      });
    }
  }



  // ═══════════════════════════════════════════════════════
  // Commands
  // ═══════════════════════════════════════════════════════

  /// Pushes a command to the "commands" subcollection.
  Future<void> sendCommand(Map<String, dynamic> payload) async {
    if (Platform.isLinux) {
      try {
        final commandPayload = {
          ...payload,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'processed': false,
        };
        final restPayload = _mapToRestFields(commandPayload);
        await _authenticatedPost(
            '$_baseUrl/commands?key=$_apiKey', {'fields': restPayload});
      } catch (e) {
        debugPrint('[REST_ERROR] sendCommand: $e');
      }
    } else {
      final commandPayload = {
        ...payload,
        'timestamp': FieldValue.serverTimestamp(),
        'processed': false,
      };
      await _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('commands')
          .add(commandPayload);
    }
  }

  /// Converts a standard Map into Firestore REST format.
  Map<String, dynamic> _mapToRestFields(Map<String, dynamic> data) {
    Map<String, dynamic> result = {};
    data.forEach((key, value) {
      if (value is String) {
        result[key] = {'stringValue': value};
      } else if (value is int) {
        result[key] = {'integerValue': value.toString()};
      } else if (value is double) {
        result[key] = {'doubleValue': value};
      } else if (value is bool) {
        result[key] = {'booleanValue': value};
      }
    });
    return result;
  }

  Future<void> forceWaterZone(int zone, {int durationSeconds = 10}) async {
    await sendCommand({
      'command': 'force_water',
      'zone': zone,
      'duration_seconds': durationSeconds,
    });
  }

  /// Dead-Man's Switch: writes a heartbeat timestamp while manual watering is active.
  /// The Pi monitors this — if stale >5s, it kills the pump immediately.
  Future<void> updateManualHeartbeat() async {
    if (Platform.isLinux) {
      try {
        final url =
            '$_baseUrl?updateMask.fieldPaths=manual_heartbeat&key=$_apiKey';
        final token = await _getAuthToken();
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null) headers['Authorization'] = 'Bearer $token';
        await http.patch(
          Uri.parse(url),
          headers: headers,
          body: json.encode({
            'fields': {
              'manual_heartbeat': {
                'timestampValue': DateTime.now().toUtc().toIso8601String(),
              }
            }
          }),
        );
      } catch (e) {
        debugPrint('[REST_ERROR] updateManualHeartbeat: $e');
      }
    } else {
      try {
        await _firestore.collection('devices').doc(deviceId).set(
          {'manual_heartbeat': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('[FIREBASE_ERROR] updateManualHeartbeat: $e');
      }
    }
  }

  /// Sends a FORCE_SYNC command to the Pi, triggering an immediate telemetry push.
  Future<void> forceSync() async {
    await sendCommand({
      'command': 'FORCE_SYNC',
      'requested_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Triggers dry calibration for a specific zone on the Pi.
  /// The probe must be in open air (0% reference) when this is called.
  /// Pi command handler: 'dry_calibrate' with optional 'zone' key.
  Future<void> runDryCalibration(int zone) async {
    await sendCommand({'command': 'dry_calibrate', 'zone': zone});
  }

  /// Triggers wet calibration for a specific zone on the Pi.
  /// The probe must be fully submerged in water (100% reference) when this is called.
  /// Pi command handler: 'run_wet_calibration' with optional 'zone' key.
  Future<void> runWetCalibration(int zone) async {
    await sendCommand({'command': 'run_wet_calibration', 'zone': zone});
  }

  /// Writes calibration offsets directly to the device document in Firestore.
  /// This ensures the database reflects the user's calibration immediately,
  /// without waiting for the Pi to process and push telemetry.
  Future<void> updateCalibrationInFirestore(int zone, double value) async {
    final bedKey = 'bed$zone';
    if (Platform.isLinux) {
      try {
        // REST API: PATCH the soil_offsets field
        final url =
            '$_baseUrl?updateMask.fieldPaths=soil_offsets.$bedKey&key=$_apiKey';
        final token = await _getAuthToken();
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null) headers['Authorization'] = 'Bearer $token';
        await http.patch(
          Uri.parse(url),
          headers: headers,
          body: json.encode({
            'fields': {
              'soil_offsets': {
                'mapValue': {
                  'fields': {
                    bedKey: {'doubleValue': value},
                  }
                }
              }
            }
          }),
        );
      } catch (e) {
        debugPrint('[REST_ERROR] updateCalibration: $e');
      }
    } else {
      // Native Firestore on mobile
      try {
        await _firestore.collection('devices').doc(deviceId).set(
          {
            'soil_offsets': {bedKey: value}
          },
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('[FIREBASE_ERROR] updateCalibration: $e');
      }
    }
  }

  /// Writes target moisture and max pump runtime to Firestore for a zone.
  Future<void> updateZoneTargets(int zone, double target, int timeout) async {
    final bedKey = 'bed$zone';
    if (Platform.isLinux) {
      try {
        final url =
            '$_baseUrl?updateMask.fieldPaths=target_moisture.$bedKey&updateMask.fieldPaths=max_pump_runtime.$bedKey&key=$_apiKey';
        final token = await _getAuthToken();
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null) headers['Authorization'] = 'Bearer $token';
        await http.patch(
          Uri.parse(url),
          headers: headers,
          body: json.encode({
            'fields': {
              'target_moisture': {
                'mapValue': {
                  'fields': {
                    bedKey: {'doubleValue': target},
                  }
                }
              },
              'max_pump_runtime': {
                'mapValue': {
                  'fields': {
                    bedKey: {'integerValue': timeout.toString()},
                  }
                }
              },
            }
          }),
        );
      } catch (e) {
        debugPrint('[REST_ERROR] updateZoneTargets: $e');
      }
    } else {
      try {
        await _firestore.collection('devices').doc(deviceId).set(
          {
            'target_moisture': {bedKey: target},
            'max_pump_runtime': {bedKey: timeout},
          },
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('[FIREBASE_ERROR] updateZoneTargets: $e');
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // Zones Collection for Plant Images
  // ═══════════════════════════════════════════════════════

  /// Fetches the plant image filename for [zoneId] from Firestore.
  ///
  /// Linux path: uses an async* generator so the first value is emitted
  /// immediately on subscribe (no 10-second delay), then re-polls every 10s.
  /// Mobile/Windows path: uses a real-time Firestore snapshot stream.
  Stream<String?> zoneImageStream(String zoneId) {
    if (Platform.isLinux) {
      return _linuxZoneImageStream(zoneId);
    } else {
      return _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('zones')
          .doc(zoneId)
          .snapshots()
          .map((doc) {
        return doc.data()?['plant_image_name'] as String?;
      });
    }
  }

  /// Linux-specific plant image stream.
  /// Uses a resilient caching loop to prevent UI blinking when offline.
  Stream<String?> _linuxZoneImageStream(String zoneId) async* {
    String? lastYielded;
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'cached_image_$zoneId';

    while (true) {
      // 1. Check local fast-memory cache. This allows the UI to update
      // immediately when 'updateZoneImage' writes to SharedPreferences.
      final cached = prefs.getString(cacheKey);
      if (cached != lastYielded) {
        lastYielded = cached;
        yield cached;
      }

      // 2. Poll Firebase REST API to get updates from the mobile app
      bool networkSuccess = false;
      String? networkResult;

      try {
        final url = '$_baseUrl/zones/$zoneId?key=$_apiKey';
        final response = await _authenticatedGet(url);
        if (response.statusCode == 200) {
          networkSuccess = true;
          final data = json.decode(response.body);
          if (data['fields'] != null &&
              data['fields']['plant_image_name'] != null) {
            networkResult =
                data['fields']['plant_image_name']['stringValue'] as String?;
          }
        } else if (response.statusCode == 404) {
          networkSuccess = true; // Document doesn't exist yet, valid state.
        }
      } catch (e) {
        // Silently skip. The node might be offline, but the UI won't blink
        // because we don't yield a null result on a network exception.
      }

      // 3. If the network gave us a *different* value than cache,
      // update our ground truth and yield it.
      if (networkSuccess && networkResult != lastYielded) {
        lastYielded = networkResult;
        yield networkResult;

        if (networkResult != null && networkResult.isNotEmpty) {
          await prefs.setString(cacheKey, networkResult);
        } else {
          await prefs.remove(cacheKey);
        }
      }

      // 4. Poll every 2 seconds. SharedPreferences is in-memory, so reading
      // it is extremely lightweight and ensures the kiosk responds instantly.
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> updateZoneImage(String zoneId, String imageName) async {
    if (Platform.isLinux) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = 'cached_image_$zoneId';
        if (imageName.isEmpty) {
          await prefs.remove(cacheKey);
        } else {
          await prefs.setString(cacheKey, imageName);
        }

        final url =
            '$_baseUrl/zones/$zoneId?updateMask.fieldPaths=plant_image_name&key=$_apiKey';
        final token = await _getAuthToken();
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (token != null) headers['Authorization'] = 'Bearer $token';
        await http.patch(
          Uri.parse(url),
          headers: headers,
          body: json.encode({
            'name':
                'projects/$_projectId/databases/(default)/documents/devices/$deviceId/zones/$zoneId',
            'fields': {
              'plant_image_name': {'stringValue': imageName}
            }
          }),
        );
      } catch (e) {
        debugPrint('[REST_ERROR] updateZoneImage: $e');
      }
    } else {
      try {
        await _firestore
            .collection('devices')
            .doc(deviceId)
            .collection('zones')
            .doc(zoneId)
            .set(
          {'plant_image_name': imageName},
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('[FIREBASE_ERROR] updateZoneImage: $e');
      }
    }
  }

  Future<void> emergencyStop() async {
    await sendCommand({
      'command': 'stop_all',
    });
  }

  Future<void> setWateringMode(String mode,
      {String? strategy,
      int? timerHour,
      int? timerMinute,
      List<int>? enabledZones}) async {
    final payload = <String, dynamic>{
      'command': 'set_mode',
      'mode': mode,
    };
    if (strategy != null) payload['strategy'] = strategy;
    if (timerHour != null) payload['timer_hour'] = timerHour;
    if (timerMinute != null) payload['timer_minute'] = timerMinute;
    // enabled_zones: list of zone numbers (1-indexed) that should participate.
    // If omitted, the Pi defaults to all zones enabled.
    if (enabledZones != null) payload['enabled_zones'] = enabledZones;

    await sendCommand(payload);
  }

  // ═══════════════════════════════════════════════════════
  // Analytics
  // ═══════════════════════════════════════════════════════

  Future<List<DailyAnalytics>> fetchWeeklyAnalytics() async {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));
    final cutoffSeconds = cutoff.millisecondsSinceEpoch ~/ 1000;

    if (Platform.isLinux) {
      return List.generate(
          7, (i) => DailyAnalytics(dayIndex: i, avgMoisture: 0, avgTemp: 0));
    }

    try {
      // PHASE 1 FIX: Hard cap at 500 documents to prevent unbounded reads.
      // The Pi writes to telemetry only on Eco-Mode (every 30 min), so
      // 500 docs = ~10+ days of data — well beyond the 7-day window needed.
      final snapshot = await _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('telemetry')
          .where('timestamp', isGreaterThanOrEqualTo: cutoffSeconds)
          .orderBy('timestamp', descending: false)
          .limit(500)
          .get();

      Map<int, List<Map<String, dynamic>>> grouped = {
        for (int i = 0; i < 7; i++) i: []
      };

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final ts = data['timestamp'] as int?;
        if (ts == null) continue;

        final date = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        final dayDiff = date.difference(cutoff).inDays;

        if (dayDiff >= 0 && dayDiff < 7) {
          grouped[dayDiff]!.add(data);
        }
      }

      List<DailyAnalytics> results = [];

      // Safe helper: Firestore returns int for whole numbers (e.g. -1, 0),
      // never cast directly as double — always go through num first.
      double safeDouble(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

      for (int i = 0; i < 7; i++) {
        final docs = grouped[i]!;
        if (docs.isEmpty) {
          results.add(DailyAnalytics(
              dayIndex: i,
              avgMoisture: 0,
              avgTemp: 0,
              hasData: false)); // No telemetry docs for this day
        } else {
          double totalMoisture = 0.0;
          double totalTemp = 0.0;
          int validDocs = 0;
          for (var d in docs) {
            try {
              // ── soil_moisture is written by the Pi as Map<String, dynamic>
              // e.g. {"bed1": 45.2, "bed2": 51, "bed3": 38.6}
              // Firestore returns int for whole numbers, so we always cast
              // through num? → toDouble() to avoid the combine-type mismatch.
              final rawSoil = d['soil_moisture'];
              List<double> soil;
              if (rawSoil is Map) {
                soil = rawSoil.values
                    .map<double>((v) => safeDouble(v))
                    .toList();
              } else if (rawSoil is List) {
                soil = rawSoil.map<double>((v) => safeDouble(v)).toList();
              } else {
                soil = [0.0, 0.0, 0.0];
              }

              final avgSoil = soil.isEmpty
                  ? 0.0
                  : soil.reduce((a, b) => a + b) / soil.length;

              totalMoisture += avgSoil;
              totalTemp += safeDouble(d['temperature']);
              validDocs++;
            } on TypeError catch (te) {
              debugPrint(
                  '[ANALYTICS_PARSE] TypeError on doc data — raw payload: $d');
              debugPrint('[ANALYTICS_PARSE] TypeError detail: $te');
            }
          }
          results.add(DailyAnalytics(
              dayIndex: i,
              avgMoisture: validDocs == 0 ? 0.0 : totalMoisture / validDocs,
              avgTemp: validDocs == 0 ? 0.0 : totalTemp / validDocs,
              hasData: validDocs > 0)); // false if all docs threw parse errors
        }
      }
      return results;
    } catch (e) {
      debugPrint('[FIREBASE_SERVICE] Failed to fetch analytics: $e');
      return List.generate(
          7, (i) => DailyAnalytics(dayIndex: i, avgMoisture: 0, avgTemp: 0));
    }
  }
}

final dataServiceProvider = Provider<DataService?>((ref) {
  final authState = ref.watch(authProvider);
  if (authState.deviceId != null) {
    return DataService(authState.deviceId!);
  }
  return null;
});
