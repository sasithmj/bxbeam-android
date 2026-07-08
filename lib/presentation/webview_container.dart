import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bloc/playback_bloc.dart';
import 'bloc/playback_state.dart';
import '../data/services/api_service.dart';
import '../domain/sync_manager.dart';
import 'registration_screen.dart';

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

  String _processUrl(String url) {
    Uri? uri = Uri.tryParse(url);
    if (uri != null && (uri.host.contains('youtube.com') || uri.host == 'youtu.be')) {
      String videoId = '';
      if (uri.path.contains('/embed/')) {
        videoId = uri.pathSegments.last;
      } else if (uri.queryParameters.containsKey('v')) {
        videoId = uri.queryParameters['v']!;
      } else if (uri.host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
        videoId = uri.pathSegments.first;
      }
      
      if (videoId.isNotEmpty) {
        return "https://www.youtube.com/embed/$videoId?autoplay=1&playsinline=1&rel=0";
      }
    }
    return url;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Kiosks usually have black backgrounds to hide loading flashes
      // BlocConsumer lets us both react to state changes (listener) and build UI (builder)
      body: Stack(
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

              // 3. Main WebView 
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
        ],
      ),
    );
  }
}
