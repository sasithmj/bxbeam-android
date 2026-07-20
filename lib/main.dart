import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:auto_start_flutter/auto_start_flutter.dart';
import 'data/services/isar_service.dart';
import 'domain/playback_engine.dart';
import 'data/services/api_service.dart';
import 'domain/sync_manager.dart';
import 'presentation/bloc/playback_bloc.dart';
import 'presentation/bloc/playback_event.dart';
import 'presentation/webview_container.dart';
import 'presentation/registration_screen.dart';
import 'presentation/loading_screen.dart';
import 'core/config.dart';
import 'presentation/license_expired_screen.dart';

@pragma('vm:entry-point')
void myBootCallback() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("Boot Callback execution triggered! The device just booted.");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Register auto-start boot callback
  try {
    bool success = await registerBootCallback(myBootCallback);
    debugPrint("Boot callback registration status: $success");
  } catch (e) {
    debugPrint("Failed to register boot callback: $e");
  }
  
  // Set preferred orientation to landscape
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isInitialized = false;
  bool _isRegistered = false;
  late ApiService _apiService;
  late SyncManager _syncManager;
  late PlaybackBloc _playbackBloc;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final startTime = DateTime.now();

    try {
      // 1. Initialize Local DB
      final isarService = IsarService();
      await isarService.db; // Wait for DB to be ready

      // 2. Initialize Playback Engine
      final playbackEngine = PlaybackEngine();

      // 3. Initialize BLoC
      _playbackBloc = PlaybackBloc(
        playbackEngine: playbackEngine,
        isarService: isarService,
      );
      _playbackBloc.add(PlaybackStarted());

      // 4. Initialize API and SyncManager
      _apiService = ApiService();
      _syncManager = SyncManager(
        apiService: _apiService,
        isarService: isarService,
        playbackBloc: _playbackBloc,
      );
      
      // Wait for sync manager initialization to determine registration status
      _isRegistered = await _syncManager.initialize();
    } catch (e) {
      debugPrint("Initialization error: $e");
    }

    // Ensure the premium splash screen is shown for at least 2.5 seconds for smooth animations
    final elapsed = DateTime.now().difference(startTime);
    final remaining = const Duration(milliseconds: 2500) - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return MaterialApp(
        title: 'BxBeam',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 183, 58, 60)),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFF0F0F1A),
        ),
        home: const LoadingScreen(),
        debugShowCheckedModeBanner: false,
      );
    }

    return BlocProvider.value(
      value: _playbackBloc,
      child: MaterialApp(
        title: 'BxBeam',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 183, 58, 60)),
          useMaterial3: true,
        ),
        // If license is expired, block everything and show the LicenseExpiredScreen.
        // Else, if registered show WebViewContainer, otherwise show RegistrationScreen.
        home: AppConfig.isLicenseExpired()
            ? const LicenseExpiredScreen()
            : (_isRegistered
                ? WebViewContainer(
                    apiService: _apiService,
                    syncManager: _syncManager,
                  )
                : RegistrationScreen(
                    apiService: _apiService,
                    syncManager: _syncManager,
                  )),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
