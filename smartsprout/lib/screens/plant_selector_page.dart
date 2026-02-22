// FILE: lib/screens/plant_selector_page.dart
import 'package:flutter/material.dart';
import '../data/plant_data.dart';

class PlantSelectorPage extends StatelessWidget {
  final Function(int) onSelect;
  const PlantSelectorPage({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text("Select Plant"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.85,
            crossAxisSpacing: 15,
            mainAxisSpacing: 15),
        itemCount: plantDB.length,
        itemBuilder: (context, index) {
          return InkWell(
            onTap: () {
              onSelect(index);
              Navigator.pop(context);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.03), blurRadius: 10)
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Image.asset(
                      plantDB[index]['image'] ?? '',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.green.shade100,
                          child: const Icon(Icons.local_florist,
                              color: Colors.green, size: 30),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(plantDB[index]['name'],
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(
                    plantDB[index]['desc'],
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
