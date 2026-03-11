import 'package:flutter/material.dart';
class ZoneCard extends StatelessWidget {
  final String zoneName;
  final int moisture;
  final int temp;
  final Animation<double> pulseAnim;

  const ZoneCard(
      {super.key,
      required this.zoneName,
      required this.moisture,
      required this.temp,
      required this.pulseAnim});

  // Mood Logic
  String getMoodIcon() {
    int target = 50;
    if (moisture < target - 15) return "🥵"; // Dry
    if (moisture > target + 15) return "🥶"; // Wet
    return "🤠"; // Happy
  }

  Color getMoodColor() {
    int target = 50;
    if (moisture < target - 15) return Colors.orange;
    if (moisture > target + 15) return Colors.blue;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
            color: const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ]),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Texts and moisture
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(zoneName,
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  const Spacer(),
                  // Moisture
                  Row(
                    children: [
                      const Icon(Icons.water_drop,
                          size: 16, color: Colors.orangeAccent),
                      const SizedBox(width: 4),
                      FadeTransition(
                        opacity: pulseAnim,
                        child: Text("$moisture%",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.orangeAccent)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Image in bottom right corner
            Positioned(
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(30),
                ),
                child: Container(
                  width: 95,
                  height: 95,
                  color: const Color(0xFFEEEEEE),
                  child: Container(
                    color: Colors.green.shade50,
                    child: const Icon(Icons.local_florist,
                        size: 40, color: Color(0xFF2BCC71)),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
  }
}
