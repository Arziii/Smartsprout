import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Switch Account Sheet
// ─────────────────────────────────────────────────────────────────────────────

class AccountSwitchSheet extends ConsumerStatefulWidget {
  const AccountSwitchSheet({super.key});

  @override
  ConsumerState<AccountSwitchSheet> createState() => _AccountSwitchSheetState();
}

class _AccountSwitchSheetState extends ConsumerState<AccountSwitchSheet> {
  bool _isLoading = false;

  Future<void> _handleSwitch(String deviceId) async {
    setState(() => _isLoading = true);
    final success = await ref.read(authProvider.notifier).quickSwitch(deviceId);
    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        context.pop();
        context.go('/dashboard');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to switch device.')),
        );
      }
    }
  }

  void _showAddAccountModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _AddAccountSheet(),
    );
  }

  void _showEditNicknameDialog(SavedDevice device) {
    final controller = TextEditingController(text: device.nickname);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Edit Nickname', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: 'e.g. Backyard Garden',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                ref.read(authProvider.notifier).updateDeviceNickname(device.deviceId, newName);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(SavedDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Remove Account', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        content: Text(
          "Are you sure you want to remove ${device.nickname}? You'll need to enter the PIN to add it again.",
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              ref.read(authProvider.notifier).removeSavedDevice(device.deviceId);
              Navigator.pop(ctx);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final devices = authState.savedDevices;
    final currentDevice = authState.deviceId;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 40, offset: Offset(0, -10))
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Drag Handle ──
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                // ── Header Row: Title + Add Button ──
                Row(
                  children: [
                    const Spacer(),
                    Text(
                      'Switch Accounts',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F2027),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _buildAddButton(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Account List ──
                if (devices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        Icon(Icons.devices_rounded, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          'No saved accounts yet.',
                          style: GoogleFonts.outfit(
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap + to add a device',
                          style: GoogleFonts.outfit(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final device = devices[index];
                        final isActive = device.deviceId == currentDevice;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF2BCC71).withOpacity(0.1)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xFF2BCC71)
                                  : Colors.grey.shade200,
                              width: 2,
                            ),
                          ),
                          child: ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: isActive
                                  ? const Color(0xFF2BCC71)
                                  : const Color(0xFF4A6164),
                              child: isActive
                                  ? const Icon(Icons.check_rounded, color: Colors.white)
                                  : const Icon(Icons.grass_rounded, color: Colors.white),
                            ),
                            title: Text(
                              device.nickname,
                              style: GoogleFonts.outfit(
                                fontWeight:
                                    isActive ? FontWeight.w800 : FontWeight.w600,
                                fontSize: 16,
                                color: const Color(0xFF0F2027),
                              ),
                            ),
                            subtitle: Text(
                              device.deviceId,
                              style: GoogleFonts.outfit(
                                  fontSize: 12, color: Colors.grey.shade600),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit_rounded,
                                      color: Colors.grey.shade400, size: 20),
                                  onPressed: () => _showEditNicknameDialog(device),
                                ),
                                IconButton(
                                  icon: const Icon(
                                      Icons.remove_circle_outline_rounded,
                                      color: Colors.redAccent,
                                      size: 20),
                                  onPressed: () => _confirmDelete(device),
                                ),
                              ],
                            ),
                            onTap: isActive || _isLoading
                                ? null
                                : () => _handleSwitch(device.deviceId),
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Tooltip(
      message: 'Add Account',
      child: GestureDetector(
        onTap: _showAddAccountModal,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF2BCC71).withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF2BCC71).withOpacity(0.4),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.add_rounded,
            color: Color(0xFF1B8E4F),
            size: 22,
          ),
        ),
      ),
    );
  }
}

void showAccountSwitchSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
      ),
      child: const AccountSwitchSheet(),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// In-App Add Account Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddAccountSheet extends ConsumerStatefulWidget {
  const _AddAccountSheet();

  @override
  ConsumerState<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends ConsumerState<_AddAccountSheet>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _deviceIdController = TextEditingController();
  final _pinController = TextEditingController();
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    
    // Clear any stale errors from previous login attempts
    Future.microtask(() => ref.read(authProvider.notifier).clearError());
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _pinController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _addAccount() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await ref.read(authProvider.notifier).login(
          _deviceIdController.text.trim(),
          _pinController.text.trim(),
        );

    if (mounted) {
      if (success) {
        // Stay in the app — just pop this add-account sheet back to the switch list
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Account added successfully!',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xFF2BCC71),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      // error is already in authState.error — displayed via _buildErrorBanner
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE0ECE9), Color(0xFFB4CDCA)],
          ),
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
                  28, 20, 28, MediaQuery.of(context).padding.bottom + 100,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Drag handle ──
                    Container(
                      width: 40,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),

                    // ── Top Row: Back button + Title ──
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.8), width: 1.5),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 16,
                              color: Color(0xFF0F2027),
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Add Account',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F2027),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 38), // balance the back button
                      ],
                    ),
                    const SizedBox(height: 32),

                    // ── Icon + subtitle ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.4),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.grass_rounded,
                        size: 40,
                        color: Color(0xFF2BCC71),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Connect a Device',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F2027),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enter the Device ID and PIN',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: const Color(0xFF4A6164),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Login Form Card ──
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
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
                                    controller: _deviceIdController,
                                    label: 'Device ID',
                                    icon: Icons.router_rounded,
                                    hint: 'SPROUT_A1B2',
                                  ),
                                  const SizedBox(height: 18),
                                  _buildField(
                                    controller: _pinController,
                                    label: 'Admin PIN',
                                    icon: Icons.lock_rounded,
                                    hint: '••••',
                                    obscure: true,
                                  ),
                                  const SizedBox(height: 28),
                                  _buildConnectButton(authState.isLoading),
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    bool obscure = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: const Color(0xFF0F2027),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          style: GoogleFonts.outfit(
              fontWeight: FontWeight.w600, color: const Color(0xFF0F2027)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
            prefixIcon: Icon(icon, color: const Color(0xFF2BCC71), size: 20),
            filled: true,
            fillColor: Colors.white.withOpacity(0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: Color(0xFF2BCC71), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
          ),
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Required' : null,
        ),
      ],
    );
  }

  Widget _buildConnectButton(bool isLoading) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: isLoading ? null : _addAccount,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F2027),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                'CONNECT TO SYSTEM',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.outfit(
                  color: Colors.redAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
