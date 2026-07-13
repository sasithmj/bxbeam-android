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

  // 1. Initialize Local DB
  final isarService = IsarService();
  await isarService.db; // Wait for DB to be ready

  // 2. Initialize Playback Engine
  final playbackEngine = PlaybackEngine();

  // 3. Initialize BLoC
  final playbackBloc = PlaybackBloc(
    playbackEngine: playbackEngine,
    isarService: isarService,
  );
  playbackBloc.add(PlaybackStarted());

  // 4. Initialize API and SyncManager
  final apiService = ApiService();
  final syncManager = SyncManager(
    apiService: apiService,
    isarService: isarService,
    playbackBloc: playbackBloc,
  );
  
  // Wait for sync manager initialization to determine registration status
  bool isRegistered = await syncManager.initialize();

  // 5. Run App
  runApp(MyApp(
    playbackBloc: playbackBloc,
    isRegistered: isRegistered,
    apiService: apiService,
    syncManager: syncManager,
  ));
}

class MyApp extends StatelessWidget {
  final PlaybackBloc playbackBloc;
  final bool isRegistered;
  final ApiService apiService;
  final SyncManager syncManager;

  const MyApp({
    super.key,
    required this.playbackBloc,
    required this.isRegistered,
    required this.apiService,
    required this.syncManager,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: playbackBloc,
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
            : (isRegistered
                ? WebViewContainer(
                    apiService: apiService,
                    syncManager: syncManager,
                  )
                : RegistrationScreen(
                    apiService: apiService,
                    syncManager: syncManager,
                  )),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
