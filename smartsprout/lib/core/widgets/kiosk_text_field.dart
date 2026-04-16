import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'kiosk_keyboard_overlay.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Smart Sprout — Kiosk-Aware Text Widgets
// ═══════════════════════════════════════════════════════════════════════════
//
// On Linux (Raspberry Pi kiosk):
//   • keyboardType is forced to TextInputType.none to suppress the system
//     IME (there is no physical OS keyboard in kiosk mode).
//   • On focus-gained, the field registers its controller + FocusNode with
//     KioskKeyboardService, which signals KioskKeyboardHost to show the
//     on-screen keyboard overlay.
//   • Keyboard visibility is decoupled from focus state — it dismisses only
//     via Enter, drag-handle, tap-outside barrier, or screen dispose().
//
// On Android / iOS:
//   • Renders as a standard TextFormField / TextField with the system keyboard.
//
// ── Obscure / show-password features (both widgets) ──────────────────────
//
//   Eye-icon toggle:
//     Automatically injected into the InputDecoration suffixIcon when
//     obscureText == true AND the caller did not already provide a suffixIcon.
//     Tapping it permanently reveals or re-hides the field contents.
//     Callers that manage their own suffixIcon (e.g. pairing_screen.dart)
//     are unaffected — their icon takes precedence.
//
//   Peek-on-type (iOS-style character flash):
//     When a character is typed via the kiosk keyboard while the field is in
//     obscure mode, the field briefly shows its contents for 700 ms, then
//     re-obscures. This gives the premium "you can see what you typed"
//     feel without requiring the user to touch the eye icon.
//     If the user has already toggled reveal (permanent), peek is skipped.
//
// Usage: drop-in replacements for TextFormField and TextField.

// ═══════════════════════════════════════════════════════════════════════════
// KioskTextFormField
// ═══════════════════════════════════════════════════════════════════════════
class KioskTextFormField extends StatefulWidget {
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final bool obscureText;
  final bool autofocus;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final bool readOnly;
  final TextAlign textAlign;
  final String? Function(String?)? validator;

  const KioskTextFormField({
    super.key,
    this.controller,
    this.decoration,
    this.obscureText = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.style,
    this.inputFormatters,
    this.focusNode,
    this.readOnly = false,
    this.textAlign = TextAlign.start,
    this.validator,
  });

  @override
  State<KioskTextFormField> createState() => _KioskTextFormFieldState();
}

class _KioskTextFormFieldState extends State<KioskTextFormField> {
  late TextEditingController _ctrl;
  late FocusNode _focus;
  bool _ownCtrl = false;
  bool _ownFocus = false;

  // ── Obscure state ─────────────────────────────────────────────────────────
  // _userObscure: the user's persistent preference (toggled by the eye icon).
  //               Initialised from widget.obscureText; synced via didUpdateWidget.
  // _obscure:     the live display state — briefly flips to false during the
  //               700 ms "peek" animation triggered by each kiosk keystroke.
  late bool _userObscure;
  late bool _obscure;
  Timer? _peekTimer;

  @override
  void initState() {
    super.initState();
    _userObscure = widget.obscureText;
    _obscure = widget.obscureText;

    _ctrl = widget.controller ?? (_ownCtrl = true, TextEditingController()).$2;
    _focus = widget.focusNode ?? (_ownFocus = true, FocusNode()).$2;

    if (Platform.isLinux && !widget.readOnly) {
      _focus.addListener(_onFocusChange);
    }
  }

  @override
  void didUpdateWidget(KioskTextFormField old) {
    super.didUpdateWidget(old);
    // Sync when the parent explicitly changes obscureText (e.g. external toggle
    // in pairing_screen.dart that manages its own _obscurePin state).
    if (old.obscureText != widget.obscureText) {
      setState(() {
        _userObscure = widget.obscureText;
        _obscure = widget.obscureText;
      });
    }
  }

