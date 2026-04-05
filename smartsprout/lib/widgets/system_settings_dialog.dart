import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../data/services/data_service.dart';

class SystemSettingsDialog extends ConsumerWidget {
  const SystemSettingsDialog({super.key});

  void _sendCommand(BuildContext context, WidgetRef ref, String command) {
    ref.read(dataServiceProvider)?.sendCommand({'command': command});

    // Close the settings dialog
    Navigator.of(context).pop();

    // If it's a restart command, automatically go back to the Home/Dashboard
    if (command == 'RESTART_APP') {
      context.go('/dashboard');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(command == 'RESTART_APP'
            ? 'Restarting Dashboard...'
            : 'Command sent: $command'),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : const Color(0xFF0F2027),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, blurRadius: 30, offset: Offset(0, 10))
            ],
            border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white12
                    : Colors.white,
                width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white12
                      : const Color(0xFF0F2027).withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.settings_system_daydream_rounded,
                    size: 48,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : const Color(0xFF0F2027)),
              ),
              const SizedBox(height: 24),
              Text(
                'System Control',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF0F2027),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hardware-level maintenance controls for the Kiosk.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF4A6164),
                ),
              ),
              const SizedBox(height: 32),

              // Restart Dashboard Button
              _buildControlButton(
                context: context,
                icon: Icons.refresh_rounded,
                title: "Restart Dashboard",
                subtitle: "Relaunches the Flutter UI only",
                color: const Color(0xFF29B6F6),
                onTap: () => _sendCommand(context, ref, 'RESTART_APP'),
              ),

              const SizedBox(height: 16),

              // Reboot Hardware Button
              _buildControlButton(
                context: context,
                icon: Icons.power_settings_new_rounded,
                title: "Reboot Hardware",
                subtitle: "Full Raspberry Pi core reboot",
                color: Colors.redAccent,
                onTap: () => _showConfirmReboot(context, ref),
              ),

              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'CANCEL',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800,
                    color: Colors.grey,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : const Color(0xFF0F2027),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: const Color(0xFF4A6164),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: color.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  void _showConfirmReboot(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Confirm Hardware Reboot',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF0F2027),
          ),
        ),
        content: Text(
          'Are you sure you want to reboot the Raspberry Pi? This will temporarily take the system offline and halt any active watering.',
          style: GoogleFonts.outfit(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white70
                : const Color(0xFF37474F),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'CANCEL',
              style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800, color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx); // Close confirm
              _sendCommand(context, ref,
                  'REBOOT_PI'); // Sends command and closes settings dialog
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('REBOOT',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
