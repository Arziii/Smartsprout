import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryGreen =
      Color(0xFF2BCC71); // Vibrant Green from reference
  static const Color lightGreen =
      Color(0xFFE8F6EF); // Soft Green background for active elements
  static const Color darkGreen = Color(0xFF27AE60); // Darker Green for accents
  static const Color backgroundLight =
      Color(0xFFFAFAFA); // Almost white background
  static const Color surfaceColor = Colors.white; // Card background

  static const Color textPrimary = Color(0xFF1E1E1E);
  static const Color textSecondary = Color(0xFF9E9E9E);

  static const Color iconBackground =
      Color(0xFFF5F5F7); // Light grey for icon buttons
  static const Color waterBlue = Color(0xFF29B6F6);
  static const Color warningOrange = Color(0xFFFFA726);
  static const Color alertRed = Color(0xFFEF5350);

  static final ThemeData lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        primary: primaryGreen,
        secondary: lightGreen,
        surface: surfaceColor,
        background: backgroundLight,
        error: alertRed,
      ),
      scaffoldBackgroundColor: backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textSecondary),
      ));
}
