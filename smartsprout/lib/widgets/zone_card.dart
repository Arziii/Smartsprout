import 'package:flutter/material.dart';
class ZoneCard extends StatefulWidget {
  final String zoneName;
  final int moisture;
  final int temp;
  final Animation<double> pulseAnim;

  const ZoneCard({
    super.key,
    required this.zoneName,
    required this.moisture,
    required this.temp,
    required this.pulseAnim,
  });

  @override
  State<ZoneCard> createState() => _ZoneCardState();
}

class _ZoneCardState extends State<ZoneCard> {
  bool _isPressed = false;

  Color getMoodColor() {
    int target = 50;
    if (widget.moisture < target - 15) return const Color(0xFFFFA726); // Dry
    if (widget.moisture > target + 15) return const Color(0xFF29B6F6); // Wet
    return const Color(0xFF2BCC71); // Healthy
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = getMoodColor();

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
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
            ],
            border: Border.all(
              color: Colors.white.withOpacity(0.5),
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              // ── Background Accent ──
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

              // ── Content ──
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.zoneName,
                      style: TextStyle(
                        color: const Color(0xFF4A6164),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${widget.temp}°C",
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    // Moisture Row
                    Row(
                      children: [
                        Icon(Icons.water_drop, size: 18, color: statusColor),
                        const SizedBox(width: 6),
                        FadeTransition(
                          opacity: widget.pulseAnim,
                          child: Text(
                            "${widget.moisture}%",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: statusColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Plant Icon Container ──
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 75,
                  height: 75,
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
                      size: 32,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
