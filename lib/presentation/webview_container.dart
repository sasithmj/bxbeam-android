import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bloc/playback_bloc.dart';
import 'bloc/playback_state.dart';
import '../data/services/api_service.dart';
import '../domain/sync_manager.dart';
import 'registration_screen.dart';
import 'running_schedule_screen.dart';
import 'license_expired_screen.dart';
import '../core/config.dart';
import '../core/overlay_permission_helper.dart';

class WebViewContainer extends StatefulWidget {
  final ApiService? apiService;
  final SyncManager? syncManager;

  const WebViewContainer({
    super.key,
    this.apiService,
    this.syncManager,
  });

  @override
  State<WebViewContainer> createState() => _WebViewContainerState();
}

class _WebViewContainerState extends State<WebViewContainer> {
  InAppWebViewController? webViewController;
  String? currentUrl;
  bool _showMenuButton = false;
  Timer? _menuHideTimer;

  @override
  void initState() {
    super.initState();
    // Check and request overlay permission after the screen renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OverlayPermissionHelper.checkAndPrompt(context);
    });
  }

  void _toggleMenuButton() {
    setState(() {
      _showMenuButton = !_showMenuButton;
    });
    _startMenuHideTimer();
  }

  void _startMenuHideTimer() {
    _menuHideTimer?.cancel();
    if (_showMenuButton) {
      _menuHideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _showMenuButton = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _menuHideTimer?.cancel();
    webViewController = null;
    super.dispose();
  }

  String _processUrl(String url) {
    Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;

    // 1. YouTube embedding logic
    if (uri.host.contains('youtube.com') || uri.host == 'youtu.be') {
      String videoId = '';
      if (uri.path.contains('/embed/')) {
        videoId = uri.pathSegments.last;
      } else if (uri.queryParameters.containsKey('v')) {
        videoId = uri.queryParameters['v']!;
      } else if (uri.host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
        videoId = uri.pathSegments.first;
      }
      
      if (videoId.isNotEmpty) {
        url = "https://www.youtube.com/embed/$videoId?autoplay=1&playsinline=1&rel=0";
        uri = Uri.parse(url);
      }
    }

    // 2. Append license expiry query parameter if configured
    final expiry = AppConfig.licenseExpiryDate;
    if (expiry != null && expiry.isNotEmpty) {
      final queryParams = Map<String, String>.from(uri.queryParameters);
      queryParams['lic_exp'] = expiry;
      uri = uri.replace(queryParameters: queryParams);
    }

    return uri.toString();
  }

  void _showResetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E30),
          title: const Text(
            'Device Settings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Do you want to reset this device registration? This will clear the cached screen settings and return to the registration screen.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCF6679),
              ),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                
                // 1. Cancel the SyncManager timer/refresh loop
                widget.syncManager?.dispose();

                // 2. Clear SharedPreferences
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('screen_id');

                // 3. Navigate back to RegistrationScreen
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => RegistrationScreen(
                        apiService: widget.apiService ?? ApiService(),
                        syncManager: widget.syncManager ?? widget.syncManager!,
                      ),
                    ),
                  );
                }
              },
              child: const Text('Reset', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E30),
          title: const Text(
            'Confirm Logout',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Are you sure you want to logout? This will clear the cached screen settings and local schedule database, returning the app to default state.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCF6679),
              ),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                
                // 1. Cancel the SyncManager timer/refresh loop
                widget.syncManager?.dispose();

                // 2. Clear stored screen ID from SharedPreferences (keep device ID)
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('screen_id');

                // 3. Clear all schedules from local database
                if (widget.syncManager != null) {
                  await widget.syncManager!.isarService.clearAllSchedules();
                }

                // 4. Navigate back to RegistrationScreen
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => RegistrationScreen(
                        apiService: widget.apiService ?? ApiService(),
                        syncManager: widget.syncManager ?? widget.syncManager!,
                      ),
                    ),
                  );
                }
              },
              child: const Text('Logout', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Kiosks usually have black backgrounds to hide loading flashes
      // BlocConsumer lets us both react to state changes (listener) and build UI (builder)
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          final size = MediaQuery.of(context).size;
          // Ignore taps in the top-right corner area (100x100 pixels) to avoid conflicts with menu button
          if (event.localPosition.dx > size.width - 100 && event.localPosition.dy < 100) {
            return;
          }
          _toggleMenuButton();
        },
        child: Stack(
          children: [
            BlocConsumer<PlaybackBloc, PlaybackState>(
              listener: (context, state) {
                if (state is PlaybackPlaying) {
                  // Only tell the WebView to load if the URL has actually changed
                  if (currentUrl != state.url) {
                    currentUrl = state.url;
                    String processedUrl = _processUrl(state.url);
                    webViewController?.loadUrl(
                      urlRequest: URLRequest(url: WebUri(processedUrl)),
                    );
                  }
                }
              },
              builder: (context, state) {
                // 1. Loading State
                if (state is PlaybackInitial || state is PlaybackLoading) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
  
                // 2. Error State (e.g. Isar failed)
                if (state is PlaybackError) {
                  return Center(
                    child: Text(
                      state.message,
                      style: const TextStyle(color: Colors.red, fontSize: 24),
                    ),
                  );
                }

                // 3. Deactivated State
                if (state is PlaybackDeactivated) {
                  return const Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_clock, size: 64, color: Colors.amber),
                            SizedBox(height: 16),
                            Text(
                              'Device deactivated. Contact admin to activate this screen.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // 3.5. License Expired State
                if (state is PlaybackLicenseExpired) {
                  return const LicenseExpiredScreen();
                }

                // 4. Main WebView 
                // We render the WebView once and use the listener above to drive URL changes.
                return InAppWebView(
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false, // Important for auto-playing videos in kiosk
                    allowsInlineMediaPlayback: true, // Required for proper inline playback without fullscreen
                    clearCache: true, // Prevents stale content issues, disable if you want heavy caching
                    transparentBackground: true,
                  ),
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                    // If we are already playing something when the view is created, load it immediately
                    if (state is PlaybackPlaying) {
                      currentUrl = state.url;
                      String processedUrl = _processUrl(state.url);
                      webViewController?.loadUrl(
                        urlRequest: URLRequest(url: WebUri(processedUrl)),
                      );
                    }
                  },
                  onLoadStop: (controller, url) async {
                    // Inject custom CSS or JS here if needed to hide scrollbars or UI elements
                  },
                  onReceivedError: (controller, request, error) {
                    // Triggered on network errors or invalid URLs. 
                    // In an industrial setting, you could inject a fallback local HTML page here.
                  },
                );
              },
            ),
            // Hidden Admin Settings Hotspot in top right corner (80x80 pixels)
            Positioned(
              top: 0,
              right: 0,
              width: 80,
              height: 80,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onLongPress: () => _showResetDialog(context),
              ),
            ),
            // Floating Hamburger Menu Button
            if (_showMenuButton)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                    tooltip: 'Menu',
                    onSelected: (value) {
                      if (value == 'schedule') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => RunningScheduleScreen(
                              isarService: widget.syncManager!.isarService,
                            ),
                          ),
                        );
                      } else if (value == 'logout') {
                        _showLogoutDialog(context);
                      }
                    },
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'schedule',
                        child: Row(
                          children: [
                            Icon(Icons.list_alt, color: Colors.black87),
                            SizedBox(width: 8),
                            Text('View Running Schedule'),
                          ],
                        ),
                      ),
                      const PopupMenuItem<String>(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text('Logout', style: TextStyle(color: Colors.redAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
