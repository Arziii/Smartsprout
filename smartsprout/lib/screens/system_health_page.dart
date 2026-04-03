import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/utils/platform_utils.dart';
import '../presentation/providers/sensor_provider.dart';

class SystemHealthPage extends ConsumerWidget {
  const SystemHealthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sensorData = ref.watch(sensorDataProvider);
    
    // Overall Status
    final isHealthy = sensorData.isHealthy;
    final isOffline = sensorData.isOffline;
    
    Color overallColor = isOffline ? Colors.grey : (isHealthy ? const Color(0xFF2BCC71) : Colors.redAccent);
    IconData overallIcon = isOffline ? Icons.wifi_off_rounded : (isHealthy ? Icons.verified_rounded : Icons.report_problem_rounded);
    String overallText = isOffline ? "System Offline" : (isHealthy ? "System Healthy" : "Issues Detected");

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "System Health",
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F2027),
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F2027), size: 20),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: Stack(
        children: [
          // ── Gradient Background ──
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFE0ECE9),
                    Color(0xFFB4CDCA),
                  ],
                ),
              ),
            ),
          ),
          // Blobs
          Positioned(
            top: -100, right: -50,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(color: const Color(0xFF2BCC71).withValues(alpha: 0.15), shape: BoxShape.circle),
            ),
          ),
          Positioned(
            bottom: 100, left: -100,
            child: Container(
              width: 400, height: 400,
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              // ── OVERALL STATUS BANNER ──
              _buildStatusBanner(overallText, overallIcon, overallColor),
              const SizedBox(height: 24),

              // ── CONTROLLER CONNECTION ──
              _buildDetailCard(
                title: "Controller Connection",
                icon: Icons.router_rounded,
                statusText: isOffline ? "Offline" : "Online",
                statusColor: isOffline ? Colors.redAccent : const Color(0xFF2BCC71),
                description: isOffline 
                    ? "The Raspberry Pi controller cannot be reached over the network."
                    : "Securely connected and synchronizing data.",
              ),
              const SizedBox(height: 16),

              // ── WATER RESERVOIR ──
              _buildDetailCard(
                title: "Water Reservoir",
                icon: Icons.water_drop_rounded,
                statusText: isOffline
                    ? "Unknown"
                    : sensorData.isTankFault
                        ? "Sensor Fault"
                        : (sensorData.isTankLow ? "Low Water" : "Sufficient"),
                statusColor: isOffline
                    ? Colors.grey
                    : sensorData.isTankFault
                        ? Colors.orange
                        : (sensorData.isTankLow ? Colors.redAccent : const Color(0xFF2BCC71)),
                description: isOffline
                    ? "Reservoir level unavailable while disconnected."
                    : sensorData.isTankFault
                        ? "The XKC non-contact water level sensor is not responding. Check wiring on GPIO pin and verify sensor power. Pump is locked for safety."
                        : (sensorData.isTankLow
                            ? "The XKC sensor reports the reservoir is LOW. Refill the water tank to restore automatic irrigation. Pump is locked until water is detected."
                            : "The XKC sensor reports the reservoir is at a sufficient level (HIGH). Irrigation is permitted."),
              ),
              const SizedBox(height: 16),

              // ── SENSOR INTEGRITY ──
              _buildDetailCard(
                title: "Sensor Integrity",
                icon: Icons.memory_rounded,
                statusText: isOffline ? "Status Unknown" : (sensorData.hasSensorFault ? "Fault Detected" : "All Systems Nominal"),
                statusColor: isOffline ? Colors.grey : (sensorData.hasSensorFault ? Colors.orange : const Color(0xFF2BCC71)),
                description: isOffline ? "Sensor data unavailable while disconnected." : _getSensorDescription(sensorData),
              ),
              const SizedBox(height: 16),

              // ── ZONE BREAKDOWN ──
              _buildZoneBreakdownCard(sensorData),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }

  String _getSensorDescription(sensorData) {
    if (sensorData.hasSensorFault) {
      if (sensorData.alerts.contains('dht22_fault')) {
        return "Air temperature/humidity sensor (DHT22) fault detected.";
      }
      if (sensorData.alerts.contains('soil_sensor_fault')) {
        return "One or more soil moisture sensors are reporting errors.";
      }
      return "Unknown sensor hardware fault.";
    }
    return "Air sensor and all soil moisture sensors are reporting correctly.";
  }

  Widget _buildStatusBanner(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: isLiteMode ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F2027),
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard({
    required String title,
    required IconData icon,
    required String statusText,
    required Color statusColor,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isLiteMode ? 1.0 : 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: isLiteMode ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF29B6F6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF0277BD), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F2027),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1),
                ),
                child: Text(
                  statusText,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: Colors.grey.shade500),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4A6164),
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneBreakdownCard(sensorData) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isLiteMode ? 1.0 : 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: isLiteMode ? null : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A6164).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.grass_rounded, color: Color(0xFF4A6164), size: 24),
              ),
              const SizedBox(width: 16),
              Text(
                "Zone Breakdown",
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F2027),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildZoneRow("Zone 1 (Left)", sensorData, 0),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Divider(height: 24, thickness: 1, color: Color(0xFFE8F1F2)),
          ),
          _buildZoneRow("Zone 2 (Center)", sensorData, 1),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Divider(height: 24, thickness: 1, color: Color(0xFFE8F1F2)),
          ),
          _buildZoneRow("Zone 3 (Right)", sensorData, 2),
        ],
      ),
    );
  }

  Widget _buildZoneRow(String title, sensorData, int index) {
    double moisture = sensorData.soilMoisture.length > index ? sensorData.soilMoisture[index] : 0.0;
    bool hasFault = sensorData.hasBedFault(index);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF0F2027),
            fontWeight: FontWeight.w700,
          ),
        ),
        Row(
          children: [
             if (hasFault)
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                 decoration: BoxDecoration(
                   color: Colors.orange.withValues(alpha: 0.1),
                   borderRadius: BorderRadius.circular(10),
                   border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                 ),
                 child: const Text(
                   "FAULT",
                   style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.orange),
                 ),
               )
             else
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                 decoration: BoxDecoration(
                   color: const Color(0xFFF5F7F8),
                   borderRadius: BorderRadius.circular(10),
                 ),
                 child: Text(
                   sensorData.isOffline ? "--%" : "${moisture.toStringAsFixed(0)}%",
                   style: const TextStyle(
                     fontSize: 14,
                     color: Color(0xFF0277BD),
                     fontWeight: FontWeight.w800,
                   ),
                 ),
               ),
          ],
        ),
      ],
    );
  }
}
