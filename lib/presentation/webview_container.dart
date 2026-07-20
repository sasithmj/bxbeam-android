import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    // Check and request overlay permission after the screen renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OverlayPermissionHelper.checkAndPrompt(context);
    });

    // Listen to network connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isNowOffline = results.contains(ConnectivityResult.none);
      if (isNowOffline != _isOffline) {
        setState(() {
          _isOffline = isNowOffline;
        });
        
        if (isNowOffline) {
          debugPrint("Network connection dropped. Pausing sync loop...");
          widget.syncManager?.dispose(); // Cancels the active refresh timer
        } else {
          debugPrint("Network connection restored. Restarting schedules...");
          SharedPreferences.getInstance().then((prefs) {
            final screenId = prefs.getString('screen_id');
            if (screenId != null && screenId.isNotEmpty) {
              widget.syncManager?.setScreenIdAndStart(screenId);
            }
          });
        }
      }
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
    _connectivitySubscription?.cancel();
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
                  return const Scaffold(
                    backgroundColor: Color(0xFF0F0F1A),
                    body: Center(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 72,
                                color: Color(0xFFCF6679),
                              ),
                              SizedBox(height: 24),
                              Text(
                                'Screen Inactive',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'This display has been deactivated. Please contact your system administrator to authorize and activate this device.',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 32),
                              // Translucent Red Status Indicator Pill
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0x1ACF6679),
                                  borderRadius: BorderRadius.all(Radius.circular(20)),
                                  border: Border.fromBorderSide(
                                    BorderSide(color: Color(0x33CF6679), width: 1),
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Color(0xFFCF6679),
                                          shape: BoxShape.circle,
                                        ),
                                        child: SizedBox(width: 8, height: 8),
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'DEACTIVATED',
                                        style: TextStyle(
                                          color: Color(0xFFCF6679),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
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
            
            // Connection Dropped / Offline Overlay Screen
            if (_isOffline)
              Positioned.fill(
                child: Scaffold(
                  backgroundColor: const Color(0xFF0F0F1A),
                  body: Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.wifi_off_rounded,
                              size: 80,
                              color: Color(0xFFFFB300), // Amber
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Connection Dropped',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Please check your network settings. Normal display operation and schedules will automatically resume once the connection is restored.',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 36),
                            // Translucent Reconnecting Indicator Pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: const BoxDecoration(
                                color: Color(0x1AFFB300),
                                borderRadius: BorderRadius.all(Radius.circular(20)),
                                border: Border.fromBorderSide(
                                  BorderSide(color: Color(0x33FFB300), width: 1),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.0,
                                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFB300)),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'RECONNECTING...',
                                    style: TextStyle(
                                      color: Color(0xFFFFB300),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
