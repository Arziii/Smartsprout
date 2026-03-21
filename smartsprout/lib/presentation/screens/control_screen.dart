import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/sensor_provider.dart';
import '../../data/services/data_service.dart';

class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen>
    with SingleTickerProviderStateMixin {
  String _mode = 'manual';
  String _autoStrategy = 'sensor';
  TimeOfDay _autoTime = const TimeOfDay(hour: 8, minute: 0);
  late AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sensorData = ref.watch(sensorDataProvider);
    final notifier = ref.read(sensorDataProvider.notifier);
    // On Linux (Pi), always treat as connected — the Pi IS the system.
    final isConnected = Platform.isLinux || !sensorData.isOffline;
    final pumpLocked = sensorData.pumpLocked;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Irrigation Control',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F2027),
              letterSpacing: -0.5,
            )),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // ── Background ──
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE0ECE9), Color(0xFFB4CDCA)],
                ),
              ),
            ),
          ),
          _buildBlob(top: -50, right: -100, size: 300, color: const Color(0xFF2BCC71).withOpacity(0.15)),
          _buildBlob(bottom: 100, left: -100, size: 400, color: Colors.blue.withOpacity(0.1)),

          // ── Content ──
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   _buildAnimatedItem(0, Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: isConnected ? const Color(0xFF2BCC71).withOpacity(0.1) : Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, 
                          color: isConnected ? const Color(0xFF2BCC71) : Colors.redAccent, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          isConnected ? "System online and connected" : "System offline - commands disabled",
                          style: GoogleFonts.outfit(
                            color: isConnected ? const Color(0xFF2BCC71) : Colors.redAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 24),

                  // Mode Selector Card
                  _buildAnimatedItem(1, _buildGlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Operation Mode',
                            style: GoogleFonts.outfit(
                                fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F2027))),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: SegmentedButton<String>(
                            style: SegmentedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              selectedForegroundColor: Colors.white,
                              selectedBackgroundColor: const Color(0xFF0F2027),
                              textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            segments: const [
                              ButtonSegment(
                                  value: 'manual',
                                  label: Text('Manual'),
                                  icon: Icon(Icons.touch_app_rounded)),
                              ButtonSegment(
                                  value: 'auto',
                                  label: Text('Auto'),
                                  icon: Icon(Icons.schedule_rounded)),
                            ],
                            selected: {_mode},
                            showSelectedIcon: false,
                            onSelectionChanged: (sel) =>
                                setState(() => _mode = sel.first),
                          ),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 20),

                  // Per-Zone Force Water Controls
                  if (_mode == 'manual') ...[
                    _buildAnimatedItem(2, _buildGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Manual Override",
                              style: GoogleFonts.outfit(
                                  fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F2027))),
                          const SizedBox(height: 12),
                          if (pumpLocked)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.redAccent
                                        .withOpacity(0.4)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.lock_rounded, color: Colors.redAccent),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "Pump is LOCKED — tank level critically low.",
                                      style: GoogleFonts.outfit(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          _buildZoneButton(1, "Zone 1 (Left)",
                              sensorData.soilMoisture.isNotEmpty ? sensorData.soilMoisture[0] : 0, notifier,
                              disabled: pumpLocked || !isConnected),
                          const SizedBox(height: 12),
                          _buildZoneButton(
                              2,
                              "Zone 2 (Center)",
                              sensorData.soilMoisture.length > 1
                                  ? sensorData.soilMoisture[1]
                                  : 0,
                              notifier,
                              disabled: pumpLocked || !isConnected),
                          const SizedBox(height: 12),
                          _buildZoneButton(
                              3,
                              "Zone 3 (Right)",
                              sensorData.soilMoisture.length > 2
                                  ? sensorData.soilMoisture[2]
                                  : 0,
                              notifier,
                              disabled: pumpLocked || !isConnected),
                        ],
                      ),
                    )),
                    const SizedBox(height: 24),
                  ],

                  if (_mode == 'auto') ...[
                    _buildAnimatedItem(2, _buildGlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text("Automatic Strategy",
                              style: GoogleFonts.outfit(
                                  fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF0F2027))),
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: SegmentedButton<String>(
                              style: SegmentedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                selectedForegroundColor: Colors.white,
                                selectedBackgroundColor: const Color(0xFF29B6F6),
                                textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide.none,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: 'sensor',
                                  label: Text('Sensor Target'),
                                  icon: Icon(Icons.water_drop_rounded),
                                ),
                                ButtonSegment(
                                  value: 'timer',
                                  label: Text('Daily Timer'),
                                  icon: Icon(Icons.access_time_filled_rounded),
                                ),
                              ],
                              selected: {_autoStrategy},
                              showSelectedIcon: false,
                              onSelectionChanged: (sel) => setState(() => _autoStrategy = sel.first),
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          if (_autoStrategy == 'sensor') ...[
                             Row(
                               children: [
                                 Container(
                                   padding: const EdgeInsets.all(12),
                                   decoration: BoxDecoration(color: const Color(0xFF29B6F6).withOpacity(0.15), shape: BoxShape.circle),
                                   child: const Icon(Icons.water_drop_rounded, color: Color(0xFF29B6F6)),
                                 ),
                                 const SizedBox(width: 16),
                                 Expanded(
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       Text("Sensor Thresholds", style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF0F2027))),
                                       Text("Waters automatically when soil moisture is low across any zone.", style: GoogleFonts.outfit(color: const Color(0xFF4A6164), fontSize: 13, fontWeight: FontWeight.w500)),
                                     ]
                                   )
                                 )
                               ]
                             )
                          ] else ...[
                             Row(
                               children: [
                                 Container(
                                   padding: const EdgeInsets.all(12),
                                   decoration: BoxDecoration(color: const Color(0xFF29B6F6).withOpacity(0.15), shape: BoxShape.circle),
                                   child: const Icon(Icons.access_time_filled_rounded, color: Color(0xFF29B6F6)),
                                 ),
                                 const SizedBox(width: 16),
                                 Expanded(
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       Text("Daily Schedule", style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF0F2027))),
                                       Text("Waters all zones every day at the time selected below.", style: GoogleFonts.outfit(color: const Color(0xFF4A6164), fontSize: 13, fontWeight: FontWeight.w500)),
                                     ]
                                   )
                                 )
                               ]
                             ),
                             const SizedBox(height: 16),
                             InkWell(
                               onTap: () async {
                                 final time = await showTimePicker(context: context, initialTime: _autoTime);
                                 if (time != null) setState(() => _autoTime = time);
                               },
                               borderRadius: BorderRadius.circular(12),
                               child: Container(
                                 padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                                 decoration: BoxDecoration(
                                   color: Colors.white.withOpacity(0.8),
                                   borderRadius: BorderRadius.circular(12),
                                   border: Border.all(color: const Color(0xFF29B6F6).withOpacity(0.3)),
                                 ),
                                 child: Row(
                                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                   children: [
                                     Text("Execution Time", style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 15, color: const Color(0xFF0F2027))),
                                     Text(_autoTime.format(context), style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18, color: const Color(0xFF29B6F6))),
                                   ]
                                 )
                               )
                             )
                          ],

                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: (!isConnected || pumpLocked)
                                ? null
                                : () {
                                    HapticFeedback.heavyImpact();
                                    ref.read(dataServiceProvider)?.setWateringMode(
                                      'auto',
                                      strategy: _autoStrategy,
                                      timerHour: _autoTime.hour,
                                      timerMinute: _autoTime.minute,
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Auto Watering Mode Activated', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                                        backgroundColor: const Color(0xFF2BCC71),
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.check_circle_rounded),
                            label: Text("Activate Auto Mode",
                                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2BCC71),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    )),
                    const SizedBox(height: 24),
                  ],

                  // Emergency Stop
                  _buildAnimatedItem(3, Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        )
                      ]
                    ),
                    child: SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: isConnected
                            ? () {
                                HapticFeedback.heavyImpact();
                                notifier.emergencyStop();
                              }
                            : null,
                        icon: const Icon(Icons.power_settings_new_rounded, size: 24),
                        label: Text("EMERGENCY STOP",
                            style: GoogleFonts.outfit(
                                fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  )),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneButton(
      int zone, String label, double moisture, SensorDataNotifier notifier,
      {bool disabled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF29B6F6).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.water_drop_rounded, color: Color(0xFF29B6F6), size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700, fontSize: 16, color: const Color(0xFF0F2027))),
              Text("Moisture: ${moisture.toStringAsFixed(0)}%",
                  style: GoogleFonts.outfit(
                      color: const Color(0xFF4A6164),
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: disabled
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    notifier.forceWater(zone);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2BCC71),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              elevation: 0,
            ),
            child: Text("Water Now",
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildBlob({double? top, double? left, double? right, double? bottom, required double size, required Color color}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  Widget _buildAnimatedItem(int index, Widget child) {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, _) {
        final start = index * 0.1;
        final curve = CurvedAnimation(
          parent: _entranceController,
          curve: Interval(start.clamp(0.0, 1.0), (start + 0.6).clamp(0.0, 1.0), curve: Curves.easeOutQuart),
        );
        return Opacity(
          opacity: curve.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - curve.value)),
            child: child,
          ),
        );
      },
    );
  }
}
