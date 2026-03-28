import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/platform_utils.dart';
import '../presentation/providers/sensor_provider.dart';
import '../widgets/plant_selection_grid.dart';
import '../data/services/data_service.dart';

class ZoneCard extends ConsumerStatefulWidget {
  final String zoneId;
  final String zoneName;
  final int rawMoisture;         // Actual sensor reading from the Pi/database
  final double calibratedValue;  // User-set threshold from Calibration screen
  final double targetMoisture;   // Precision saturation target
  final int temp;
  final Animation<double> pulseAnim;
  final bool isFault;

  const ZoneCard({
    super.key,
    required this.zoneId,
    required this.zoneName,
    this.rawMoisture = 0,
    this.calibratedValue = 0.0,
    this.targetMoisture = 65.0,
    required this.temp,
    required this.pulseAnim,
    this.isFault = false,
  });

  @override
  ConsumerState<ZoneCard> createState() => _ZoneCardState();
}

class _ZoneCardState extends ConsumerState<ZoneCard> {
  bool _isPressed = false;
  bool _isHovered = false;

  bool get isTempFault => widget.temp <= -1;

  Color getMoodColor() {
    if (widget.isFault) return Colors.grey.shade400;

    final val = widget.rawMoisture;
    final target = widget.targetMoisture.round();
    if (val < target - 15) return const Color(0xFFFFA726); // Dry
    if (val > target + 15) return const Color(0xFF29B6F6); // Wet
    return const Color(0xFF2BCC71); // Healthy
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = getMoodColor();
    final hasThreshold = widget.calibratedValue != 0.0;
    final plantImageAsync = ref.watch(plantImageProvider(widget.zoneId));
    final plantImageName = plantImageAsync.value;

    return MouseRegion(
      onEnter: Platform.isWindows ? (_) => setState(() => _isHovered = true) : null,
      onExit: Platform.isWindows ? (_) => setState(() => _isHovered = false) : null,
      child: GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlantSelectionGrid(
              onPlantSelected: (filename) async {
                final dataService = ref.read(dataServiceProvider);
                if (dataService != null) {
                  await dataService.updateZoneImage(widget.zoneId, filename);
                }
              },
            ),
          ),
        );
      },
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(isLiteMode ? 1.0 : 0.9),
            borderRadius: BorderRadius.circular(28),
            boxShadow: isLiteMode
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                    if (_isPressed)
                      BoxShadow(
                        color: statusColor.withOpacity(0.2),
                        blurRadius: 15,
                        spreadRadius: -5,
                      ),
                    // Windows hover glow
                    if (_isHovered && Platform.isWindows)
                      BoxShadow(
                        color: const Color(0xFF2BCC71).withOpacity(0.25),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                  ],
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              // ── Ghost Background Image ──
              if (plantImageName != null && plantImageName.isNotEmpty)
                Positioned.fill(
                  child: Platform.isLinux
                      ? ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            Colors.black.withOpacity(0.25),
                            BlendMode.dstIn,
                          ),
                          child: Image.asset(
                            'assets/images/plants/$plantImageName',
                            fit: BoxFit.cover,
                          ),
                        )
                      : Opacity(
                          opacity: 0.25,
                          child: Image.asset(
                            'assets/images/plants/$plantImageName',
                            fit: BoxFit.cover,
                          ),
                        ),
                ),

              // ── Subtle background accent ──
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                ),
              ),

              // ── TOP-LEFT: Zone Name + Temperature ──
              Positioned(
                top: 16,
                left: 18,
                right: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.zoneName,
                      style: const TextStyle(
                        color: Color(0xFF4A6164),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isTempFault ? '--°C' : '${widget.temp}°C',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // ── TOP-RIGHT: Calibrated threshold (user-set auto-water level) ──
              Positioned(
                top: 16,
                right: 16,
                child: hasThreshold
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF29B6F6).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color:
                                  const Color(0xFF29B6F6).withOpacity(0.3)),
                        ),
                        child: Text(
                          '${widget.calibratedValue.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            color: Color(0xFF0277BD),
                          ),
                        ),
                      )
                    : Text(
                        'No set',
                        style: TextStyle(
                          color: Colors.grey.shade300,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),

              // ── BOTTOM-LEFT: Raw Sensor Value + Ghost Target ──
              Positioned(
                left: 18,
                bottom: 18,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Icon(Icons.water_drop, size: 16, color: statusColor),
                    const SizedBox(width: 5),
                    if (widget.isFault)
                      Tooltip(
                        message: "Maintenance Required",
                        child: Row(
                          children: [
                            const Icon(Icons.build_rounded, color: Colors.orange, size: 28),
                            const SizedBox(width: 4),
                            Text(
                              'FAULT',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: Colors.orange,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      FadeTransition(
                        opacity: widget.pulseAnim,
                        child: Text(
                          '${widget.rawMoisture}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            color: statusColor,
                            letterSpacing: -1.0,
                            height: 1.0,
                          ),
                        ),
                      ),
                    // Ghost target label
                    if (!widget.isFault && widget.targetMoisture > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 2),
                        child: Text(
                          '→ ${widget.targetMoisture.round()}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.grey.shade400,
                            letterSpacing: -0.3,
                            height: 1.0,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── BOTTOM-RIGHT: Plant icon fallback ──
              if (plantImageName == null || plantImageName.isEmpty)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          statusColor.withOpacity(0.1),
                          statusColor.withOpacity(0.3),
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(35),
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.local_florist_rounded,
                        size: 30,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
