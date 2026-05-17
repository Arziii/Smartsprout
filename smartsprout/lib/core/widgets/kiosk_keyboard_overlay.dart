import 'dart:async';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Smart Sprout — Linux Kiosk Keyboard System
// ═══════════════════════════════════════════════════════════════════════════
//
// Architecture:
//   ┌─────────────────────────────────────────────────────────────┐
//   │  KioskKeyboardHost  (wraps MaterialApp via builder:)        │
//   │  • Listens to KioskKeyboardService.isShowing                │
//   │  • Injects MediaQuery.viewInsets = keyboard height          │
//   │    → All Scaffolds with resizeToAvoidBottomInset:true       │
//   │      automatically push their body content upward           │
//   │  • Renders _SmartSproutKeyboard as animated overlay         │
//   └─────────────────────────────────────────────────────────────┘
//
//   ┌─────────────────────────────────────────────────────────────┐
//   │  KioskKeyboardService  (singleton)                          │
//   │  • Holds reference to the active TextEditingController      │
//   │    and FocusNode                                            │
//   │  • KioskTextFormField / KioskTextField call register()      │
//   │    on focus-gained and dismiss() on focus-lost              │
//   └─────────────────────────────────────────────────────────────┘
//
// NOTE: _SmartSproutKeyboard is built entirely from Flutter primitives.
//       We intentionally do NOT use RawOnscreenKeyboard from the
//       flutter_onscreen_keyboard package because it requires its own
//       OnscreenKeyboardTheme InheritedWidget ancestor (not exported
//       publicly), which caused keys to render as blank grey rectangles.

// ── Height constants ──────────────────────────────────────────────────────
const double _kKeyboardHeight = 305.0;
const Duration _kAnimDuration = Duration(milliseconds: 220);

// Palette
const _kBg = Color(0xFF14201F);          // keyboard panel background
const _kLetterKey = Color(0xFF2A3F41);   // alphanumeric key face
const _kActionKey = Color(0xFF1A2E30);   // action key face (darker)
const _kAccent = Color(0xFF4CAF82);      // green accent (shift active / enter)
const _kKeyText = Colors.white;
const _kActionText = Colors.white70;

// ═══════════════════════════════════════════════════════════════════════════
// KioskKeyboardService — Singleton state bus
// ═══════════════════════════════════════════════════════════════════════════
class KioskKeyboardService {
  KioskKeyboardService._();
  static final KioskKeyboardService instance = KioskKeyboardService._();

  /// Notifies [KioskKeyboardHost] to show or hide the panel.
  final ValueNotifier<bool> isShowing = ValueNotifier(false);

  TextEditingController? _activeController;
  FocusNode? _activeFocusNode;

  /// Short debounce used ONLY by the tap-outside barrier.
  /// Gives text-field onTap handlers time to call register() and cancel
  /// the dismiss before the timer fires (translucent barrier delivers both
  /// events simultaneously).
  Timer? _tapOutsideTimer;

  TextEditingController? get activeController => _activeController;
  FocusNode? get activeFocusNode => _activeFocusNode;

  // ── Peek-on-type (flash last character) ──────────────────────────────────
  // Registered by KioskTextField/KioskTextFormField when the field uses
  // obscureText. The keyboard calls triggerPeek() on every keystroke;  the
  // field briefly unobscures for 700 ms so the user can confirm the char.
  VoidCallback? _peekTrigger;

  /// Called when a [KioskTextField] / [KioskTextFormField] gains focus.
  /// Cancels any pending tap-outside dismiss so switching between fields
  /// or re-tapping an already-focused field keeps the keyboard visible.
  void register({
    required TextEditingController controller,
    required FocusNode focusNode,
    /// Optional callback fired after every keystroke when the field uses
    /// obscureText — lets the field briefly "peek" the last typed character.
    VoidCallback? peekTrigger,
  }) {
    _tapOutsideTimer?.cancel();
    _tapOutsideTimer = null;
    _activeController = controller;
    _activeFocusNode = focusNode;
    _peekTrigger = peekTrigger;
    isShowing.value = true;
  }

  /// Called by the full-screen tap-outside [Listener] barrier.
  ///
  /// Starts a 120 ms debounce. If [register] is called within that window
  /// (i.e. the user tapped a text field rather than blank space), the timer
  /// is cancelled and the keyboard stays open. Otherwise it dismisses.
  void startTapOutsideDismiss() {
    _tapOutsideTimer?.cancel();
    _tapOutsideTimer = Timer(const Duration(milliseconds: 120), () {
      _tapOutsideTimer = null;
      _activeController = null;
      _activeFocusNode = null;
      isShowing.value = false;
    });
  }

