import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/widgets/kiosk_text_field.dart';
import '../providers/auth_provider.dart';

class HardwareLoginScreen extends ConsumerStatefulWidget {
  const HardwareLoginScreen({super.key});

  @override
  ConsumerState<HardwareLoginScreen> createState() =>
      _HardwareLoginScreenState();
}

class _HardwareLoginScreenState extends ConsumerState<HardwareLoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _deviceIdController = TextEditingController();
  final _pinController = TextEditingController();
  late AnimationController _fadeController;

  Timer? countdownTimer;
  Duration _rateLimitRemaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _pinController.dispose();
    _fadeController.dispose();
    countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(DateTime expiry) {
    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = expiry.difference(DateTime.now());
      if (!mounted) return;
      if (remaining.isNegative || remaining.inSeconds <= 0) {
        countdownTimer?.cancel();
        ref.read(authProvider.notifier).clearRateLimit();
        return;
      }
      setState(() => _rateLimitRemaining = remaining);
    });
    setState(() => _rateLimitRemaining = expiry.difference(DateTime.now()));
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authProvider.notifier).login(
          _deviceIdController.text.trim(),
          _pinController.text.trim(),
        );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Login successful!'),
          backgroundColor: const Color(0xFF2BCC71),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Start countdown when rate-limited
    if (authState.isRateLimited && authState.rateLimitExpiry != null) {
      final expiry = authState.rateLimitExpiry!;
      final remaining = expiry.difference(DateTime.now());
      if (!remaining.isNegative &&
          remaining.inSeconds > 0 &&
          (countdownTimer == null || !countdownTimer!.isActive)) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _startCountdown(expiry));
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Stack(
        children: [
          // ── Gradient & Blob Background ──
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
          _buildBlob(
              top: -100,
              right: -50,
              size: 300,
              color: const Color(0xFF2BCC71).withValues(alpha: 0.15)),
          _buildBlob(
              bottom: -50,
              left: -100,
              size: 400,
              color: Colors.blue.withValues(alpha: 0.1)),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: FadeTransition(
                opacity: _fadeController,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildAnimatedElement(0, _buildHeader()),
                    const SizedBox(height: 48),

                    // ── Rate-Limit Banner (full screen, blocks login) ──
                    if (authState.isRateLimited) ...[
                      _buildAnimatedElement(1, _buildRateLimitBanner()),
                      const SizedBox(height: 24),
                    ],

                    if (!authState.isRateLimited) ...[
                      if (authState.savedDevices.isNotEmpty) ...[
                        _buildAnimatedElement(
                            1, _buildSavedAccountsHorizontal(authState)),
                        const SizedBox(height: 32),
                      ],
                      _buildAnimatedElement(2, _buildLoginForm(authState)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // Header
  // ─────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2BCC71).withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Smart Sprout',
          style: GoogleFonts.outfit(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF0F2027),
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'INDOOR GARDENING SYSTEM',
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF4A6164),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────
  // Rate-Limit Banner with Live Countdown
  // ─────────────────────────────────────────────────────
  Widget _buildRateLimitBanner() {
    final minutes = _rateLimitRemaining.inMinutes;
    final seconds = _rateLimitRemaining.inSeconds.remainder(60);
    final timeStr =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
            color: const Color(0xFFFFB347).withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            children: [
              // Lock icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB347).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_clock_rounded,
                    size: 48, color: Color(0xFFE67E22)),
              ),
              const SizedBox(height: 20),
              Text(
                'Too Many Attempts',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F2027),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This device has been temporarily locked\ndue to multiple incorrect PINs.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: const Color(0xFF4A6164),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              // Countdown display
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F2027).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFFFFB347).withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text(
                      'TRY AGAIN IN',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: const Color(0xFF4A6164),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timeStr,
                      style: GoogleFonts.outfit(
                        fontSize: 48,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFE67E22),
                        letterSpacing: -2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // Saved Accounts Carousel
  // ─────────────────────────────────────────────────────
  Widget _buildSavedAccountsHorizontal(AuthState authState) {
    final devices = authState.savedDevices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Saved Accounts',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            color: const Color(0xFF4A6164),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: devices.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final device = devices[index];
              return GestureDetector(
                onTap: () async {
                  // Capture context-dependent refs before async gap
                  final messenger = ScaffoldMessenger.of(context);
                  final router = GoRouter.of(context);
                  // Option B: try session reuse first
                  final success = await ref
                      .read(authProvider.notifier)
                      .quickSwitch(device.deviceId);
                  if (success && mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Switched to ${device.nickname}'),
                        backgroundColor: const Color(0xFF2BCC71),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                    router.go('/dashboard');
                  } else {
                    // Session expired — pre-fill device ID and let user enter PIN
                    _deviceIdController.text = device.deviceId;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                            'Session expired for ${device.nickname}. Enter your PIN.'),
                        backgroundColor: const Color(0xFF4A6164),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  }
                },
                child: Stack(
                  children: [
                    Container(
                      width: 90,
                      height: 100, // ensure explicit height
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircleAvatar(
                                radius: 20,
                                backgroundColor: Color(0xFF2BCC71),
                                child: Icon(Icons.grass_rounded,
                                    color: Colors.white, size: 20),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  device.nickname,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F2027),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () async {
                          final messenger2 = ScaffoldMessenger.of(context);
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                                backgroundColor: const Color(0xFFF0FDF4),
                                title: Text(
                                  'Remove Account',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF0F2027),
                                  ),
                                ),
                                content: Text(
                                  'Are you sure you want to remove ${device.nickname}?',
                                  style: GoogleFonts.outfit(
                                      color: const Color(0xFF4A6164)),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: Text(
                                      'CANCEL',
                                      style: GoogleFonts.outfit(
                                          color: const Color(0xFF4A6164),
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text(
                                      'REMOVE',
                                      style: GoogleFonts.outfit(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );

                          if (confirm == true) {
                            await ref
                                .read(authProvider.notifier)
                                .removeSavedDevice(device.deviceId);
                            if (mounted) {
                              messenger2.showSnackBar(
                                SnackBar(
                                  content: Text('${device.nickname} removed'),
                                  backgroundColor: const Color(0xFFE67E22),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            }
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.transparent,
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: Colors.black54),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────
  // Login Form
  // ─────────────────────────────────────────────────────
  Widget _buildLoginForm(AuthState authState) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (authState.error != null && !authState.isRateLimited)
                    _buildErrorBanner(authState.error!),

                  _buildTextField(
                    controller: _deviceIdController,
                    label: 'Device ID',
                    icon: Icons.router_rounded,
                    hint: 'SPROUT_A1B2',
                  ),
                  const SizedBox(height: 20),
                  _buildTextField(
                    controller: _pinController,
                    label: 'Admin Password',
                    icon: Icons.lock_rounded,
                    obscure: true,
                    hint: 'Min. 8 chars · A-Z · 0-9 · @#!',
                  ),

                  // Pi-Bouncer status hint
                  const SizedBox(height: 16),
                  if (authState.isLoading)
                    _buildWaitingBanner()
                  else
                    const SizedBox.shrink(),

                  const SizedBox(height: 16),
                  _buildLoginButton(authState.isLoading),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2BCC71).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFF2BCC71).withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF2BCC71),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Contacting hardware...',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2BCC71),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    required String hint,
    int? maxLength,
    TextInputType? keyboardType,
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
        KioskTextFormField(
          controller: controller,
          obscureText: obscure,
          maxLength: maxLength,
          keyboardType: keyboardType,
          style: GoogleFonts.outfit(
              fontWeight: FontWeight.w600, color: const Color(0xFF0F2027)),
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            hintStyle: TextStyle(color: Colors.grey.withValues(alpha: 0.5)),
            prefixIcon: Icon(icon, color: const Color(0xFF2BCC71), size: 20),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: Color(0xFF2BCC71), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
          ),
          validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Required';
              return null;
            },
        ),
      ],
    );
  }

  Widget _buildLoginButton(bool isLoading) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0F2027),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
        child: Text(
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
    // "Hardware Offline" gets a special amber treatment
    final isOffline =
        message.contains('Offline') || message.contains('offline');
    final color = isOffline ? const Color(0xFFE67E22) : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.outfit(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600),
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

  Widget _buildAnimatedElement(int index, Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 800 + (index * 200)),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
