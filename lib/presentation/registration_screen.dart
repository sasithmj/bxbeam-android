import 'package:flutter/material.dart';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import '../data/services/api_service.dart';
import '../domain/sync_manager.dart';
import '../data/models/dto/device_dto.dart';
import '../data/models/dto/plant_code_dto.dart';
import 'webview_container.dart';

class RegistrationScreen extends StatefulWidget {
  final ApiService apiService;
  final SyncManager syncManager;

  const RegistrationScreen({
    super.key,
    required this.apiService,
    required this.syncManager,
  });

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();

  String _macAddress = 'Loading...';
  List<PlantCodeDto> _plantCodes = [];
  String? _selectedPlantCode;
  bool _isLoading = true;
  bool _isRegistering = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      // Load Device Identifier
      String mac = 'UNKNOWN_DEVICE_ID';
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          mac = androidInfo.id;
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          mac = iosInfo.identifierForVendor ?? 'UNKNOWN_IOS';
        }
      } catch (e) {
        print('Failed to get device identifier: $e');
      }

      // Load Plant Codes
      final codes = await widget.apiService.getPlantCode();

      setState(() {
        _macAddress = mac;
        _plantCodes = codes;
        if (codes.isNotEmpty) {
          _selectedPlantCode = codes.first.plantCode;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _registerDevice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isRegistering = true;
    });

    try {
      // 1. Check if the device is already registered under this MAC
      final existingDevices = await widget.apiService.getRegisteredDevice(_macAddress);

      String screenId = '';
      if (existingDevices.isNotEmpty) {
        screenId = existingDevices.first.scrId;
        print("Device already registered on server. Logging in directly with Screen ID: $screenId");
      } else {
        final newDevice = DeviceDto(
          scrId: '',
          scrName: _nameController.text.trim(),
          scrLoc: _locationController.text.trim(),
          ipAddress: '0.0.0.0',
          macAddress: _macAddress,
          createdDate: DateTime.now(),
          scrStatus: 'SC1',
          onStatus: 'Offline',
          plantCode: _selectedPlantCode ?? 'KT01',
        );

        final result = await widget.apiService.registerDevice(newDevice);

        if (result.toLowerCase() == 'ok') {
          // Query the registered device list by MAC to get the newly generated screen ID
          final devices = await widget.apiService.getRegisteredDevice(_macAddress);
          if (devices.isNotEmpty) {
            screenId = devices.first.scrId;
          } else {
            throw Exception('Device registered successfully, but could not retrieve Screen ID from server.');
          }
        } else if (result.startsWith('SR')) {
          screenId = result;
        } else {
          throw Exception('Invalid registration response: $result');
        }
      }

      // Start the sync loop with the screen ID
      await widget.syncManager.setScreenIdAndStart(screenId);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => WebViewContainer(
              apiService: widget.apiService,
              syncManager: widget.syncManager,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Registration failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRegistering = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Register Device')),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Device Setup',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'MAC Address / ID: $_macAddress',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Screen Name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _locationController,
                          decoration: const InputDecoration(
                            labelText: 'Screen Location',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          decoration: const InputDecoration(
                            labelText: 'Plant Code',
                            border: OutlineInputBorder(),
                          ),
                          value: _selectedPlantCode,
                          items: _plantCodes.map((plant) {
                            return DropdownMenuItem(
                              value: plant.plantCode,
                              child: Text(plant.plantName),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedPlantCode = value;
                            });
                          },
                          validator: (value) =>
                              value == null ? 'Required' : null,
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: _isRegistering ? null : _registerDevice,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isRegistering
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Register & Start',
                                  style: TextStyle(fontSize: 16),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }
}
