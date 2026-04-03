import 'dart:io';
import 'dart:ui';
import '../core/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/providers/auth_provider.dart';
import '../presentation/screens/hardware_login_screen.dart';
import '../screens/dashboard_page.dart';
import '../presentation/screens/control_screen.dart';
import '../presentation/screens/analytics_screen.dart';
import '../presentation/screens/settings_screen.dart';
import '../presentation/screens/pairing_screen.dart';
import '../presentation/screens/calibration_screen.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'shell');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    // Start on the dashboard immediately for Linux, login for mobile
    initialLocation: Platform.isLinux ? '/dashboard' : '/login',
    redirect: (context, state) {
      // Hard guard at the top to ensure Raspberry Pi ignores auth states
      if (Platform.isLinux) return null;

      final authState = ref.read(authProvider);
      final isLoggedIn = authState.deviceId != null;
      final isLoggingIn = state.matchedLocation == '/login';

      // If still loading initial state from local storage, don't redirect yet
      if (authState.isLoading && !isLoggedIn) {
        return null;
      }

      if (!isLoggedIn) {
        return isLoggingIn ? null : '/login';
      }

      if (isLoggedIn && isLoggingIn) {
        return '/dashboard'; // default after login
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const HardwareLoginScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          final location = GoRouterState.of(context).matchedLocation;
          final showNavBar = location != '/pairing' && location != '/login';
          return ScaffoldWithNavBar(showNavBar: showNavBar, child: child);
        },
        routes: [
          GoRoute(
            path: '/pairing',
            pageBuilder: (context, state) => _buildPage(state, const PairingScreen()),
          ),
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => _buildPage(state, const DashboardPage()),
          ),
          GoRoute(
            path: '/control',
            pageBuilder: (context, state) => _buildPage(state, const ControlScreen()),
          ),
          GoRoute(
            path: '/analytics',
            pageBuilder: (context, state) => _buildPage(state, const AnalyticsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _buildPage(state, const SettingsScreen()),
          ),
          GoRoute(
            path: '/calibration',
            pageBuilder: (context, state) => _buildPage(state, const CalibrationScreen()),
          ),
        ],
      ),
    ],
  );
});

Page<dynamic> _buildPage(GoRouterState state, Widget child) {
  return Platform.isLinux
      ? NoTransitionPage(key: state.pageKey, child: child)
      : MaterialPage(key: state.pageKey, child: child);
}

// ─────────────────────────────────────────────
// ScaffoldWithNavBar — premium frosted-glass nav
// ─────────────────────────────────────────────
class ScaffoldWithNavBar extends StatelessWidget {
  final Widget child;
  final bool showNavBar;

  const ScaffoldWithNavBar({
    required this.child,
    this.showNavBar = true,
    super.key,
  });

  static const _navItems = [
    _NavItemData(icon: Icons.home_filled, label: 'Home', path: '/dashboard'),
    _NavItemData(
        icon: Icons.health_and_safety, label: 'Diagnose', path: '/analytics'),
    _NavItemData(icon: Icons.grass, label: 'My Garden', path: '/control'),
    _NavItemData(icon: Icons.person, label: 'Profile', path: '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _navItems
        .indexWhere(
          (item) => location.startsWith(item.path),
        )
        .clamp(0, _navItems.length - 1);

    return Scaffold(
      extendBody: true, // content flows under transparent nav bar
      backgroundColor: Colors.transparent,
      body: child,
      bottomNavigationBar: showNavBar
          ? _FrostedNavBar(
              items: _navItems,
              selectedIndex: selectedIndex,
              onTap: (path) => context.go(path),
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────
// _FrostedNavBar — glassmorphism Tab Menu
// ─────────────────────────────────────────────
class _FrostedNavBar extends StatelessWidget {
  final List<_NavItemData> items;
  final int selectedIndex;
  final void Function(String path) onTap;

  const _FrostedNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / items.length;
          const circleSize = 56.0;
          final leftOffset = (tabWidth * selectedIndex) + (tabWidth - circleSize) / 2;

          final background = Container(
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: isLiteMode ? 1.0 : 0.60),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.50),
                  width: 1.0,
                ),
              ),
            ),
          );

          return SizedBox(
            height: 88, // 68 bar + 20 float space
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Frosted Bar Background
                Positioned(
                  left: 0, right: 0, bottom: 0, height: 68,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: isLiteMode ? null : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 24,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: isPremiumMode ? ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: background,
                      ),
                    ) : background,
                  ),
                ),

                // 2. Animated Floating Circle
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutBack,
                  top: 0, // Top of the 88px container
                  left: leftOffset,
                  child: Container(
                    width: circleSize,
                    height: circleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary,
                      boxShadow: [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Foreground Icons & Labels
                Positioned.fill(
                  child: Row(
                    children: List.generate(items.length, (i) {
                      return SizedBox(
                        width: tabWidth,
                        height: 88,
                        child: _NavButton(
                          data: items[i],
                          isSelected: i == selectedIndex,
                          activeColor: primary,
                          onTap: () => onTap(items[i].path),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _NavButton — handles popping icon up and showing text
// ─────────────────────────────────────────────
class _NavButton extends StatefulWidget {
  final _NavItemData data;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _NavButton({
    required this.data,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_NavButton old) {
    super.didUpdateWidget(old);
    // Scale animation not strictly needed for selection anymore, 
    // but kept for tap down/up feedback
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unselectedColor = Colors.grey.shade500;

    return Semantics(
      label: widget.data.label,
      button: true,
      selected: widget.isSelected,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return Transform.scale(
              scale: _scale.value, // squish on press
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Label — slides up and fades in
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    bottom: widget.isSelected ? 14.0 : -20.0,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: widget.isSelected ? 1.0 : 0.0,
                      child: Text(
                        widget.data.label,
                        style: TextStyle(
                          color: widget.activeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),

                  // Icon — slides up into the floating circle
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    bottom: widget.isSelected ? 48.0 : 22.0,
                    child: Icon(
                      widget.data.icon,
                      size: 26,
                      color: widget.isSelected ? Colors.white : unselectedColor,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────
class _NavItemData {
  final IconData icon;
  final String label;
  final String path;
  const _NavItemData({
    required this.icon,
    required this.label,
    required this.path,
  });
}
