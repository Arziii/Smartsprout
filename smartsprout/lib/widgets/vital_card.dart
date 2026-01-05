// FILE: lib/widgets/vital_card.dart
import 'package:flutter/material.dart';

class VitalCard extends StatelessWidget {
  final String label, value, subValue;
  final IconData icon;
  final Color color;
  final bool isAlert;

  const VitalCard({
    super.key, 
    required this.label, 
    required this.value, 
    required this.subValue, 
    required this.icon, 
    required this.color, 
    this.isAlert = false
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isAlert ? Colors.red[50] : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(20),
        border: isAlert ? Border.all(color: Colors.red.withOpacity(0.3)) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: isAlert ? Colors.red : color, size: 24),
              if(isAlert) const Icon(Icons.warning, color: Colors.red, size: 16)
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.bold,
            color: isAlert ? Colors.red : Colors.black87
          )),
          Text(subValue, style: TextStyle(fontSize: 12, color: isAlert ? Colors.red[300] : Colors.grey)),
        ],
      ),
    );
  }
}