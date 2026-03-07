import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ahbu/models/device_record.dart';
import 'package:ahbu/models/site_record.dart';
import 'package:ahbu/models/user_role.dart';
import 'package:ahbu/models/user_session.dart';
import 'package:ahbu/services/api_exception.dart';

class AuthApi {
  AuthApi({required this.baseUrl});

  final String baseUrl;

  Future<UserSession> login({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    return _authRequest(
      path: '/auth/login',
      body: {'email': email, 'password': password, 'role': role.apiValue},
      expectedCode: 200,
    );
  }

  Future<String> registerSiteManager({
    required String fullName,
    required String email,
    required String password,
    required String phoneNumber,
  }) async {
    final payload = await _postJson(
      path: '/auth/site-manager/register',
      body: {
        'full_name': fullName,
        'email': email,
        'password': password,
        'phone_number': phoneNumber,
      },
      expectedCode: 200,
    );

    return payload['email'] as String? ?? email;
  }

  Future<void> verifySiteManagerEmail({
    required String email,
    required String code,
  }) async {
    await _postJson(
      path: '/auth/site-manager/verify-email',
      body: {'email': email, 'code': code},
      expectedCode: 200,
    );
  }

  Future<void> resendSiteManagerCode({
    required String email,
  }) async {
    await _postJson(
      path: '/auth/site-manager/resend-code',
      body: {'email': email},
      expectedCode: 200,
    );
  }

  Future<List<SiteRecord>> listManagerSites({
    required String token,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return (payload['sites'] as List<dynamic>? ?? <dynamic>[])
        .map((item) => SiteRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<DeviceRecord> lookupAssignableDevice({
    required String token,
    required String deviceUid,
  }) async {
    final encodedUid = Uri.encodeQueryComponent(deviceUid.trim().toUpperCase());
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/devices/lookup?device_uid=$encodedUid',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return DeviceRecord.fromJson(payload['device'] as Map<String, dynamic>);
  }

  Future<DeviceRecord> assignDeviceToSiteGate({
    required String token,
    required int deviceId,
    required int siteCode,
    required String gateName,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/manager/devices/$deviceId/assignment',
      token: token,
      body: {
        'site_code': siteCode,
        'gate_name': gateName,
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return DeviceRecord.fromJson(payload['device'] as Map<String, dynamic>);
  }

  Future<UserSession> _authRequest({
    required String path,
    required Map<String, dynamic> body,
    required int expectedCode,
  }) async {
    final payload = await _postJson(
      path: path,
      body: body,
      expectedCode: expectedCode,
    );

    final user = payload['user'] as Map<String, dynamic>;
    return UserSession(
      id: user['id'] as int,
      fullName: user['full_name'] as String,
      email: user['email'] as String,
      role: UserRole.fromApi(user['role'] as String),
      token: payload['token'] as String,
      phoneNumber: user['phone_number'] as String?,
      createdAt: user['created_at'] == null
          ? null
          : DateTime.tryParse(user['created_at'] as String),
    );
  }

  Future<Map<String, dynamic>> _postJson({
    required String path,
    required Map<String, dynamic> body,
    required int expectedCode,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    final payload = _decodePayload(response);
    if (response.statusCode != expectedCode) {
      throw ApiException(
        (payload['error'] as String?) ??
            'Islem basarisiz (${response.statusCode})',
      );
    }

    return payload;
  }

  Future<http.Response> _authorizedRequest({
    required String method,
    required String path,
    required String token,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'PATCH':
        return http.patch(uri, headers: headers, body: jsonEncode(body ?? {}));
      default:
        throw ArgumentError('Desteklenmeyen method: $method');
    }
  }

  void _ensureStatus(http.Response response, int expectedCode) {
    if (response.statusCode == expectedCode) {
      return;
    }

    final payload = _decodePayload(response);
    throw ApiException(
      (payload['error'] as String?) ??
          'Islem basarisiz (${response.statusCode})',
    );
  }

  Map<String, dynamic> _decodePayload(http.Response response) {
    if (response.body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    final raw = jsonDecode(response.body);
    return raw is Map<String, dynamic> ? raw : <String, dynamic>{};
  }
}
