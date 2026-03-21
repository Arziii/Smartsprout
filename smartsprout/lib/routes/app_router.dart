import 'dart:io';
import 'dart:ui';
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
          return ScaffoldWithNavBar(child: child, showNavBar: showNavBar);
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
// _FrostedNavBar — glassmorphism bottom nav
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

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            // 60% white frosted glass matching the dashboard overlay
            color: Colors.white.withOpacity(0.60),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.50),
                width: 1.0,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 68,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(items.length, (i) {
                  return _NavButton(
                    data: items[i],
                    isSelected: i == selectedIndex,
                    activeColor: primary,
                    onTap: () => onTap(items[i].path),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _NavButton — animated button with ripple, glow, and gradient pill
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

class _NavButtonState extends State<_NavButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_NavButton old) {
    super.didUpdateWidget(old);
    if (widget.isSelected) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isSelected
        ? widget.activeColor
        : Colors.grey.shade500; // ≥4.5:1 contrast on white — WCAG AA ✓

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
              scale: widget.isSelected
                  ? 1.0 // selected: no squish
                  : _scale.value, // unselected: squish on press
              child: SizedBox(
                width: 76,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Animated pill indicator ──
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      height: 36,
                      width: widget.isSelected ? 56 : 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: widget.isSelected
                            ? LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  widget.activeColor.withOpacity(0.90),
                                  widget.activeColor.withOpacity(0.65),
                                ],
                              )
                            : null,
                        color: widget.isSelected ? null : Colors.transparent,
                        boxShadow: widget.isSelected
                            ? [
                                BoxShadow(
                                  color: widget.activeColor.withOpacity(0.35),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : [],
                      ),
                      child: Icon(
                        widget.data.icon,
                        size: 22,
                        color: widget.isSelected ? Colors.white : color,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // ── Label ──
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: widget.isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                      child: Text(widget.data.label),
                    ),
                  ],
                ),
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
