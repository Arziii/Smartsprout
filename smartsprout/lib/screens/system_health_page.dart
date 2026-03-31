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
      backgroundColor: const Color(0xFFE8F1F2),
      appBar: AppBar(
        title: Text(
          "System Health",
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F2027),
          ),
        ),
        backgroundColor: const Color(0xFFE8F1F2),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F2027)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
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
                statusColor: isOffline ? Colors.grey : (sensorData.hasSensorFault ? Colors.redAccent : const Color(0xFF2BCC71)),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.3), width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(width: 16),
          Text(
            text,
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: color,
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
        color: Colors.white.withOpacity(isLiteMode ? 1.0 : 0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: isLiteMode ? null : [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A6164).withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: const Color(0xFF4A6164), size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F2027),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF4A6164),
              fontWeight: FontWeight.w500,
              height: 1.4,
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
        color: Colors.white.withOpacity(isLiteMode ? 1.0 : 0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: isLiteMode ? null : [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A6164).withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.grass_rounded, color: Color(0xFF4A6164), size: 22),
              ),
              const SizedBox(width: 16),
              Text(
                "Zone Breakdown",
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F2027),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildZoneRow("Zone 1 (Left)", sensorData, 0),
          const Divider(height: 24, thickness: 1, color: Color(0xFFE8F1F2)),
          _buildZoneRow("Zone 2 (Center)", sensorData, 1),
          const Divider(height: 24, thickness: 1, color: Color(0xFFE8F1F2)),
          _buildZoneRow("Zone 3 (Right)", sensorData, 2),
        ],
      ),
    );
  }

  Widget _buildZoneRow(String title, sensorData, int index) {
    double moisture = sensorData.soilMoisture.length > index ? sensorData.soilMoisture[index] : 0.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF4A6164),
            fontWeight: FontWeight.w700,
          ),
        ),
        Row(
          children: [
            Text(
              sensorData.isOffline ? "Current: --%" : "Current: ${moisture.toStringAsFixed(0)}%",
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF0F2027),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
