import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_start_flutter/auto_start_flutter.dart';
import '../data/services/api_service.dart';
import '../domain/sync_manager.dart';
import '../data/models/dto/device_dto.dart';
import '../data/models/dto/plant_code_dto.dart';
import '../core/overlay_permission_helper.dart';
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
  final _macController = TextEditingController();
  final _ipController = TextEditingController();

  List<PlantCodeDto> _plantCodes = [];
  String? _selectedPlantCode;
  bool _isLoading = true;
  bool _isRegistering = false;
  bool _isAlreadyRegistered = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _macController.addListener(_onMacAddressChanged);
    _loadInitialData();
    initAutoStart();
    
    // Check and request overlay permission after the screen renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      OverlayPermissionHelper.checkAndPrompt(context);
    });
  }

  Future<void> initAutoStart() async {
    try {
      // Check auto-start availability.
      var isAvailable = (await isAutoStartAvailable) ?? false;
      debugPrint("Auto start available: $isAvailable");
      // If available then navigate to auto-start setting page.
      if (isAvailable) {
         bool success = await getAutoStartPermission();
         debugPrint("Auto start permission open success: $success");
      }
    } catch (e) {
      debugPrint("Failed to initialize auto-start setting: $e");
    }
  }

  void _onMacAddressChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _checkIfRegistered(_macController.text);
    });
  }

  Future<void> _checkIfRegistered(String mac) async {
    if (mac.trim().isEmpty) return;
    try {
      final existingDevices = await widget.apiService.getRegisteredDevice(mac.trim());
      if (existingDevices.isNotEmpty) {
        final device = existingDevices.first;
        setState(() {
          _nameController.text = device.scrName;
          _locationController.text = device.scrLoc;
          _ipController.text = device.ipAddress;
          
          if (_plantCodes.any((element) => element.plantCode == device.plantCode)) {
            _selectedPlantCode = device.plantCode;
          } else {
            _plantCodes.add(PlantCodeDto(plantCode: device.plantCode, plantName: device.plantCode));
            _selectedPlantCode = device.plantCode;
          }
          _isAlreadyRegistered = true;
        });
      } else {
        if (_isAlreadyRegistered) {
          final ip = await _getLocalIpAddress();
          setState(() {
            _nameController.clear();
            _locationController.clear();
            _ipController.text = ip;
            if (_plantCodes.isNotEmpty) {
              _selectedPlantCode = _plantCodes.first.plantCode;
            }
            _isAlreadyRegistered = false;
          });
        }
      }
    } catch (e) {
      print('Check registration failed: $e');
    }
  }

  Future<String> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback && address.address.isNotEmpty) {
            return address.address;
          }
        }
      }
    } catch (e) {
      print('Failed to get local IP: $e');
    }
    return '0.0.0.0';
  }

  Future<void> _loadInitialData() async {
    try {
      // Load Device Identifier using persistent generator
      final mac = await SyncManager.getDeviceMac();

      // Load Local IP
      final ip = await _getLocalIpAddress();

      // Load Plant Codes
      final codes = await widget.apiService.getPlantCode();

      setState(() {
        _macController.text = mac;
        _ipController.text = ip;
        _plantCodes = codes;
        if (codes.isNotEmpty) {
          _selectedPlantCode = codes.first.plantCode;
        }
      });
      await _checkIfRegistered(mac);
      setState(() {
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

    final mac = _macController.text.trim();
    final ip = _ipController.text.trim();

    try {
      // Save the (potentially edited) device ID permanently to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_mac_address', mac);

      // 1. Check if the device is already registered under this MAC
      final existingDevices = await widget.apiService.getRegisteredDevice(mac);

      String screenId = '';
      if (existingDevices.isNotEmpty) {
        screenId = existingDevices.first.scrId;
        print(
          "Device already registered on server. Logging in directly with Screen ID: $screenId",
        );
      } else {
        final newDevice = DeviceDto(
          scrId: '',
          scrName: _nameController.text.trim(),
          scrLoc: _locationController.text.trim(),
          ipAddress: ip.isEmpty ? '0.0.0.0' : ip,
          macAddress: mac,
          createdDate: DateTime.now(),
          scrStatus: 'SC1',
          onStatus: 'Offline',
          plantCode: _selectedPlantCode ?? 'KT01',
        );

        final result = await widget.apiService.registerDevice(newDevice);

        if (result.toLowerCase() == 'ok') {
          // Query the registered device list by MAC to get the newly generated screen ID
          final devices = await widget.apiService.getRegisteredDevice(mac);
          if (devices.isNotEmpty) {
            screenId = devices.first.scrId;
          } else {
            throw Exception(
              'Device registered successfully, but could not retrieve Screen ID from server.',
            );
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
                        TextFormField(
                          controller: _macController,
                          enabled: true,
                          decoration: const InputDecoration(
                            labelText: 'Device Identifier',
                            border: OutlineInputBorder(),
                            helperText: 'Enter custom ID or use the generated BX ID',
                            helperStyle: TextStyle(color: Colors.green),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _ipController,
                          enabled: !_isAlreadyRegistered,
                          decoration: const InputDecoration(
                            labelText: 'IP Address',
                            border: OutlineInputBorder(),
                            helperText:
                                'Auto-detected local IP. Edit if incorrect.',
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty)
                              return 'Required';
                            final parts = value.split('.');
                            if (parts.length != 4)
                              return 'Enter a valid IPv4 address';
                            for (final part in parts) {
                              final num = int.tryParse(part);
                              if (num == null || num < 0 || num > 255) {
                                return 'Enter a valid IPv4 address';
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameController,
                          enabled: !_isAlreadyRegistered,
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
                          enabled: !_isAlreadyRegistered,
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
                          onChanged: _isAlreadyRegistered
                              ? null
                              : (value) {
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
                              : Text(
                                  _isAlreadyRegistered ? 'Login & Start' : 'Register & Start',
                                  style: const TextStyle(fontSize: 16),
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
    _macController.removeListener(_onMacAddressChanged);
    _debounceTimer?.cancel();
    _nameController.dispose();
    _locationController.dispose();
    _macController.dispose();
    _ipController.dispose();
    super.dispose();
  }
}
