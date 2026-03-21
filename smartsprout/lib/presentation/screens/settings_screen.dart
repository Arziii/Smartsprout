import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../../data/services/data_service.dart';
import '../../widgets/system_settings_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text('Settings', 
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w800, 
            color: const Color(0xFF0F2027),
            letterSpacing: -0.5,
          )),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: context.canPop() ? IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F2027), size: 20),
          onPressed: () => context.pop(),
        ) : null,
      ),
      body: Stack(
        children: [
          // ── Background (Matches Dashboard) ──
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE0ECE9), Color(0xFFB4CDCA)],
                ),
              ),
            ),
          ),
          _buildBlob(top: -50, right: -100, size: 300, color: const Color(0xFF2BCC71).withOpacity(0.15)),
          _buildBlob(bottom: 100, left: -100, size: 400, color: Colors.blue.withOpacity(0.1)),

          // ── Content ──
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                const SizedBox(height: 25),
                _buildAnimatedItem(0, _buildSectionHeader('System')),
                _buildAnimatedItem(1, _buildSettingsCard(
                  title: 'Calibration',
                  subtitle: 'Adjust sensor offsets and reset references',
                  icon: Icons.tune_rounded,
                  color: const Color(0xFFFFA726),
                  onTap: () => context.push('/calibration'),
                )),
                _buildAnimatedItem(2, _buildSettingsCard(
                  title: 'Hardware Controls',
                  subtitle: 'Restart dashboard or reboot Kiosk',
                  icon: Icons.settings_system_daydream_rounded,
                  color: const Color(0xFF2BCC71),
                  onTap: () => showDialog(context: context, builder: (_) => const SystemSettingsDialog()),
                )),
                if (!Platform.isLinux)
                  _buildAnimatedItem(3, _buildSettingsCard(
                    title: 'Force Sync',
                    subtitle: 'Request live data from Raspberry Pi now',
                    icon: Icons.sync_rounded,
                    color: const Color(0xFF29B6F6),
                    isLoading: _isSyncing,
                    onTap: _isSyncing ? null : () => _handleForceSync(),
                  )),
                const SizedBox(height: 25),
                _buildAnimatedItem(3, _buildSectionHeader('Account')),
                _buildAnimatedItem(4, _buildSettingsCard(
                  title: 'Change Device PIN',
                  subtitle: 'Update your hardware access PIN',
                  icon: Icons.lock_outline_rounded,
                  color: const Color(0xFF78909C),
                  onTap: () => _showChangePinDialog(),
                )),
                _buildAnimatedItem(5, _buildSettingsCard(
                  title: 'Disconnect Device',
                  subtitle: 'Log out of current hardware',
                  icon: Icons.logout_rounded,
                  color: Colors.redAccent,
                  isDestructive: true,
                  onTap: () => _logout(),
                )),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF4A6164),
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool isLoading = false,
    bool isDestructive = false,
  }) {
    final listTile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title,
        style: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: isDestructive ? Colors.redAccent : const Color(0xFF0F2027),
        )),
      subtitle: Text(subtitle,
        style: GoogleFonts.outfit(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF4A6164).withOpacity(0.7),
        )),
      trailing: isLoading
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.chevron_right_rounded, color: const Color(0xFF4A6164).withOpacity(0.3)),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(Platform.isLinux ? 0.95 : 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: Platform.isLinux ? null : [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Platform.isLinux 
            ? listTile 
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: listTile,
              ),
      ),
    );
  }


  Widget _buildBlob({double? top, double? left, double? right, double? bottom, required double size, required Color color}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Platform.isLinux ? null : BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  Widget _buildAnimatedItem(int index, Widget child) {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, _) {
        final start = index * 0.05;
        final curve = CurvedAnimation(
          parent: _entranceController,
          curve: Interval(start.clamp(0.0, 1.0), (start + 0.6).clamp(0.0, 1.0), curve: Curves.easeOutQuart),
        );
        return Opacity(
          opacity: curve.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - curve.value)),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _handleForceSync() async {
    final dataService = ref.read(dataServiceProvider);
    if (dataService == null) return;

    setState(() => _isSyncing = true);

    try {
      await dataService.forceSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Requesting live data from Raspberry Pi...',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xFF0F2027),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
      // Silently fail
    }

    await Future.delayed(const Duration(seconds: 5));
    if (mounted) setState(() => _isSyncing = false);
  }

  // ── Actions & Dialogs (Kept functional logic, restyled UI) ──

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildAwesomeDialog(
        ctx,
        title: 'Disconnect Device',
        content: 'Are you sure you want to log out of this device?',
        confirmText: 'Disconnect',
        isDestructive: true,
      ),
    );

    if (confirm == true) {
      await ref.read(authProvider.notifier).logout();
      if (mounted) context.go('/login');
    }
  }


  void _showChangePinDialog() {
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => _buildAwesomeInputDialog(
        ctx,
        title: 'Change PIN',
        subtitle: 'Update your system security PIN',
        controller: pinController,
        controller2: confirmController,
        hint: 'New PIN',
        hint2: 'Confirm PIN',
        isPin: true,
        onConfirm: () async {
          if (pinController.text == confirmController.text) {
            await ref.read(authProvider.notifier).changePin(pinController.text.trim());
          }
        },
      ),
    );
  }

  // ── Custom Glass Dialog Components ──

  Widget _buildAwesomeDialog(BuildContext dialogCtx, {required String title, required String content, required String confirmText, bool isDestructive = false}) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
      content: Text(content, style: GoogleFonts.outfit(color: const Color(0xFF4A6164))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey))),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDestructive ? Colors.redAccent : const Color(0xFF0F2027),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(confirmText, style: GoogleFonts.outfit(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildAwesomeInputDialog(BuildContext dialogCtx, {
    required String title,
    required String subtitle,
    required TextEditingController controller,
    TextEditingController? controller2,
    required String hint,
    String? hint2,
    bool isPin = false,
    required VoidCallback onConfirm,
  }) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
          Text(subtitle, style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: controller, obscureText: true, decoration: InputDecoration(hintText: hint)),
          if (controller2 != null) ...[
            const SizedBox(height: 10),
            TextField(controller: controller2, obscureText: true, decoration: InputDecoration(hintText: hint2)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () { onConfirm(); Navigator.pop(dialogCtx); }, child: const Text('Confirm')),
      ],
    );
  }
}
