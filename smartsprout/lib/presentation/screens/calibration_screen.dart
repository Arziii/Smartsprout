import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/sensor_provider.dart';
import '../../data/services/firebase_service.dart';
class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen>
    with SingleTickerProviderStateMixin {
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
    final isConnected = !sensorData.isOffline;
    final moistureData = sensorData.soilMoisture;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text('Calibration',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F2027),
              letterSpacing: -0.5,
            )),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF0F2027), size: 20),
          onPressed: () => context.canPop() ? context.pop() : context.pushReplacement('/settings'),
        ),
      ),
      body: Stack(
        children: [
          // Background Gradient
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
          
          // Organic Blob shapes
          Positioned(
            top: -50,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2BCC71).withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(0.1),
              ),
            ),
          ),

          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                _buildInfoBanner(),
                const SizedBox(height: 25),
                _buildSectionHeader('Beds Offset'),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Column(
                        children: [
                          for (int i = 0; i < 3; i++) ...[
                            _buildAnimatedItem(
                              i,
                              _buildCalibrationCard(
                                zone: i + 1,
                                label: i == 0 ? 'LEFT BED' : i == 1 ? 'CENTER BED' : 'RIGHT BED',
                                moisture: moistureData.length > i ? moistureData[i] : 0.0,
                                isConnected: isConnected,
                              ),
                            ),
                            const SizedBox(height: 15),
                          ],
                        ],
                      ),
                      if (!isConnected)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                color: Colors.white.withOpacity(0.6),
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(color: Color(0xFF2BCC71)),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Searching for Raspberry Pi...',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: const Color(0xFF0F2027),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 30),
                _buildSectionHeader('Reference Reset'),
                _buildAnimatedItem(
                  4,
                  _buildDryCalibrationButton(isConnected),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F2027).withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA726).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.info_outline_rounded, color: Color(0xFFE65100), size: 24),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Text(
              'Adjust offsets manually or reset the 0% line by exposing the sensor to dry air.',
              style: GoogleFonts.outfit(
                color: const Color(0xFF37474F),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF4A6164),
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildCalibrationCard({
    required int zone,
    required String label,
    required double moisture,
    required bool isConnected,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F2027).withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: const Color(0xFF0F2027),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2BCC71).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isConnected ? '${moisture.toStringAsFixed(1)}%' : '--%',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: const Color(0xFF2BCC71),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _buildAdjustmentButton(
                  icon: Icons.remove_rounded,
                  label: '-1%',
                  color: Colors.redAccent,
                  onTap: isConnected
                      ? () => ref.read(firebaseServiceProvider)?.sendCommand({'command': 'adjust_offset', 'zone': zone, 'adjustment': -1})
                      : null,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildAdjustmentButton(
                  icon: Icons.add_rounded,
                  label: '+1%',
                  color: const Color(0xFF2BCC71),
                  onTap: isConnected
                      ? () => ref.read(firebaseServiceProvider)?.sendCommand({'command': 'adjust_offset', 'zone': zone, 'adjustment': 1})
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustmentButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: onTap == null ? 0.05 : 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: onTap == null ? 0.1 : 0.5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: onTap == null ? Colors.grey : color, size: 20),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: onTap == null ? Colors.grey : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDryCalibrationButton(bool isConnected) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isConnected
            ? () {
                _showConfirmDryCalibrationDialog();
              }
            : null,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
             gradient: LinearGradient(
              colors: isConnected 
                  ? [const Color(0xFF2BCC71), const Color(0xFF20A056)]
                  : [Colors.grey.withOpacity(0.4), Colors.grey.withOpacity(0.5)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: isConnected ? null : Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
            boxShadow: isConnected ? [
              BoxShadow(
                color: const Color(0xFF2BCC71).withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: isConnected 
              ? [
                  const Icon(Icons.water_drop_outlined, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'RUN DRY CALIBRATION (ALL ZONES)',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ]
              : [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'WAITING FOR CONNECTION...',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
          ),
        ),
      ),
    );
  }

  void _showConfirmDryCalibrationDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: Colors.white.withOpacity(0.9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Confirm Dry Calibration',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F2027),
            ),
          ),
          content: Text(
            'Please ensure all soil sensors are completely dry and exposed to air before running this calibration. This will reset the 0% reference for all zones.',
            style: GoogleFonts.outfit(color: const Color(0xFF37474F)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'CANCEL',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                ref.read(firebaseServiceProvider)?.sendCommand({'command': 'dry_calibrate'});
                Navigator.pop(dialogCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Dry calibration command sent to hardware.'),
                    backgroundColor: const Color(0xFF0F2027),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2BCC71),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('CONFIRM', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedItem(int index, Widget child) {
    final animation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Interval(
        (index * 0.1).clamp(0.0, 1.0),
        1.0,
        curve: Curves.easeOutCubic,
      ),
    ));

    final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Interval(
        (index * 0.1).clamp(0.0, 1.0),
        1.0,
        curve: Curves.easeOut,
      ),
    ));

    return SlideTransition(
      position: animation,
      child: FadeTransition(
        opacity: opacity,
        child: child,
      ),
    );
  }
}