  /// Fires the peek callback registered by the active obscured field.
  /// Called after every successful keystroke from the keyboard.
  void triggerPeek() => _peekTrigger?.call();

  /// Synchronous dismiss — called from:
  ///   • widget dispose() (screen navigation cleanup)
  ///   • Enter key press
  ///   • Drag handle tap
  ///
  /// NOT called on focus-loss. The keyboard is now permanent until an
  /// explicit user action or the owning widget is removed from the tree.
  void dismissIfStillOwned(FocusNode callerNode) {
    if (_activeFocusNode != callerNode) return;
    _tapOutsideTimer?.cancel();
    _tapOutsideTimer = null;
    _peekTrigger = null;
    _activeController = null;
    _activeFocusNode = null;
    isShowing.value = false;
  }

  /// Force-dismiss: Enter key / drag handle.
  void dismiss() {
    _tapOutsideTimer?.cancel();
    _tapOutsideTimer = null;
    _peekTrigger = null;
    _activeController = null;
    _activeFocusNode = null;
    isShowing.value = false;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KioskKeyboardHost — Wraps MaterialApp, shows keyboard, adjusts MediaQuery
// ═══════════════════════════════════════════════════════════════════════════
class KioskKeyboardHost extends StatefulWidget {
  final Widget child;
  const KioskKeyboardHost({super.key, required this.child});

  @override
  State<KioskKeyboardHost> createState() => _KioskKeyboardHostState();
}

class _KioskKeyboardHostState extends State<KioskKeyboardHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  final _service = KioskKeyboardService.instance;
  bool _isPanelMounted = false;

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(vsync: this, duration: _kAnimDuration);

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );

