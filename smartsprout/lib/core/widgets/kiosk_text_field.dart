import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';

// ═══════════════════════════════════════════════════════
// Smart Sprout — Kiosk-Aware Text Fields
// ═══════════════════════════════════════════════════════

class KioskKeyboardWrapper extends StatefulWidget {
  final Widget child;
  final TextEditingController controller;
  final FocusNode focusNode;

  const KioskKeyboardWrapper({
    super.key,
    required this.child,
    required this.controller,
    required this.focusNode,
  });

  @override
  State<KioskKeyboardWrapper> createState() => _KioskKeyboardWrapperState();
}

class _KioskKeyboardWrapperState extends State<KioskKeyboardWrapper> {
  PersistentBottomSheetController? _sheetController;
  final Set<String> _pressedActionKeys = {};
  
  bool get _showSecondary =>
      _pressedActionKeys.contains('capslock') ^
      _pressedActionKeys.contains('shift');

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _closeKeyboard();
    super.dispose();
  }

  void _onFocusChange() {
    if (widget.focusNode.hasFocus) {
      _openKeyboard();
    } else {
      _closeKeyboard();
    }
  }

  void _openKeyboard() {
    if (_sheetController != null) return;
    
    // We use a bottom sheet wrapper on the nearest scaffold.
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold == null) return;

    final layout = const MobileKeyboardLayout();
    
    _sheetController = scaffold.showBottomSheet(
      (ctx) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: const Color(0xFF1A1A1A),
        padding: const EdgeInsets.only(bottom: 24, top: 8),
        child: StatefulBuilder(
          builder: (context, setStateSheet) {
            return SafeArea(
              child: SizedBox(
                height: 250,
                child: RawOnscreenKeyboard(
                  layout: layout,
                  mode: layout.modes.keys.first,
                  pressedActionKeys: _pressedActionKeys,
                  showSecondary: _showSecondary,
                  onKeyDown: (key) {
                    if (key is TextKey) {
                      _handleTextKey(key);
                    } else if (key is ActionKey) {
                      _handleActionKey(key, setStateSheet);
                    }
                  },
                  onKeyUp: (key) {
                    if (key is ActionKey && key.canHold) {
                      setStateSheet(() {
                        if (!_pressedActionKeys.contains(key.name)) {
                          _pressedActionKeys.add(key.name);
                        } else {
                          _pressedActionKeys.remove(key.name);
                        }
                      });
                    }
                  },
                ),
              ),
            );
          }
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 24,
    );

    _sheetController?.closed.then((_) {
      _sheetController = null;
      if (widget.focusNode.hasFocus) {
        widget.focusNode.unfocus();
      }
    });
  }

  void _closeKeyboard() {
    _sheetController?.close();
    _sheetController = null;
  }

  void _handleTextKey(TextKey key) {
    final keyText = key.getText(secondary: _showSecondary);
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    
    if (selection.isValid) {
      final newText = text.replaceRange(selection.start, selection.end, keyText);
      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + keyText.length),
      );
    } else {
      widget.controller.text = text + keyText;
      widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
    }
  }

  void _handleActionKey(ActionKey key, void Function(void Function()) setStateSheet) {
    if (!key.canHold) {
      setStateSheet(() => _pressedActionKeys.add(key.name));
    }
    
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    
    switch (key.name) {
      case 'backspace':
        if (text.isEmpty) return;
        if (selection.isValid && !selection.isCollapsed) {
          final newText = text.replaceRange(selection.start, selection.end, '');
          widget.controller.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: selection.start),
          );
        } else if (selection.isValid && selection.start > 0) {
          final newText = text.replaceRange(selection.start - 1, selection.start, '');
          widget.controller.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: selection.start - 1),
          );
        }
        break;
      case 'enter':
        widget.focusNode.unfocus();
        break;
      case 'tab':
        widget.focusNode.nextFocus();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class KioskTextField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final effectiveController = controller ?? TextEditingController();
    final effectiveFocusNode = focusNode ?? FocusNode();

    Widget field = TextField(
      controller: effectiveController,
      focusNode: effectiveFocusNode,
      decoration: decoration,
      obscureText: obscureText,
      autofocus: autofocus,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: Platform.isLinux ? TextInputType.none : keyboardType,
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      onSubmitted: onSubmitted,
      style: style,
      inputFormatters: inputFormatters,
      readOnly: readOnly,
      textAlign: textAlign,
    );

    if (Platform.isLinux && !readOnly) {
      return KioskKeyboardWrapper(
        controller: effectiveController,
        focusNode: effectiveFocusNode,
        child: field,
      );
    }
    return field;
  }
}

class KioskTextFormField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final effectiveController = controller ?? TextEditingController();
    final effectiveFocusNode = focusNode ?? FocusNode();

    Widget field = TextFormField(
      controller: effectiveController,
      focusNode: effectiveFocusNode,
      decoration: decoration,
      obscureText: obscureText,
      autofocus: autofocus,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: Platform.isLinux ? TextInputType.none : keyboardType,
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      onFieldSubmitted: onSubmitted,
      style: style,
      inputFormatters: inputFormatters,
      readOnly: readOnly,
      textAlign: textAlign,
      validator: validator,
    );

    if (Platform.isLinux && !readOnly) {
      return KioskKeyboardWrapper(
        controller: effectiveController,
        focusNode: effectiveFocusNode,
        child: field,
      );
    }
    return field;
  }
}
