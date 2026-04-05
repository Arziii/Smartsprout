import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/models/sensor_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../presentation/providers/auth_provider.dart';
import '../../data/models/analytics_model.dart';

class DataService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
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

  /// Streams the latest telemetry from the device's main document.
  Stream<SensorData> get telemetryStream {
    if (Platform.isLinux) {
      // PHASE 2 FIX: Increased from 5s → 30s to reduce REST API reads.
      // At 5s: 720 reads/hr (17,280/day) just from the Linux kiosk.
      // At 30s: 120 reads/hr (2,880/day) — 83% reduction.
      // The 30s interval still provides near-real-time sensor feedback.
      return Stream.periodic(const Duration(seconds: 30)).asyncMap((_) async {
        try {
          final response = await _authenticatedGet('$_baseUrl?key=$_apiKey');
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            return _parseRestData(data);
          } else {
            debugPrint(
                '[REST_ERROR] status ${response.statusCode}: ${response.body}');
          }
        } catch (e) {
          debugPrint('[REST_ERROR] fetch telemetry: $e');
        }
        return const SensorData(systemStatus: 'offline');
      });
    } else {
      // Native Firebase on Mobile
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

  /// Parses Firestore REST JSON payload into SensorData
  SensorData _parseRestData(Map<String, dynamic> doc) {
    if (!doc.containsKey('fields')) {
      return const SensorData(systemStatus: 'offline');
    }
    final fields = doc['fields'] as Map<String, dynamic>;

    dynamic getField(String key) {
      if (!fields.containsKey(key)) return null;
      final val = fields[key];
      if (val.containsKey('stringValue')) return val['stringValue'];
      if (val.containsKey('doubleValue')) return val['doubleValue'];
      if (val.containsKey('integerValue')) {
        return double.tryParse(val['integerValue'].toString());
      }
      if (val.containsKey('booleanValue')) return val['booleanValue'];

      if (val.containsKey('arrayValue')) {
        final arr = val['arrayValue']['values'] as List?;
        if (arr == null) return [];
        return arr.map((e) {
          if (e.containsKey('doubleValue')) return e['doubleValue'];
          if (e.containsKey('integerValue')) {
            return double.tryParse(e['integerValue'].toString()) ?? 0.0;
          }
          if (e.containsKey('stringValue')) return e['stringValue'];
          return 0.0;
        }).toList();
      }

      // Handle Firestore REST mapValue (e.g., soil_moisture: {bed1: ..., bed2: ..., bed3: ...})
      if (val.containsKey('mapValue')) {
        final mapFields = val['mapValue']['fields'] as Map<String, dynamic>?;
        if (mapFields == null) return {};
        final result = <String, dynamic>{};
        mapFields.forEach((k, v) {
          if (v is Map) {
            if (v.containsKey('doubleValue')) {
              result[k] = v['doubleValue'];
            } else if (v.containsKey('integerValue')) {
              result[k] = double.tryParse(v['integerValue'].toString()) ?? 0.0;
            } else if (v.containsKey('stringValue')) {
              result[k] = v['stringValue'];
            }
          }
        });
        return result;
      }
      return null;
    }

    final soilCal = getField('soil_moisture') as List?;
    final soilRaw = getField('soil_moisture_raw') as List?;
    final soilOffsets = getField('soil_offsets') as List?;
    final alertsRaw = getField('alerts') as List?;

    // Parse timestamp fields for heartbeat
    dynamic lastHb;
    if (fields.containsKey('last_heartbeat')) {
      final hbVal = fields['last_heartbeat'];
      if (hbVal.containsKey('timestampValue')) {
        final ts = DateTime.tryParse(hbVal['timestampValue']);
        if (ts != null) lastHb = ts;
      }
    }

    Map<String, dynamic> mapped = {
      'system_status': getField('system_status') ?? 'offline',
      'tank_level': getField('tank_level') ?? 0.0,
      'pump_locked': getField('pump_locked') ?? false,
      'pump_status_zone1': getField('pump_status_zone1') ?? false,
      'pump_status_zone2': getField('pump_status_zone2') ?? false,
      'pump_status_zone3': getField('pump_status_zone3') ?? false,
      'temperature': getField('temperature') ?? 0.0,
      'humidity': getField('humidity') ?? 0.0,
      'soil_moisture': soilCal,
      'soil_moisture_raw': soilRaw,
      'soil_offsets': soilOffsets,
      'start_threshold': getField('start_threshold'),
      'target_moisture': getField('target_moisture'),
      'max_pump_runtime': getField('max_pump_runtime'),
      'alerts': alertsRaw,
      'last_heartbeat': lastHb,
    };
    return SensorData.fromJson(mapped);
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
  Stream<String?> zoneImageStream(String zoneId) {
    if (Platform.isLinux) {
      return Stream.periodic(const Duration(seconds: 10)).asyncMap((_) async {
        try {
          final url = '$_baseUrl/zones/$zoneId?key=$_apiKey';
          final response = await _authenticatedGet(url);
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['fields'] != null &&
                data['fields']['plant_image_name'] != null) {
              return data['fields']['plant_image_name']['stringValue'];
            }
          }
        } catch (_) {}
        return null;
      });
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

  Future<void> updateZoneImage(String zoneId, String imageName) async {
    if (Platform.isLinux) {
      try {
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
      {String? strategy, int? timerHour, int? timerMinute}) async {
    final payload = <String, dynamic>{
      'command': 'set_mode',
      'mode': mode,
    };
    if (strategy != null) payload['strategy'] = strategy;
    if (timerHour != null) payload['timer_hour'] = timerHour;
    if (timerMinute != null) payload['timer_minute'] = timerMinute;

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
