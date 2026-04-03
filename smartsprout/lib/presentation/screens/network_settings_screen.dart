import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class WifiNetwork {
  final String ssid;
  final int signal;
  final String strength; // "strong" | "medium" | "weak"
  final bool secured;
  final bool connected;

  const WifiNetwork({
    required this.ssid,
    required this.signal,
    required this.strength,
    required this.secured,
    required this.connected,
  });

  factory WifiNetwork.fromJson(Map<String, dynamic> j) => WifiNetwork(
        ssid: j['ssid'] ?? '',
        signal: j['signal'] ?? 0,
        strength: j['strength'] ?? 'weak',
        secured: j['secured'] ?? true,
        connected: j['connected'] ?? false,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Service — talks to wifi_bridge.py on port 7788
// ─────────────────────────────────────────────────────────────────────────────

class _WifiService {
  static const _base = 'http://127.0.0.1:7788';

  static Future<Map<String, dynamic>> _get(String path) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$_base$path'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  static Future<List<WifiNetwork>> scan() async {
    final data = await _get('/scan');
    final list = data['networks'] as List<dynamic>? ?? [];
    return list.map((e) => WifiNetwork.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Map<String, dynamic>> connect(String ssid, String password) =>
      _get('/connect?ssid=${Uri.encodeComponent(ssid)}&password=${Uri.encodeComponent(password)}');

  static Future<Map<String, dynamic>> forget(String ssid) =>
      _get('/forget?ssid=${Uri.encodeComponent(ssid)}');

  static Future<Map<String, dynamic>> status() => _get('/status');
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({super.key});

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  List<WifiNetwork> _networks = [];
  bool _scanning = false;
  String _connectedSsid = '';
  String? _statusMessage;
  bool _statusSuccess = true;

  @override
  void initState() {
    super.initState();
    _checkCurrentStatus();
  }

  Future<void> _checkCurrentStatus() async {
    try {
      final data = await _WifiService.status();
      if (mounted) {
        setState(() {
          _connectedSsid = data['connected'] == true ? (data['ssid'] ?? '') : '';
        });
      }
    } catch (_) {}
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _statusMessage = null;
    });
    try {
      final nets = await _WifiService.scan();
      if (mounted) setState(() => _networks = nets);
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Could not reach Wi-Fi bridge. Is wifi_bridge.py running?';
          _statusSuccess = false;
        });
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _showPasswordSheet(WifiNetwork net) async {
    // If unsecured, connect directly
    if (!net.secured) {
      await _connect(net.ssid, '');
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PasswordSheet(
        ssid: net.ssid,
        onConnect: (password) => _connect(net.ssid, password),
      ),
    );
  }

  Future<void> _connect(String ssid, String password) async {
    setState(() {
      _statusMessage = 'Connecting to $ssid…';
      _statusSuccess = true;
    });
    try {
      final result = await _WifiService.connect(ssid, password);
      final success = result['success'] == true;
      if (mounted) {
        setState(() {
          _statusMessage = result['message'] ?? (success ? 'Connected!' : 'Failed');
          _statusSuccess = success;
          if (success) _connectedSsid = ssid;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error: $e';
          _statusSuccess = false;
        });
      }
    }
  }

  Future<void> _forget(String ssid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2A2F),
        title: Text('Forget "$ssid"?',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text('This will remove the saved password for this network.',
            style: GoogleFonts.outfit(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white54))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Forget', style: GoogleFonts.outfit(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await _WifiService.forget(ssid);
      final success = result['success'] == true;
      if (mounted) {
        setState(() {
          _statusMessage = result['message'] ?? (success ? 'Network forgotten.' : 'Failed');
          _statusSuccess = success;
          if (success) {
            _networks.removeWhere((n) => n.ssid == ssid);
            if (_connectedSsid == ssid) _connectedSsid = '';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() { _statusMessage = 'Error: $e'; _statusSuccess = false; });
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  IconData _signalIcon(String strength) {
    switch (strength) {
      case 'strong': return Icons.signal_wifi_4_bar_rounded;
      case 'medium': return Icons.network_wifi_3_bar_rounded;
      default:       return Icons.network_wifi_1_bar_rounded;
    }
  }

  Color _signalColor(String strength) {
    switch (strength) {
      case 'strong': return const Color(0xFF2BCC71);
      case 'medium': return const Color(0xFFFFA726);
      default:       return Colors.redAccent;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Network Settings',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F2027),
                letterSpacing: -0.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0F2027), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // Background gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE0ECE9), Color(0xFFB4CDCA)],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),

                // ── Current Status Banner ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildStatusBanner(),
                ),

                const SizedBox(height: 16),

                // ── Status / Error Message ────────────────────────────────
                if (_statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _statusSuccess
                            ? const Color(0xFF2BCC71).withValues(alpha: 0.15)
                            : Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _statusSuccess
                              ? const Color(0xFF2BCC71).withValues(alpha: 0.4)
                              : Colors.redAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _statusSuccess ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                            color: _statusSuccess ? const Color(0xFF2BCC71) : Colors.redAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_statusMessage!,
                                style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _statusSuccess
                                        ? const Color(0xFF2BCC71)
                                        : Colors.redAccent)),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // ── Scan Button ───────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _scanning ? null : _scan,
                      icon: _scanning
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.wifi_find_rounded, size: 20),
                      label: Text(_scanning ? 'Scanning…' : 'Scan for Wi-Fi',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2BCC71),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Network List ──────────────────────────────────────────
                Expanded(
                  child: _networks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.wifi_off_rounded, size: 60,
                                  color: const Color(0xFF4A6164).withValues(alpha: 0.3)),
                              const SizedBox(height: 12),
                              Text('No networks found.\nPress Scan to search.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                      color: const Color(0xFF4A6164).withValues(alpha: 0.5),
                                      fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: _networks.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _buildNetworkTile(_networks[i]),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final connected = _connectedSsid.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: connected
            ? const Color(0xFF2BCC71).withValues(alpha: 0.12)
            : Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: connected
              ? const Color(0xFF2BCC71).withValues(alpha: 0.4)
              : Colors.orange.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
            color: connected ? const Color(0xFF2BCC71) : Colors.orange,
            size: 22,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(connected ? 'Connected' : 'Not Connected',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: connected ? const Color(0xFF2BCC71) : Colors.orange)),
              if (connected)
                Text(_connectedSsid,
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: const Color(0xFF4A6164))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkTile(WifiNetwork net) {
    final isConnected = net.ssid == _connectedSsid;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: isConnected
            ? Border.all(color: const Color(0xFF2BCC71), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: () => _showPasswordSheet(net),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _signalColor(net.strength).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(_signalIcon(net.strength),
              color: _signalColor(net.strength), size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(net.ssid,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: const Color(0xFF0F2027))),
            ),
            if (isConnected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF2BCC71).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Connected',
                    style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2BCC71))),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Icon(
              net.secured ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 12,
              color: const Color(0xFF4A6164).withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(net.secured ? 'Secured' : 'Open',
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: const Color(0xFF4A6164).withValues(alpha: 0.6))),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded,
              color: Colors.redAccent.withValues(alpha: 0.7), size: 20),
          tooltip: 'Forget network',
          onPressed: () => _forget(net.ssid),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Password Sheet — Full QWERTY + Numbers
// ─────────────────────────────────────────────────────────────────────────────

class _PasswordSheet extends StatefulWidget {
  final String ssid;
  final Future<void> Function(String password) onConnect;

  const _PasswordSheet({required this.ssid, required this.onConnect});

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _connecting = false;

  Future<void> _submit() async {
    if (_controller.text.isEmpty) return;
    setState(() => _connecting = true);
    await widget.onConnect(_controller.text.trim());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: EdgeInsets.only(
          left: 24, right: 24, top: 24, bottom: 24 + bottomInset),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2027), Color(0xFF1A3A3A)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white54, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Enter Password',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            color: Colors.white)),
                    Text(widget.ssid,
                        style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: const Color(0xFF2BCC71),
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Password field — uses the system QWERTY keyboard on Linux
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Wi-Fi Password',
              hintStyle: GoogleFonts.outfit(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.08),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: Colors.white38),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Connect Button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _connecting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2BCC71),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _connecting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : Text('Connect',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
