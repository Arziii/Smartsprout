import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';

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
        content: Text("Are you sure you want to remove ${device.nickname}? You'll need to enter the PIN to add it again.", style: GoogleFonts.outfit()),
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
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Text(
                  'Switch Accounts',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F2027),
                  ),
                ),
                const SizedBox(height: 24),
                
                if (devices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('No saved accounts yet.', style: TextStyle(color: Colors.grey.shade600)),
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
                            color: isActive ? const Color(0xFF2BCC71).withOpacity(0.1) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isActive ? const Color(0xFF2BCC71) : Colors.grey.shade200,
                              width: 2,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: isActive ? const Color(0xFF2BCC71) : const Color(0xFF4A6164),
                              child: _isLoading && !isActive && device.deviceId != currentDevice
                                  ? const Icon(Icons.grass_rounded, color: Colors.white)
                                  : isActive ? const Icon(Icons.check_rounded, color: Colors.white) : const Icon(Icons.grass_rounded, color: Colors.white),
                            ),
                            title: Text(
                              device.nickname,
                              style: GoogleFonts.outfit(
                                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                                fontSize: 16,
                                color: const Color(0xFF0F2027),
                              ),
                            ),
                            subtitle: Text(
                              device.deviceId,
                              style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit_rounded, color: Colors.grey.shade400, size: 20),
                                  onPressed: () => _showEditNicknameDialog(device),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 20),
                                  onPressed: () => _confirmDelete(device),
                                ),
                              ],
                            ),
                            onTap: isActive || _isLoading ? null : () => _handleSwitch(device.deviceId),
                          ),
                        );
                      },
                    ),
                  ),
                  
                const SizedBox(height: 16),
                
                if (devices.length < 5)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add_rounded),
                      label: Text('Add New Device', style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F2027),
                        side: BorderSide(color: Colors.grey.shade300, width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        context.pop();
                        // Assuming /login doesn't erase state, or we just push it
                        context.push('/login');
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
