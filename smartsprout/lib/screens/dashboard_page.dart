// FILE: lib/screens/dashboard_page.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// import 'package:http/http.dart' as http; // Uncomment for Real IoT

import '../data/plant_data.dart';
import '../widgets/vital_card.dart';
import '../widgets/zone_card.dart';
import 'plant_selector_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with SingleTickerProviderStateMixin {
  // SYSTEM STATE
  List<int> soilLevels = [0, 0, 0]; // Zone 1, 2, 3
  List<int> plantIDs = [0, 1, 2];   // Default Plants
  int tankLevel = 75;
  double batteryVolts = 12.4;
  bool isCharging = true;
  
  Timer? _timer;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // Setup "Live Pulse" Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.5,
      upperBound: 1.0,
    )..repeat(reverse: true);

    // Start Polling Loop
    _timer = Timer.periodic(const Duration(seconds: 2), (t) => _fetchData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    // --- REAL IOT MODE (Uncomment when ESP32 is ready) ---
    /*
    try {
      final response = await http.get(Uri.parse('$databaseUrl/.json'));
      if (response.statusCode == 200) {
        // Parse Logic Here...
      }
    } catch (e) { print(e); }
    */

    // --- DEMO MODE ---
    if(mounted) {
      setState(() {
        Random r = Random();
        tankLevel = (tankLevel + r.nextInt(3) - 1).clamp(0, 100);
        batteryVolts = 12.0 + (r.nextInt(10) / 10.0);
        soilLevels[0] = (45 + r.nextInt(2)); 
        soilLevels[1] = (60 + r.nextInt(2)); 
        soilLevels[2] = (25 + r.nextInt(2)); 
      });
    }
  }

  void _openPlantSelector(int zoneIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PlantSelectorPage(
        onSelect: (plantIndex) {
          setState(() => plantIDs[zoneIndex] = plantIndex);
          // Add http.put logic here to save to Firebase
        },
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  const SizedBox(height: 10),
                  const Text("YOUR ZONES", style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2
                  )),
                  const SizedBox(height: 15),
                  ZoneCard(
                    zoneName: "Zone 1 (Left)",
                    moisture: soilLevels[0],
                    plantIndex: plantIDs[0],
                    temp: 32,
                    onTap: () => _openPlantSelector(0),
                    pulseAnim: _pulseController,
                  ),
                  ZoneCard(
                    zoneName: "Zone 2 (Center)",
                    moisture: soilLevels[1],
                    plantIndex: plantIDs[1],
                    temp: 31,
                    onTap: () => _openPlantSelector(1),
                    pulseAnim: _pulseController,
                  ),
                  ZoneCard(
                    zoneName: "Zone 3 (Right)",
                    moisture: soilLevels[2],
                    plantIndex: plantIDs[2],
                    temp: 33,
                    onTap: () => _openPlantSelector(2),
                    pulseAnim: _pulseController,
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF4CAF50),
        elevation: 10,
        onPressed: () {}, 
        label: const Row(
          children: [
            Icon(Icons.hub, color: Colors.white),
            SizedBox(width: 8),
            Text("Quick Actions", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 5))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Good Morning,", style: TextStyle(color: Colors.grey, fontSize: 14)),
                  Text("Smart Sprout", style: GoogleFonts.poppins(
                    fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF2E7D32)
                  )),
                ],
              ),
              CircleAvatar(
                backgroundColor: Colors.green[50],
                child: const Icon(Icons.settings, color: Colors.green),
              )
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: VitalCard(
                label: "Reservoir",
                value: "$tankLevel%",
                subValue: "Capacity",
                icon: Icons.water_drop,
                color: Colors.blue,
                isAlert: tankLevel < 15,
              )),
              const SizedBox(width: 15),
              Expanded(child: VitalCard(
                label: "Solar Power",
                value: "${batteryVolts.toStringAsFixed(1)}V",
                subValue: isCharging ? "Charging..." : "Draining",
                icon: Icons.bolt,
                color: Colors.orange,
              )),
            ],
          )
        ],
      ),
    );
  }
}