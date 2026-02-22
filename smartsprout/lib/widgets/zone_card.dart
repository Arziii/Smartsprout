// FILE: lib/widgets/zone_card.dart
import 'package:flutter/material.dart';
import '../data/plant_data.dart'; // Import to access plantDB

class ZoneCard extends StatelessWidget {
  final String zoneName;
  final int moisture;
  final int plantIndex;
  final int temp;
  final VoidCallback onTap;
  final Animation<double> pulseAnim;

  const ZoneCard(
      {super.key,
      required this.zoneName,
      required this.moisture,
      required this.plantIndex,
      required this.temp,
      required this.onTap,
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
    var plant = plantDB[plantIndex];

    // Use the realistic image from the plant database
    String imageAsset = plant['image'] ?? 'assets/images/plants/kamatis.jpg';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            // Bottom Right Plant Image
            Positioned(
              right: -30,
              bottom: -20,
              child: SizedBox(
                width: 140,
                height: 140,
                child: Image.asset(
                  imageAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.green.shade50,
                      child: const Icon(Icons.local_florist,
                          size: 80, color: Color(0xFF2BCC71)),
                    );
                  },
                ),
              ),
            ),

            // Texts overlay
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plant['name'],
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E1E1E))),
                  const SizedBox(height: 4),
                  Text(zoneName,
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  const Spacer(),
                  // Moisture
                  Row(
                    children: [
                      Icon(Icons.water_drop, size: 14, color: getMoodColor()),
                      const SizedBox(width: 4),
                      FadeTransition(
                        opacity: pulseAnim,
                        child: Text("$moisture%",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: getMoodColor())),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
