// FILE: lib/main.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/dashboard_page.dart';

void main() {
  runApp(const SmartSproutApp());
}

class SmartSproutApp extends StatelessWidget {
  const SmartSproutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Sprout',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
        primarySwatch: Colors.green,
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const DashboardPage(),
    );
  }
}