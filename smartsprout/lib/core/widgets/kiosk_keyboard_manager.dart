import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';

/// Manages a global onscreen keyboard for Linux kiosk mode.
class KioskKeyboardManager extends StatefulWidget {
  final Widget child;

  const KioskKeyboardManager({super.key, required this.child});

  @override
  State<KioskKeyboardManager> createState() => _KioskKeyboardManagerState();
}

class _KioskKeyboardManagerState extends State<KioskKeyboardManager> {
  OverlayEntry? _keyboardEntry;
  bool _isVisible = false;
  
  // Track focused field
  FocusNode? _currentFocus;
  late final KeyboardLayout _layout;
  final Set<String> _pressedActionKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _layout = const MobileKeyboardLayout();
    FocusManager.instance.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    _hideKeyboard();
    super.dispose();
  }

  void _onFocusChange() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != _currentFocus) {
      _currentFocus = focus;
      if (_currentFocus != null && _currentFocus!.context != null) {
        // Only show keyboard if the focused widget is an EditableText.
        final hasEditableText = focus!.consumeKeyboardToken();
        // Alternatively, check if contextual text input
        _showKeyboard();
      } else {
        _hideKeyboard();
      }
    }
  }

  void _showKeyboard() {
    if (_isVisible) return;
    _isVisible = true;

    if (_keyboardEntry == null) {
      _keyboardEntry = OverlayEntry(
        builder: (context) {
          return Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: const Color(0xFF1A2C2E),
              elevation: 24,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: RawOnscreenKeyboard(
                    layout: _layout,
                    mode: _layout.modes.keys.first,
                    pressedActionKeys: _pressedActionKeys,
                    onKeyDown: _onKeyDown,
                    onKeyUp: _onKeyUp,
                  ),
                ),
              ),
            ),
          );
        },
      );
      // Wait until next frame so Overlay is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isVisible && _keyboardEntry != null && !_keyboardEntry!.mounted) {
          Overlay.of(context).insert(_keyboardEntry!);
        }
      });
    } else {
      Overlay.of(context).insert(_keyboardEntry!);
    }
  }

  void _hideKeyboard() {
    if (!_isVisible) return;
    _isVisible = false;
    if (_keyboardEntry != null && _keyboardEntry!.mounted) {
      _keyboardEntry!.remove();
    }
  }

  bool get _showSecondary =>
      _pressedActionKeys.contains(ActionKeyType.capslock) ^
      _pressedActionKeys.contains(ActionKeyType.shift);

  void _onKeyDown(OnscreenKeyboardKey key) {
    if (_currentFocus == null || _currentFocus!.context == null) return;
    
    // We need to inject text into the currently focused EditableText.
    // However, FocusNode does not directly expose its TextEditingController.
    // We can use the platform TextInput mechanism.
  }

  void _onKeyUp(OnscreenKeyboardKey key) {
    if (key is ActionKey) {
      setState(() {
         // ...
      });
      _keyboardEntry?.markNeedsBuild();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
