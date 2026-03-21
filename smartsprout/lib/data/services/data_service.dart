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

  String get _baseUrl => 'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/devices/$deviceId';

  // ═══════════════════════════════════════════════════════
  // Firebase Auth REST API - Anonymous Sign-In for Linux
  // ═══════════════════════════════════════════════════════

  /// Gets a valid auth token, refreshing if expired
  Future<String?> _getAuthToken() async {
    // Return cached token if still valid (with 5-min buffer)
    if (_authToken != null && _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      return _authToken;
    }

    try {
      final url = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey'
      );
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
  Future<http.Response> _authenticatedPost(String url, Map<String, dynamic> body) async {
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
      // Poll REST API every 5 seconds on Linux
      return Stream.periodic(const Duration(seconds: 5)).asyncMap((_) async {
        try {
          final response = await _authenticatedGet('$_baseUrl?key=$_apiKey');
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            return _parseRestData(data);
          } else {
            debugPrint('[REST_ERROR] status ${response.statusCode}: ${response.body}');
          }
        } catch (e) {
          debugPrint('[REST_ERROR] fetch telemetry: $e');
        }
        return const SensorData(systemStatus: 'offline');
      });
    } else {
      // Native Firebase on Mobile
      return _firestore.collection('devices').doc(deviceId).snapshots().map((snapshot) {
        if (!snapshot.exists || snapshot.data() == null) {
          return const SensorData(systemStatus: 'offline');
        }
        return SensorData.fromJson(snapshot.data()!);
      });
    }
  }

  /// Parses Firestore REST JSON payload into SensorData
  SensorData _parseRestData(Map<String, dynamic> doc) {
    if (!doc.containsKey('fields')) return const SensorData(systemStatus: 'offline');
    final fields = doc['fields'] as Map<String, dynamic>;
    
    dynamic getField(String key) {
      if (!fields.containsKey(key)) return null;
      final val = fields[key];
      if (val.containsKey('stringValue')) return val['stringValue'];
      if (val.containsKey('doubleValue')) return val['doubleValue'];
      if (val.containsKey('integerValue')) return double.tryParse(val['integerValue'].toString());
      if (val.containsKey('booleanValue')) return val['booleanValue'];
      
      if (val.containsKey('arrayValue')) {
         final arr = val['arrayValue']['values'] as List?;
         if (arr == null) return [];
         return arr.map((e) {
            if (e.containsKey('doubleValue')) return e['doubleValue'];
            if (e.containsKey('integerValue')) return double.tryParse(e['integerValue'].toString()) ?? 0.0;
            if (e.containsKey('stringValue')) return e['stringValue'];
            return 0.0;
         }).toList();
      }
      return null;
    }

    final soilRaw = getField('soil_moisture') as List?;
    final alertsRaw = getField('alerts') as List?;

    Map<String, dynamic> mapped = {
      'system_status': getField('system_status') ?? 'offline',
      'tank_level': getField('tank_level') ?? 0.0,
      'pump_locked': getField('pump_locked') ?? false,
      'temperature': getField('temperature') ?? 0.0,
      'humidity': getField('humidity') ?? 0.0,
      'soil_moisture': soilRaw,
      'alerts': alertsRaw,
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
        await _authenticatedPost('$_baseUrl/commands?key=$_apiKey', {'fields': restPayload});
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
      if (value is String) result[key] = {'stringValue': value};
      else if (value is int) result[key] = {'integerValue': value.toString()};
      else if (value is double) result[key] = {'doubleValue': value};
      else if (value is bool) result[key] = {'booleanValue': value};
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

  Future<void> emergencyStop() async {
    await sendCommand({
      'command': 'stop_all',
    });
  }

  Future<void> setWateringMode(String mode, {String? strategy, int? timerHour, int? timerMinute}) async {
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
    final cutoff = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final cutoffSeconds = cutoff.millisecondsSinceEpoch ~/ 1000;

    if (Platform.isLinux) {
        return List.generate(7, (i) => DailyAnalytics(dayIndex: i, avgMoisture: 0, avgTemp: 0));
    }

    try {
      final snapshot = await _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('telemetry')
          .where('timestamp', isGreaterThanOrEqualTo: cutoffSeconds)
          .orderBy('timestamp', descending: false)
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
      for (int i = 0; i < 7; i++) {
        final docs = grouped[i]!;
        if (docs.isEmpty) {
          results.add(DailyAnalytics(dayIndex: i, avgMoisture: 0, avgTemp: 0));
        } else {
          double totalMoisture = 0;
          double totalTemp = 0;
          for (var d in docs) {
            final soil = List<num>.from(d['soil_moisture'] ?? [0,0,0]);
            final avgSoil = soil.isEmpty ? 0 : soil.reduce((a, b) => a + b) / soil.length;
            totalMoisture += avgSoil;
            totalTemp += (d['temperature'] ?? 0.0);
          }
          results.add(DailyAnalytics(
            dayIndex: i, 
            avgMoisture: totalMoisture / docs.length, 
            avgTemp: totalTemp / docs.length
          ));
        }
      }
      return results;
    } catch (e) {
      debugPrint('[FIREBASE_SERVICE] Failed to fetch analytics: $e');
      return List.generate(7, (i) => DailyAnalytics(dayIndex: i, avgMoisture: 0, avgTemp: 0));
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