    _service.isShowing.addListener(_onServiceStateChange);
  }

  @override
  void dispose() {
    _service.isShowing.removeListener(_onServiceStateChange);
    _animCtrl.dispose();
    super.dispose();
  }

  void _onServiceStateChange() {
    if (_service.isShowing.value) {
      setState(() => _isPanelMounted = true);
      _animCtrl.forward();
    } else {
      _animCtrl.reverse().then((_) {
        if (mounted) setState(() => _isPanelMounted = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = _service.isShowing.value;

    // Inject viewInsets.bottom so Scaffolds auto-push their content upward.
    final mq = MediaQuery.of(context);
    final injectedMq = mq.copyWith(
      viewInsets: mq.viewInsets.copyWith(
        bottom: isVisible ? _kKeyboardHeight : 0.0,
      ),
    );

    return MediaQuery(
      data: injectedMq,
      child: Stack(
        children: [
          widget.child,
          if (_isPanelMounted) ...[
            // ── Tap-outside barrier ───────────────────────────────────────────
            // Covers only the CONTENT AREA above the keyboard panel.
            // HitTestBehavior.translucent: this Listener AND the widgets
            // underneath (text fields, buttons) both receive the pointer event.
            // If the user tapped a text field, register() fires and cancels the
            // dismiss timer. If blank space was tapped, nothing cancels it and
            // the keyboard hides after 120 ms.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: _kKeyboardHeight,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _service.startTapOutsideDismiss(),
              ),
            ),
            // ── Keyboard panel (above the barrier) ──────────────────────────
            _buildKeyboardPanel(),
          ],
        ],
      ),
    );
  }

  Widget _buildKeyboardPanel() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          // ── ExcludeFocus: prevents ANY keyboard widget from stealing ──
          // focus away from the active text field. Without this, every
          // InkWell tap on Linux requests focus → field loses focus →
          // dismissIfStillOwned() nulls activeController → _type() no-ops.
          child: ExcludeFocus(
            excluding: true,
            child: Material(
              color: _kBg,
              elevation: 24,
              shadowColor: Colors.black54,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: _kKeyboardHeight,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Drag handle / dismiss strip ──
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _service.activeFocusNode?.unfocus();
                          _service.dismiss();
                        },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                      // ── Keyboard body ──
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
                          child: _SmartSproutKeyboard(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// _SmartSproutKeyboard — Self-contained QWERTY keyboard
// ═══════════════════════════════════════════════════════════════════════════
// Built entirely from Flutter primitives.
// No flutter_onscreen_keyboard InheritedWidget required.

enum _KbMode { lower, upper, numbers, symbols }

class _SmartSproutKeyboard extends StatefulWidget {
  const _SmartSproutKeyboard();

  @override
  State<_SmartSproutKeyboard> createState() => _SmartSproutKeyboardState();
}

class _SmartSproutKeyboardState extends State<_SmartSproutKeyboard> {
  _KbMode _mode = _KbMode.lower;
  bool _capsLock = false;

  // ── Layouts ──────────────────────────────────────────────────────────────

  static const _lettersRow1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
  static const _lettersRow2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
  static const _lettersRow3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

  static const _numbersRow1 = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
  static const _numbersRow2 = ['-', '/', ':', ';', '(', ')', r'$', '&', '@', '"'];
  static const _numbersRow3 = ['.', ',', '?', '!', "'"];

  static const _symbolsRow1 = ['[', ']', '{', '}', '#', '%', '^', '*', '+', '='];
  static const _symbolsRow2 = ['_', r'\', '|', '~', '<', '>', '€', '£', '¥', '•'];
  static const _symbolsRow3 = ['.', ',', '?', '!', "'"];

  // ── Text injection ────────────────────────────────────────────────────────

  void _type(String char) {
    final ctrl = KioskKeyboardService.instance.activeController;
    if (ctrl == null) return;
    final sel = ctrl.selection;
    final t = ctrl.text;
    if (sel.isValid) {
      final newText = t.replaceRange(sel.start, sel.end, char);
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: sel.start + char.length),
      );
    } else {
      ctrl.text = t + char;
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
    // Auto-release non-capslock shift after one character
    if (_mode == _KbMode.upper && !_capsLock) {
      setState(() => _mode = _KbMode.lower);
    }
    // Notify the active field to briefly flash the typed character if it
    // is currently in obscure mode (peek-on-type / iOS-style reveal).
    KioskKeyboardService.instance.triggerPeek();
  }

  void _backspace() {
    final ctrl = KioskKeyboardService.instance.activeController;
    if (ctrl == null || ctrl.text.isEmpty) return;
    final sel = ctrl.selection;
    if (sel.isValid && !sel.isCollapsed) {
      ctrl.value = TextEditingValue(
        text: ctrl.text.replaceRange(sel.start, sel.end, ''),
        selection: TextSelection.collapsed(offset: sel.start),
      );
    } else if (sel.isValid && sel.start > 0) {
      ctrl.value = TextEditingValue(
        text: ctrl.text.replaceRange(sel.start - 1, sel.start, ''),
        selection: TextSelection.collapsed(offset: sel.start - 1),
      );
    }
  }

  void _enter() {
    KioskKeyboardService.instance.activeFocusNode?.unfocus();
    KioskKeyboardService.instance.dismiss();
  }

  /// Shift state machine:
  ///  lower → tap → upper (one-shot)
  ///  upper (one-shot) → tap again → caps lock
  ///  caps lock → tap → lower
  void _toggleShift() {
    setState(() {
      if (_mode == _KbMode.lower) {
        _mode = _KbMode.upper;
        _capsLock = false;
      } else if (_mode == _KbMode.upper && !_capsLock) {
        _capsLock = true; // double-tap → caps lock
      } else {
        _mode = _KbMode.lower;
        _capsLock = false;
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_mode) {
      _KbMode.lower || _KbMode.upper => _buildLetterKb(),
      _KbMode.numbers => _buildNumberKb(),
      _KbMode.symbols => _buildSymbolKb(),
    };
  }

  // ── Letter keyboard ───────────────────────────────────────────────────────

  Widget _buildLetterKb() {
    final up = _mode == _KbMode.upper;
    return Column(
      children: [
        // Row 1: q–p
        _row(_lettersRow1.map((c) => _charKey(up ? c.toUpperCase() : c)).toList()),
        // Row 2: a–l
        _row(_lettersRow2.map((c) => _charKey(up ? c.toUpperCase() : c)).toList()),
        // Row 3: shift | z–m | ⌫
        _row([
          _actionKey(
            child: Icon(
              _capsLock
                  ? Icons.keyboard_capslock
                  : Icons.keyboard_arrow_up_rounded,
              size: 20,
              color: _mode == _KbMode.upper ? Colors.greenAccent : _kActionText,
            ),
            onTap: _toggleShift,
            highlight: _mode == _KbMode.upper,
          ),
          ..._lettersRow3.map((c) => _charKey(up ? c.toUpperCase() : c)),
          _actionKey(
            child: const Icon(Icons.backspace_outlined, size: 18, color: _kActionText),
            onTap: _backspace,
          ),
        ]),
        // Row 4: 123 | space | ↵
        _row([
          _actionKey(
            child: const Text('123', style: TextStyle(color: _kActionText, fontSize: 13)),
            onTap: () => setState(() => _mode = _KbMode.numbers),
            flex: 2,
          ),
          _charKey(' ', flex: 5, label: 'space'),
          _actionKey(
            child: const Icon(Icons.keyboard_return_rounded, size: 20, color: _kAccent),
            onTap: _enter,
            flex: 2,
          ),
        ]),
      ],
    );
  }

  // ── Number keyboard ───────────────────────────────────────────────────────

  Widget _buildNumberKb() {
    return Column(
      children: [
        _row(_numbersRow1.map(_charKey).toList()),
        _row(_numbersRow2.map(_charKey).toList()),
        _row([
          _actionKey(
            child: const Text('#+=', style: TextStyle(color: _kActionText, fontSize: 12)),
            onTap: () => setState(() => _mode = _KbMode.symbols),
            flex: 2,
          ),
          ..._numbersRow3.map(_charKey),
          _actionKey(
            child: const Icon(Icons.backspace_outlined, size: 18, color: _kActionText),
            onTap: _backspace,
            flex: 2,
          ),
        ]),
        _row([
          _actionKey(
            child: const Text('ABC', style: TextStyle(color: _kActionText, fontSize: 13)),
            onTap: () => setState(() => _mode = _KbMode.lower),
            flex: 2,
          ),
          _charKey(' ', flex: 5, label: 'space'),
          _actionKey(
            child: const Icon(Icons.keyboard_return_rounded, size: 20, color: _kAccent),
            onTap: _enter,
            flex: 2,
          ),
        ]),
      ],
    );
  }

  // ── Symbol keyboard ───────────────────────────────────────────────────────

  Widget _buildSymbolKb() {
    return Column(
      children: [
        _row(_symbolsRow1.map(_charKey).toList()),
        _row(_symbolsRow2.map(_charKey).toList()),
        _row([
          _actionKey(
            child: const Text('123', style: TextStyle(color: _kActionText, fontSize: 13)),
            onTap: () => setState(() => _mode = _KbMode.numbers),
            flex: 2,
          ),
          ..._symbolsRow3.map(_charKey),
          _actionKey(
            child: const Icon(Icons.backspace_outlined, size: 18, color: _kActionText),
            onTap: _backspace,
            flex: 2,
          ),
        ]),
        _row([
          _actionKey(
            child: const Text('ABC', style: TextStyle(color: _kActionText, fontSize: 13)),
            onTap: () => setState(() => _mode = _KbMode.lower),
            flex: 2,
          ),
          _charKey(' ', flex: 5, label: 'space'),
          _actionKey(
            child: const Icon(Icons.keyboard_return_rounded, size: 20, color: _kAccent),
            onTap: _enter,
            flex: 2,
          ),
        ]),
      ],
    );
  }

  // ── Widget primitives ─────────────────────────────────────────────────────

  /// One keyboard row — each key is an Expanded child.
  Widget _row(List<Widget> keys) => Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: keys,
        ),
      );

  /// A character key, typed on tap.
  /// canRequestFocus: false + onTapDown (not onTap) means:
  ///   - No focus is requested from this widget
  ///   - Response fires on finger-down, not on finger-up (snappier on touch)
  Widget _charKey(String char, {int flex = 1, String? label}) => Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: _kLetterKey,
            borderRadius: BorderRadius.circular(7),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              canRequestFocus: false,
              onTapDown: (_) => _type(char),
              child: Center(
                child: label != null
                    ? Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          letterSpacing: 0.5,
                        ),
                      )
                    : Text(
                        char,
                        style: const TextStyle(
                          color: _kKeyText,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
          ),
        ),
      );

  /// An action key (shift, backspace, enter, mode switch).
  Widget _actionKey({
    required Widget child,
    required VoidCallback onTap,
    int flex = 1,
    bool highlight = false,
  }) =>
      Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: highlight ? _kAccent : _kActionKey,
            borderRadius: BorderRadius.circular(7),
            child: InkWell(
              borderRadius: BorderRadius.circular(7),
              canRequestFocus: false,
              onTapDown: (_) => onTap(),
              child: Center(child: child),
            ),
          ),
        ),
      );
}
