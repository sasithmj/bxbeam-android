import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OverlayPermissionHelper {
  static const MethodChannel _channel = MethodChannel('com.example.bxbeam/overlay_permission');

  /// Checks if the "Display over other apps" (overlay) permission is granted.
  static Future<bool> checkPermission() async {
    try {
      final bool result = await _channel.invokeMethod('checkOverlayPermission');
      return result;
    } on PlatformException catch (e) {
      debugPrint("Failed to check overlay permission: ${e.message}");
      return false;
    }
  }

  /// Directs the user to the system settings page to grant overlay permission.
  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } on PlatformException catch (e) {
      debugPrint("Failed to request overlay permission: ${e.message}");
    }
  }

  /// Checks if the app is exempt from battery optimizations.
  static Future<bool> checkBatteryOptimization() async {
    try {
      final bool result = await _channel.invokeMethod('checkBatteryOptimization');
      return result;
    } on PlatformException catch (e) {
      debugPrint("Failed to check battery optimization: ${e.message}");
      return false;
    }
  }

  /// Prompts the system dialog to ignore battery optimizations for the app.
  static Future<void> requestBatteryOptimization() async {
    try {
      await _channel.invokeMethod('requestBatteryOptimization');
    } on PlatformException catch (e) {
      debugPrint("Failed to request battery optimization: ${e.message}");
    }
  }

  /// Prompts the user with sequential dialogs to request both permissions if not already granted.
  static Future<void> checkAndPrompt(BuildContext context) async {
    // 1. Check Overlay Permission
    final hasOverlay = await checkPermission();
    bool shouldCheckBattery = true;
    
    if (!hasOverlay && context.mounted) {
      bool userAccepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E30),
            title: const Text(
              'Overlay Permission Required',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: const Text(
              'To allow BxBeam to start automatically on device boot, the "Display over other apps" (Overlay) permission is required.\n\nPlease enable it in the next screen.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Later', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB73A3C),
                ),
                onPressed: () async {
                  Navigator.of(dialogContext).pop(true);
                  await requestPermission();
                },
                child: const Text('Enable', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ) ?? false;
      
      shouldCheckBattery = userAccepted;
    }

    if (!shouldCheckBattery) return;

    // Wait a brief moment before checking/prompting for battery optimization
    await Future.delayed(const Duration(milliseconds: 1200));

    // 2. Check Battery Optimization
    if (context.mounted) {
      final isBatteryOptimizedIgnored = await checkBatteryOptimization();
      if (!isBatteryOptimizedIgnored && context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E30),
              title: const Text(
                'Disable Battery Optimization',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: const Text(
                'To ensure the Android OS does not block auto-start broadcasts when booting, battery optimizations must be disabled for BxBeam.\n\nPlease choose "Allow" in the next system prompt.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Later', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB73A3C),
                  ),
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await requestBatteryOptimization();
                  },
                  child: const Text('Allow', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      }
    }
  }
}
