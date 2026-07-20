import 'package:flutter/material.dart';
import '../domain/sync_manager.dart';

class LicenseExpiredScreen extends StatelessWidget {
  const LicenseExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Sleek dark theme background
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Premium lock container
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.lock_clock_outlined,
                  size: 80,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 32),

              // Expired title
              const Text(
                'APPLICATION LICENSE EXPIRED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Expiry description
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: const Text(
                  'The license for this device has expired or is invalid. Please contact the system administrator or support team to renew this screen\'s license.',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 48),

              // Device ID container
              // FutureBuilder<String>(
              //   future: SyncManager.getDeviceMac(),
              //   builder: (context, snapshot) {
              //     final deviceId = snapshot.data ?? 'BX-Loading...';
              //     return Container(
              //       padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              //       decoration: BoxDecoration(
              //         color: Colors.white.withOpacity(0.05),
              //         borderRadius: BorderRadius.circular(8),
              //         border: Border.all(color: Colors.white.withOpacity(0.1)),
              //       ),
              //       child: Column(
              //         children: [
              //           const Text(
              //             'UNIQUE DEVICE IDENTIFIER',
              //             style: TextStyle(
              //               color: Colors.grey,
              //               fontSize: 11,
              //               fontWeight: FontWeight.w600,
              //               letterSpacing: 1.2,
              //             ),
              //           ),
              //           const SizedBox(height: 6),
              //           SelectableText(
              //             deviceId,
              //             style: const TextStyle(
              //               color: Colors.amberAccent,
              //               fontSize: 18,
              //               fontWeight: FontWeight.bold,
              //               fontFamily: 'monospace',
              //             ),
              //           ),
              //         ],
              //       ),
              //     );
              //   },
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
