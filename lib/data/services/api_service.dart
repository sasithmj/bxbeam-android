import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/dto/device_dto.dart';
import '../models/dto/plant_code_dto.dart';
import '../models/dto/schedule_dto.dart';

class ApiService {
  static const String _baseUrl =
      'http://bdxdisplayapp.somee.com/api/app_data.asmx';
  // static const String _baseUrl =
  //     'http://10.76.152.20/display/api/app_data.asmx';
  static const String _apiKey = 'yFlMjSup.IbHOCjyRiTb8QOO9Ltsbr';
  static const String _skey =
      '9c4572c4e6ce5ac08292f1b8affad147794d8a9ad55b2b3f08ae2fa15868ec5f';
  static const String _namespace = 'http://www.ddacode.lk/';

  Future<String> _sendSoapRequest(String operation, String bodyContent) async {
    final envelope =
        '''<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/">
  <soap:Body>
    <$operation xmlns="$_namespace">
      <skey>$_skey</skey>
$bodyContent
    </$operation>
  </soap:Body>
</soap:Envelope>''';

    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'text/xml; charset=utf-8',
        'api-key': _apiKey,
        'SOAPAction': '$_namespace$operation',
      },
      body: envelope,
    );

    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception(
        'SOAP Request Failed: ${response.statusCode}\n${response.body}',
      );
    }
  }

  String _extractResult(String xmlString, String resultTag) {
    try {
      final document = XmlDocument.parse(xmlString);
      final elements = document.findAllElements(resultTag);
      if (elements.isNotEmpty) {
        return elements.first.innerText;
      }
    } catch (e) {
      print('XML Parse Error: $e');
    }
    return '';
  }

  /// 1. Register Device
  Future<String> registerDevice(DeviceDto device) async {
    final body =
        '''
      <Screen_name>${device.scrName}</Screen_name>
      <Screen_location>${device.scrLoc}</Screen_location>
      <IP>${device.ipAddress}</IP>
      <MAC>${device.macAddress}</MAC>
      <Screen_sts>${device.scrStatus}</Screen_sts>
      <plant_code>${device.plantCode}</plant_code>
    ''';
    final responseXml = await _sendSoapRequest('Reg_app', body);
    final result = _extractResult(responseXml, 'Reg_appResult');
    if (result.toLowerCase() != 'ok' && !result.startsWith('SR')) {
      throw Exception('Registration failed: $result');
    }
    return result;
  }

  /// 2. Get Plant Code
  Future<List<PlantCodeDto>> getPlantCode() async {
    final responseXml = await _sendSoapRequest('get_plant_code', '');
    final resultText = _extractResult(responseXml, 'get_plant_codeResult');
    if (resultText.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(resultText);
        return jsonList.map((e) => PlantCodeDto.fromJson(e)).toList();
      } catch (e) {
        print('Error parsing plant code JSON: $e');
      }
    }
    return [];
  }

  /// 3. Get Registered Device
  Future<List<DeviceDto>> getRegisteredDevice(String mac) async {
    final body = '<mac>$mac</mac>';
    final responseXml = await _sendSoapRequest('get_registerd_device', body);
    final resultText = _extractResult(
      responseXml,
      'get_registerd_deviceResult',
    );
    if (resultText.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(resultText);
        return jsonList.map((e) => DeviceDto.fromJson(e)).toList();
      } catch (e) {
        print('Error parsing registered device JSON: $e');
      }
    }
    return [];
  }

  /// 4. Get Schedules
  Future<List<ScheduleDto>> getSchedules(String screenId) async {
    final body = '<screenID>$screenId</screenID>';
    final responseXml = await _sendSoapRequest('get_URL', body);

    final resultText = _extractResult(responseXml, 'get_URLResult');

    if (resultText.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(resultText);
        return jsonList.map((e) => ScheduleDto.fromJson(e)).toList();
      } catch (e) {
        throw FormatException('Failed to parse schedules JSON: $resultText');
      }
    }
    return [];
  }

  /// 5. Get Next Refresh Time (in seconds)
  Future<int> getNextRefresh(String screenId) async {
    final body = '<screnid>$screenId</screnid>';
    final responseXml = await _sendSoapRequest('get_next_refresh', body);
    final resultText = _extractResult(responseXml, 'get_next_refreshResult');
    if (resultText.isNotEmpty) {
      try {
        final List<dynamic> jsonList = jsonDecode(resultText);
        if (jsonList.isNotEmpty) {
          final Map<String, dynamic> data = jsonList.first;
          final numSeconds = data['NxtRefreshMn'];
          if (numSeconds is num) {
            return numSeconds.toInt();
          }
        }
      } catch (e) {
        print('Error parsing next refresh time: $e');
      }
    }
    return 60; // Fallback to 60s if parsing fails
  }
}
