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

  const ZoneCard({
    super.key, 
    required this.zoneName, 
    required this.moisture, 
    required this.plantIndex, 
    required this.temp, 
    required this.onTap, 
    required this.pulseAnim
  });

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
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
          ),
          child: Row(
            children: [
              // PLANT IMAGE (Icon)
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: getMoodColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(child: Text(plant['icon'], style: const TextStyle(fontSize: 40))),
              ),
              const SizedBox(width: 20),
              
              // DETAILS
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(zoneName, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(plant['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    
                    // MOISTURE METER
                    Row(
                      children: [
                        Icon(Icons.water_drop, size: 16, color: getMoodColor()),
                        const SizedBox(width: 4),
                        // PULSING TEXT
                        FadeTransition(
                          opacity: pulseAnim,
                          child: Text("$moisture%", style: TextStyle(
                            fontWeight: FontWeight.bold, color: getMoodColor()
                          )),
                        ),
                        const SizedBox(width: 15),
                        const Icon(Icons.thermostat, size: 16, color: Colors.orange),
                        Text(" $temp°C", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    )
                  ],
                ),
              ),
              
              // MOOD ICON
              Text(getMoodIcon(), style: const TextStyle(fontSize: 24)),
            ],
          ),
        ),
      ),
    );
  }
}