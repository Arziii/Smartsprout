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
import '../widgets/account_switch_sheet.dart';
import '../../core/utils/platform_utils.dart';
import 'network_settings_screen.dart';
import '../providers/theme_provider.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F2027);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Settings',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: -0.5,
            )),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: context.canPop()
            ? IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: textColor, size: 20),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: Stack(
        children: [
          // ── Background (Matches Dashboard) ──
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF1E1E1E), const Color(0xFF121212)]
                      : const [Color(0xFFE0ECE9), Color(0xFFB4CDCA)],
                ),
              ),
            ),
          ),
          _buildBlob(
              top: -50,
              right: -100,
              size: 300,
              color: const Color(0xFF2BCC71).withValues(alpha: 0.15)),
          _buildBlob(
              bottom: 100,
              left: -100,
              size: 400,
              color: Colors.blue.withValues(alpha: 0.1)),

          // ── Content ──
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                const SizedBox(height: 25),
                _buildAnimatedItem(0, _buildSectionHeader('System')),
                _buildAnimatedItem(
                    1,
                    _buildSettingsCard(
                      title: 'Calibration',
                      subtitle: 'Adjust sensor offsets and reset references',
                      icon: Icons.tune_rounded,
                      color: const Color(0xFFFFA726),
                      onTap: () => context.push('/calibration'),
                    )),
                _buildAnimatedItem(
                    2,
                    _buildSettingsCard(
                      title: 'Hardware Controls',
                      subtitle: 'Restart dashboard or reboot Kiosk',
                      icon: Icons.settings_system_daydream_rounded,
                      color: const Color(0xFF2BCC71),
                      onTap: () => showDialog(
                          context: context,
                          builder: (_) => const SystemSettingsDialog()),
                    )),
                if (!Platform.isLinux)
                  _buildAnimatedItem(
                      3,
                      _buildSettingsCard(
                        title: 'Force Sync',
                        subtitle: 'Request live data from Raspberry Pi now',
                        icon: Icons.sync_rounded,
                        color: const Color(0xFF29B6F6),
                        isLoading: _isSyncing,
                        onTap: _isSyncing ? null : () => _handleForceSync(),
                      )),
                // ── Network (Linux Kiosk Only) ──────────────────────────
                if (Platform.isLinux) ...[
                  const SizedBox(height: 25),
                  _buildAnimatedItem(3, _buildSectionHeader('Network')),
                  _buildAnimatedItem(
                      4,
                      _buildSettingsCard(
                        title: 'Network Configuration',
                        subtitle: 'Connect or switch Wi-Fi networks',
                        icon: Icons.wifi_rounded,
                        color: const Color(0xFF29B6F6),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NetworkSettingsScreen(),
                          ),
                        ),
                      )),
                ],
                const SizedBox(height: 25),
                _buildAnimatedItem(3, _buildSectionHeader('Account')),
                if (!Platform.isLinux) ...[
                  _buildAnimatedItem(
                      4,
                      _buildSettingsCard(
                        title: 'Switch Account',
                        subtitle: 'Quickly switch between saved devices',
                        icon: Icons.people_alt_rounded,
                        color: const Color(0xFF29B6F6),
                        onTap: () => showAccountSwitchSheet(context),
                      )),
                  _buildAnimatedItem(
                      5,
                      _buildSettingsCard(
                        title: 'Rename Device',
                        subtitle:
                            'Change your device display name \n(requires PIN)',
                        icon: Icons.drive_file_rename_outline_rounded,
                        color: const Color(0xFF7E57C2),
                        onTap: () => _showRenameDeviceSheet(),
                      )),
                ],
                const SizedBox(height: 25),
                _buildAnimatedItem(6, _buildSectionHeader('Appearance')),
                _buildAnimatedItem(
                    7,
                    _buildSettingsCard(
                      title: 'Dark Mode',
                      subtitle: 'Change the appearance of the app',
                      icon: Icons.dark_mode_rounded,
                      color: Colors.blueAccent,
                      onTap: () {
                        ref.read(themeProvider.notifier).toggleTheme();
                      },
                      trailingWidget: Switch(
                        value: ref.watch(themeProvider) == ThemeMode.dark,
                        onChanged: (val) {
                          ref.read(themeProvider.notifier).toggleTheme();
                        },
                        activeThumbColor: const Color(0xFF2BCC71),
                      ),
                    )),
                const SizedBox(height: 25),
                _buildAnimatedItem(8, _buildSectionHeader('Security')),
                _buildAnimatedItem(
                    9,
                    _buildSettingsCard(
                      title: 'Change Device PIN',
                      subtitle: 'Update your hardware access PIN',
                      icon: Icons.lock_outline_rounded,
                      color: const Color(0xFF78909C),
                      onTap: () => _showChangePinSheet(),
                    )),
                _buildAnimatedItem(
                    10,
                    _buildSettingsCard(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white60 : const Color(0xFF4A6164),
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
    Widget? trailingWidget,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDestructive
        ? Colors.redAccent
        : (isDark ? Colors.white : const Color(0xFF0F2027));
    final subtitleColor = isDark
        ? Colors.white60
        : const Color(0xFF4A6164).withValues(alpha: 0.7);
    final cardBgColor = isDark
        ? const Color(0xFF1E1E1E).withValues(alpha: isLiteMode ? 0.95 : 0.4)
        : Colors.white.withValues(alpha: isLiteMode ? 0.95 : 0.7);
    final borderColor = isDark ? Colors.white12 : Colors.white;

    final listTile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: textColor,
          )),
      subtitle: Text(subtitle,
          style: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: subtitleColor,
          )),
      trailing: trailingWidget ??
          (isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.chevron_right_rounded,
                  color: isDark
                      ? Colors.white24
                      : const Color(0xFF4A6164).withValues(alpha: 0.3))),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: isLiteMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: isLiteMode
            ? listTile
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: listTile,
              ),
      ),
    );
  }

  Widget _buildBlob(
      {double? top,
      double? left,
      double? right,
      double? bottom,
      required double size,
      required Color color}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: isLiteMode
            ? null
            : BackdropFilter(
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
          curve: Interval(start.clamp(0.0, 1.0), (start + 0.6).clamp(0.0, 1.0),
              curve: Curves.easeOutQuart),
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
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF0F2027),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  void _showChangePinSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _ChangePinSheet(),
    );
  }

  void _showRenameDeviceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _RenameDeviceSheet(),
    );
  }

  // ── Custom Glass Dialog Components ──

  Widget _buildAwesomeDialog(BuildContext dialogCtx,
      {required String title,
      required String content,
      required String confirmText,
      bool isDestructive = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Text(title,
          style: GoogleFonts.outfit(
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF0F2027))),
      content: Text(content,
          style: GoogleFonts.outfit(
              color: isDark ? Colors.white70 : const Color(0xFF4A6164))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child:
                Text('Cancel', style: GoogleFonts.outfit(color: Colors.grey))),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDestructive
                ? Colors.redAccent
                : (isDark ? Colors.white : const Color(0xFF0F2027)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(confirmText,
              style: GoogleFonts.outfit(
                  color: isDestructive
                      ? Colors.white
                      : (isDark ? const Color(0xFF0F2027) : Colors.white))),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rename Device Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _RenameDeviceSheet extends ConsumerStatefulWidget {
  const _RenameDeviceSheet();
  @override
  ConsumerState<_RenameDeviceSheet> createState() => _RenameDeviceSheetState();
}

class _RenameDeviceSheetState extends ConsumerState<_RenameDeviceSheet>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _nameController = TextEditingController();
  late final AnimationController _fadeController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    Future.microtask(() => ref.read(authProvider.notifier).clearError());
  }

  @override
  void dispose() {
    _pinController.dispose();
    _nameController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final error = await ref
        .read(authProvider.notifier)
        .renameDevice(_pinController.text.trim(), _nameController.text.trim());
    if (mounted) {
      setState(() => _isLoading = false);
      if (error == null) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Device renamed to "${_nameController.text.trim()}"!',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            backgroundColor: const Color(0xFF2BCC71),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    return AnimatedPadding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE0ECE9), Color(0xFFB4CDCA)]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: FadeTransition(
              opacity: _fadeController,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    28, 20, 28, MediaQuery.of(context).padding.bottom + 100),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white10
                                    : Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10))),
                    Row(
                      children: [
                        GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white10
                                        : Colors.white.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.8),
                                        width: 1.5)),
                                child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    size: 16,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : const Color(0xFF0F2027)))),
                        const Spacer(),
                        Text('Rename Device',
                            style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : const Color(0xFF0F2027),
                                letterSpacing: -0.5)),
                        const Spacer(),
                        const SizedBox(width: 38),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2)),
                        child: const Icon(
                            Icons.drive_file_rename_outline_rounded,
                            size: 40,
                            color: Color(0xFF7E57C2))),
                    const SizedBox(height: 16),
                    Text('Change Display Name',
                        style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : const Color(0xFF0F2027),
                            letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text('Enter your current PIN & new name',
                        style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: const Color(0xFF4A6164),
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 32),
                    Container(
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 20,
                                offset: const Offset(0, 10))
                          ]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  if (authState.error != null) ...[
                                    _buildErrorBanner(authState.error!),
                                    const SizedBox(height: 16),
                                  ],
                                  _buildField(
                                      controller: _pinController,
                                      label: 'Current PIN',
                                      icon: Icons.lock_outline_rounded,
                                      hint: '••••',
                                      obscure: true),
                                  const SizedBox(height: 18),
                                  _buildField(
                                      controller: _nameController,
                                      label: 'New Name',
                                      icon: Icons.text_fields_rounded,
                                      hint: 'e.g. My Garden',
                                      textCapitalization:
                                          TextCapitalization.words),
                                  const SizedBox(height: 28),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 58,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _submit,
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? Colors.white
                                                  : const Color(0xFF0F2027),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18)),
                                          elevation: 0),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white))
                                          : Text('RENAME DEVICE',
                                              style: GoogleFonts.outfit(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 1.5)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
      {required TextEditingController controller,
      required String label,
      required IconData icon,
      required String hint,
      bool obscure = false,
      TextCapitalization textCapitalization = TextCapitalization.none}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : const Color(0xFF0F2027))),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          textCapitalization: textCapitalization,
          style: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF0F2027)),
          decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
              prefixIcon: Icon(icon, color: const Color(0xFF7E57C2), size: 20),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white10
                          : Colors.white.withValues(alpha: 0.5))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFF7E57C2), width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(vertical: 18)),
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2))),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded,
            color: Colors.redAccent, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: GoogleFonts.outfit(
                    color: Colors.redAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)))
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Change PIN Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ChangePinSheet extends ConsumerStatefulWidget {
  const _ChangePinSheet();
  @override
  ConsumerState<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends ConsumerState<_ChangePinSheet>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _currentPinController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmController = TextEditingController();
  late final AnimationController _fadeController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    Future.microtask(() => ref.read(authProvider.notifier).clearError());
  }

  @override
  void dispose() {
    _currentPinController.dispose();
    _pinController.dispose();
    _confirmController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pinController.text != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('PINs do not match'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final success = await ref.read(authProvider.notifier).changePin(
          _currentPinController.text.trim(),
          _pinController.text.trim(),
        );
    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('PIN Successfully Changed!',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            backgroundColor: const Color(0xFF2BCC71),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    return AnimatedPadding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE0ECE9), Color(0xFFB4CDCA)]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: FadeTransition(
              opacity: _fadeController,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    28, 20, 28, MediaQuery.of(context).padding.bottom + 100),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 40,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white10
                                    : Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10))),
                    Row(
                      children: [
                        GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white10
                                        : Colors.white.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color:
                                            Colors.white.withValues(alpha: 0.8),
                                        width: 1.5)),
                                child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    size: 16,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : const Color(0xFF0F2027)))),
                        const Spacer(),
                        Text('Change PIN',
                            style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : const Color(0xFF0F2027),
                                letterSpacing: -0.5)),
                        const Spacer(),
                        const SizedBox(width: 38),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2)),
                        child: const Icon(Icons.lock_rounded,
                            size: 40, color: Color(0xFF78909C))),
                    const SizedBox(height: 16),
                    Text('Update Security PIN',
                        style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : const Color(0xFF0F2027),
                            letterSpacing: -0.5)),
                    const SizedBox(height: 4),
                    Text('Set a new numeric PIN',
                        style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: const Color(0xFF4A6164),
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 32),
                    Container(
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 20,
                                offset: const Offset(0, 10))
                          ]),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                children: [
                                  if (authState.error != null) ...[
                                    _buildErrorBanner(authState.error!),
                                    const SizedBox(height: 16),
                                  ],
                                  _buildField(
                                      controller: _currentPinController,
                                      label: 'Current PIN',
                                      icon: Icons.lock_rounded,
                                      hint: '••••',
                                      obscure: true),
                                  const SizedBox(height: 18),
                                  _buildField(
                                      controller: _pinController,
                                      label: 'New PIN',
                                      icon: Icons.lock_outline_rounded,
                                      hint: '••••',
                                      obscure: true),
                                  const SizedBox(height: 18),
                                  _buildField(
                                      controller: _confirmController,
                                      label: 'Confirm New PIN',
                                      icon: Icons.check_circle_outline_rounded,
                                      hint: '••••',
                                      obscure: true),
                                  const SizedBox(height: 28),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 58,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _submit,
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? Colors.white
                                                  : const Color(0xFF0F2027),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18)),
                                          elevation: 0),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white))
                                          : Text('UPDATE PIN',
                                              style: GoogleFonts.outfit(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: 1.5)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
      {required TextEditingController controller,
      required String label,
      required IconData icon,
      required String hint,
      bool obscure = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : const Color(0xFF0F2027))),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          style: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : const Color(0xFF0F2027)),
          decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
              prefixIcon: Icon(icon, color: const Color(0xFF78909C), size: 20),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white10
                          : Colors.white.withValues(alpha: 0.5))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFF78909C), width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(vertical: 18)),
          validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
        ),
      ],
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2))),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded,
            color: Colors.redAccent, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: GoogleFonts.outfit(
                    color: Colors.redAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)))
      ]),
    );
  }
}