  @override
  void dispose() {
    _peekTimer?.cancel();
    if (Platform.isLinux && !widget.readOnly) {
      _focus.removeListener(_onFocusChange);
      KioskKeyboardService.instance.dismissIfStillOwned(_focus);
    }
    if (_ownCtrl) _ctrl.dispose();
    if (_ownFocus) _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      KioskKeyboardService.instance.register(
        controller: _ctrl,
        focusNode: _focus,
        // Only register peek callback for obscured fields.
        peekTrigger: widget.obscureText ? _peekChar : null,
      );
    }
    // Focus-loss intentionally ignored — keyboard stays until explicit dismiss.
  }

  /// Briefly reveals the field for 700 ms, then re-obscures.
  /// No-op when the user already toggled permanent-reveal mode.
  void _peekChar() {
    if (!mounted || !_userObscure) return;
    _peekTimer?.cancel();
    setState(() => _obscure = false);
    _peekTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _obscure = _userObscure);
    });
  }

  /// Returns the caller's decoration merged with an eye-icon suffix button.
  /// The button is injected only when:
  ///   • widget.obscureText == true   (a password / PIN field)
  ///   • The caller has not already supplied a suffixIcon
  InputDecoration _decoration() {
    final base = widget.decoration ?? const InputDecoration();
    if (!widget.obscureText || base.suffixIcon != null) return base;

    return base.copyWith(
      suffixIcon: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _peekTimer?.cancel();
          _userObscure = !_userObscure;
          _obscure = _userObscure;
        }),
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            _userObscure
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            color: Colors.grey.withValues(alpha: 0.55),
            size: 20,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _ctrl,
      focusNode: _focus,
      decoration: _decoration(),
      // Use live _obscure (affected by peek) rather than widget.obscureText
      obscureText: _obscure,
      autofocus: widget.autofocus,
      // Obscured fields must stay single-line regardless of widget.maxLines
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      keyboardType: Platform.isLinux ? TextInputType.none : widget.keyboardType,
      onChanged: widget.onChanged,
      onEditingComplete: widget.onEditingComplete,
      onFieldSubmitted: widget.onSubmitted,
      style: widget.style,
      inputFormatters: widget.inputFormatters,
      readOnly: widget.readOnly,
      textAlign: widget.textAlign,
      validator: widget.validator,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// KioskTextField
// ═══════════════════════════════════════════════════════════════════════════
class KioskTextField extends StatefulWidget {
  final TextEditingController? controller;
  final InputDecoration? decoration;
  final bool obscureText;
  final bool autofocus;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? style;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final bool readOnly;
  final TextAlign textAlign;

  const KioskTextField({
    super.key,
    this.controller,
    this.decoration,
    this.obscureText = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.style,
    this.inputFormatters,
    this.focusNode,
    this.readOnly = false,
    this.textAlign = TextAlign.start,
  });

  @override
  State<KioskTextField> createState() => _KioskTextFieldState();
}

class _KioskTextFieldState extends State<KioskTextField> {
  late TextEditingController _ctrl;
  late FocusNode _focus;
  bool _ownCtrl = false;
  bool _ownFocus = false;

  // ── Obscure state (mirrors KioskTextFormField logic) ─────────────────────
  late bool _userObscure;
  late bool _obscure;
  Timer? _peekTimer;

  @override
  void initState() {
    super.initState();
    _userObscure = widget.obscureText;
    _obscure = widget.obscureText;

    _ctrl = widget.controller ?? (_ownCtrl = true, TextEditingController()).$2;
    _focus = widget.focusNode ?? (_ownFocus = true, FocusNode()).$2;

    if (Platform.isLinux && !widget.readOnly) {
      _focus.addListener(_onFocusChange);
    }
  }

  @override
  void didUpdateWidget(KioskTextField old) {
    super.didUpdateWidget(old);
    if (old.obscureText != widget.obscureText) {
      setState(() {
        _userObscure = widget.obscureText;
        _obscure = widget.obscureText;
      });
    }
  }

  @override
  void dispose() {
    _peekTimer?.cancel();
    if (Platform.isLinux && !widget.readOnly) {
      _focus.removeListener(_onFocusChange);
      KioskKeyboardService.instance.dismissIfStillOwned(_focus);
    }
    if (_ownCtrl) _ctrl.dispose();
    if (_ownFocus) _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      KioskKeyboardService.instance.register(
        controller: _ctrl,
        focusNode: _focus,
        peekTrigger: widget.obscureText ? _peekChar : null,
      );
    }
  }

  void _peekChar() {
    if (!mounted || !_userObscure) return;
    _peekTimer?.cancel();
    setState(() => _obscure = false);
    _peekTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _obscure = _userObscure);
    });
  }

  InputDecoration _decoration() {
    final base = widget.decoration ?? const InputDecoration();
    if (!widget.obscureText || base.suffixIcon != null) return base;

    return base.copyWith(
      suffixIcon: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _peekTimer?.cancel();
          _userObscure = !_userObscure;
          _obscure = _userObscure;
        }),
        child: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            _userObscure
                ? Icons.visibility_off_rounded
                : Icons.visibility_rounded,
            color: Colors.grey.withValues(alpha: 0.55),
            size: 20,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      decoration: _decoration(),
      obscureText: _obscure,
      autofocus: widget.autofocus,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      keyboardType: Platform.isLinux ? TextInputType.none : widget.keyboardType,
      onChanged: widget.onChanged,
      onEditingComplete: widget.onEditingComplete,
      onSubmitted: widget.onSubmitted,
      style: widget.style,
      inputFormatters: widget.inputFormatters,
      readOnly: widget.readOnly,
      textAlign: widget.textAlign,
    );
  }
}
