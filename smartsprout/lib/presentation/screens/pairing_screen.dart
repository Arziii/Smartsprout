import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/kiosk_text_field.dart';
import '../providers/auth_provider.dart';

// ═══════════════════════════════════════════════════════
// Pairing Screen — Pi-Bouncer Architecture
// Replaces the old Bluetooth flow with manual Device ID + PIN entry.
// The Pi validates the PIN via Firestore (login_requests handshake).
// ═══════════════════════════════════════════════════════

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceController;
  final _formKey = GlobalKey<FormState>();
  final _deviceIdController = TextEditingController();
  final _pinController = TextEditingController();
  bool _obscurePin = true;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();

    // Clear any stale errors from a previous attempt
    Future.microtask(() => ref.read(authProvider.notifier).clearError());
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _deviceIdController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await ref.read(authProvider.notifier).login(
          _deviceIdController.text.trim().toUpperCase(),
          _pinController.text.trim(),
        );

    if (mounted && success) {
      context.go('/dashboard');
    }
    // On failure, auth_provider sets error — displayed via _buildErrorBanner
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // ── Background Gradient ──
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF0FDF4), Color(0xFFCCFBF1)],
                ),
              ),
            ),
          ),

          // ── Organic Blobs ──
          _buildBlob(
              top: -100,
              right: -50,
              size: 350,
              color: const Color(0xFF2BCC71).withValues(alpha: 0.15)),
          _buildBlob(
              bottom: -50,
              left: -150,
              size: 400,
              color: const Color(0xFF1A9B63).withValues(alpha: 0.08)),

          // ── Content ──
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Top Bar ──
                      _buildAnimatedItem(
                        0,
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Row(
                            children: [
                              // Back arrow (only if we have a saved device to go back to)
                              if (authState.savedDevices.isNotEmpty)
                                GestureDetector(
                                  onTap: () => context.go('/dashboard'),
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white10
                                          : Colors.white.withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.8),
                                          width: 1.5),
                                    ),
                                    child: Icon(
                                      Icons.arrow_back_ios_new_rounded,
                                      size: 16,
                                      color: Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : const Color(0xFF0F2027),
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(width: 40),
                              const Spacer(),
                              Text(
                                'Pair New Device',
                                style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : const Color(0xFF0F2027),
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const Spacer(),
                              const SizedBox(width: 40),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // ── Icon Badge ──
                      _buildAnimatedItem(
                        1,
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.6),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(65),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: const Center(
                                child: Icon(
                                  Icons.router_rounded,
                                  size: 60,
                                  color: Color(0xFF2BCC71),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── Headline ──
                      _buildAnimatedItem(
                        2,
                        Text(
                          'Connect Your Garden',
                          style: GoogleFonts.outfit(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : const Color(0xFF0F2027),
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildAnimatedItem(
                        2,
                        Text(
                          'Enter the Device ID and Admin PIN\nfound on your Smart Sprout unit.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF4A6164),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 36),

                      // ── Glass Form Card ──
                      _buildAnimatedItem(
                        3,
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Error Banner
                                    if (authState.error != null) ...[
                                      _buildErrorBanner(authState.error!,
                                          isRateLimited:
                                              authState.isRateLimited),
                                      const SizedBox(height: 16),
                                    ],

                                    // Device ID Field
                                    _buildFieldLabel('Device ID'),
                                    const SizedBox(height: 8),
                                    _buildTextField(
                                      controller: _deviceIdController,
                                      hint: 'e.g. SPROUT_A1B2',
                                      icon: Icons.devices_rounded,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                            RegExp(r'[A-Za-z0-9_]')),
                                        LengthLimitingTextInputFormatter(20),
                                      ],
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                              ? 'Device ID is required'
                                              : null,
                                    ),

                                    const SizedBox(height: 20),

                                    // Admin PIN Field
                                    _buildFieldLabel('Admin PIN'),
                                    const SizedBox(height: 8),
                                    _buildTextField(
                                      controller: _pinController,
                                      hint: '••••',
                                      icon: Icons.lock_rounded,
                                      obscure: _obscurePin,
                                      onToggleObscure: () => setState(
                                          () => _obscurePin = !_obscurePin),
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(8),
                                      ],
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                              ? 'PIN is required'
                                              : null,
                                    ),

                                    const SizedBox(height: 28),

                                    // Connect Button
                                    SizedBox(
                                      height: 56,
                                      child: ElevatedButton(
                                        onPressed: authState.isLoading ||
                                                authState.isRateLimited
                                            ? null
                                            : _connect,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? Colors.white
                                                  : const Color(0xFF0F2027),
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor:
                                              const Color(0xFF0F2027)
                                                  .withValues(alpha: 0.4),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                          elevation: 0,
                                        ),
                                        child: authState.isLoading
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                  color: Colors.white,
                                                ),
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
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── Help hint ──
                      _buildAnimatedItem(
                        4,
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  size: 14,
                                  color: const Color(0xFF4A6164)
                                      .withValues(alpha: 0.7)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'The Device ID and PIN are set during hardware setup.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: const Color(0xFF4A6164)
                                        .withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // What happens hint
                      _buildAnimatedItem(
                        4,
                        _buildStepRow(),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step indicator (replaces old Bluetooth scanning animation) ──
  Widget _buildStepRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1),
      ),
      child: Column(
        children: [
          _buildStep(Icons.edit_rounded, '1. Enter credentials',
              'Type your Device ID and PIN'),
          const SizedBox(height: 10),
          _buildStep(Icons.cloud_sync_rounded, '2. Pi validates',
              'Your garden\'s hardware authenticates via cloud'),
          const SizedBox(height: 10),
          _buildStep(Icons.check_circle_rounded, '3. You\'re in',
              'Full control of your garden'),
        ],
      ),
    );
  }

  Widget _buildStep(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2BCC71).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF2BCC71)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : const Color(0xFF0F2027),
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: const Color(0xFF4A6164),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.outfit(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : const Color(0xFF0F2027),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return KioskTextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: GoogleFonts.outfit(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : const Color(0xFF0F2027)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            TextStyle(color: const Color(0xFF4A6164).withValues(alpha: 0.5)),
        prefixIcon: Icon(icon, color: const Color(0xFF2BCC71), size: 20),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: const Color(0xFF4A6164).withValues(alpha: 0.5),
                  size: 20,
                ),
                onPressed: onToggleObscure,
              )
            : null,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white10
                  : Colors.white.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2BCC71), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
      ),
      validator: validator,
    );
  }

  Widget _buildErrorBanner(String message, {bool isRateLimited = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            isRateLimited
                ? Icons.timer_off_rounded
                : Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.outfit(
                color: Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlob({
    double? top,
    double? left,
    double? right,
    double? bottom,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: BackdropFilter(
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
        final start = index * 0.12;
        final curve = CurvedAnimation(
          parent: _entranceController,
          curve: Interval(
            start.clamp(0.0, 1.0),
            (start + 0.6).clamp(0.0, 1.0),
            curve: Curves.easeOutQuart,
          ),
        );
        return Opacity(
          opacity: curve.value,
          child: Transform.translate(
            offset: Offset(0, 28 * (1 - curve.value)),
            child: child,
          ),
        );
      },
    );
  }
}
