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

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  // SYSTEM STATE
  List<int> soilLevels = [0, 0, 0]; // Zone 1, 2, 3
  List<int> plantIDs = [0, 1, 2]; // Default Plants
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
    if (mounted) {
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
      MaterialPageRoute(
          builder: (context) => PlantSelectorPage(
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
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          // ── Photorealistic garden background ──
          Positioned.fill(
            child: Image.asset(
              'assets/images/dashboard_bg.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: const Color(0xFFF0F4EE)),
            ),
          ),
          // ── Soft frosted overlay for legibility ──
          Positioned.fill(
            child: Container(
              color: Colors.white.withValues(alpha: 0.60),
            ),
          ),
          // ── Main dashboard content ──
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                _buildTopHeader(),
                const SizedBox(height: 25),
                _buildVitals(),
                const SizedBox(height: 25),
                const Text("All Feature",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E1E1E),
                      letterSpacing: 0.5,
                    )),
                const SizedBox(height: 15),
                // Zone Cards Grid
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 15,
                  mainAxisSpacing: 15,
                  childAspectRatio: 0.85,
                  children: [
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
                    _buildSystemOverviewCard(),
                  ],
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Good Morning,",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 4),
            Text("Smart Sprout",
                style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E1E1E))),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.wifi, color: Color(0xFF1E1E1E), size: 22),
        )
      ],
    );
  }

  Widget _buildVitals() {
    return Row(
      children: [
        Expanded(
            child: VitalCard(
          label: "Reservoir",
          value: "$tankLevel%",
          subValue: "Capacity",
          icon: Icons.water_drop,
          color: Colors.blue,
          isAlert: tankLevel < 15,
        )),
        const SizedBox(width: 15),
        Expanded(
            child: VitalCard(
          label: "Solar Power",
          value: "${batteryVolts.toStringAsFixed(1)}V",
          subValue: isCharging ? "Charging" : "Draining",
          icon: Icons.bolt,
          color: Colors.orange,
        )),
      ],
    );
  }

  Widget _buildSystemOverviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F7), // Light grey
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("System\nHealth",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E1E1E),
                height: 1.2,
              )),
          const SizedBox(height: 8),
          Text("All systems nominal",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const Spacer(),
          const Align(
            alignment: Alignment.bottomRight,
            child: Icon(Icons.check_circle, color: Color(0xFF2BCC71), size: 40),
          )
        ],
      ),
    );
  }
}
