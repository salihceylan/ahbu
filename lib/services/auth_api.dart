import 'dart:async';
import 'dart:convert';

import 'package:ahbu/models/apartment_record.dart';
import 'package:ahbu/models/device_record.dart';
import 'package:ahbu/models/door_record.dart';
import 'package:ahbu/models/site_record.dart';
import 'package:ahbu/models/site_structure_record.dart';
import 'package:ahbu/models/user_role.dart';
import 'package:ahbu/models/user_session.dart';
import 'package:ahbu/services/api_exception.dart';
import 'package:http/http.dart' as http;

class AuthApi {
  AuthApi({required this.baseUrl});

  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Duration _retryDelay = Duration(milliseconds: 350);

  final String baseUrl;

  Future<UserSession> login({
    required String identifier,
    required String password,
    required UserRole role,
  }) async {
    return _authRequest(
      path: '/auth/login',
      body: {
        'identifier': identifier,
        'password': password,
        'role': role.apiValue,
      },
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

  Future<void> resendSiteManagerCode({required String email}) async {
    await _postJson(
      path: '/auth/site-manager/resend-code',
      body: {'email': email},
      expectedCode: 200,
    );
  }

  Future<List<SiteRecord>> listManagerSites({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites?page=1&page_size=100',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site listesi',
      () => (payload['sites'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => SiteRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<SiteRecord> createManagerSite({
    required String token,
    required String name,
    String? address,
    String? city,
    String? district,
    required List<int> blockApartmentCounts,
    required int doorCount,
  }) async {
    final totalApartments = blockApartmentCounts.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/sites',
      token: token,
      body: {
        'name': name,
        'address': address,
        'city': city,
        'district': district,
        'block_count': blockApartmentCounts.length,
        'apartment_count': totalApartments,
        'block_apartment_counts': blockApartmentCounts,
        'door_count': doorCount,
      },
    );

    _ensureStatus(response, 201);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site kaydi',
      () => SiteRecord.fromJson(payload['site'] as Map<String, dynamic>),
    );
  }

  Future<SiteRecord> updateManagerSite({
    required String token,
    required int siteCode,
    String? name,
    String? address,
    String? city,
    String? district,
    List<int>? blockApartmentCounts,
    int? doorCount,
  }) async {
    final totalApartments = blockApartmentCounts?.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    final body = <String, dynamic>{
      'name': name,
      'address': address,
      'city': city,
      'district': district,
      'block_count': blockApartmentCounts?.length,
      'apartment_count': totalApartments,
      'block_apartment_counts': blockApartmentCounts,
      'door_count': doorCount,
    }..removeWhere((_, value) => value == null);

    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/manager/sites/$siteCode',
      token: token,
      body: body,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Site kaydi',
      () => SiteRecord.fromJson(payload['site'] as Map<String, dynamic>),
    );
  }

  Future<SiteStructureRecord> getManagerSiteStructure({
    required String token,
    required int siteCode,
  }) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/sites/$siteCode/structure',
      token: token,
    );

    _ensureStatus(response, 200);
    return _parsePayload(
      'Site yapisi',
      () => SiteStructureRecord.fromJson(_decodePayload(response)),
    );
  }

  Future<ApartmentRecord> upsertManagerApartmentResident({
    required String token,
    required int apartmentId,
    required String fullName,
    required String loginName,
    required String password,
    String? email,
    String? phoneNumber,
    required bool isActive,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/manager/apartments/$apartmentId/resident',
      token: token,
      body: {
        'full_name': fullName,
        'login_name': loginName,
        'password': password,
        'email': email,
        'phone_number': phoneNumber,
        'is_active': isActive,
      },
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Daire kullanicisi',
      () => ApartmentRecord.fromJson(
        payload['apartment'] as Map<String, dynamic>,
      ),
    );
  }

  Future<void> sendManagerApartmentCredentials({
    required String token,
    required int apartmentId,
  }) async {
    final response = await _authorizedRequest(
      method: 'POST',
      path: '/manager/apartments/$apartmentId/send-credentials',
      token: token,
    );

    _ensureStatus(response, 200);
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
    return _parsePayload(
      'Cihaz kaydi',
      () => DeviceRecord.fromJson(payload['device'] as Map<String, dynamic>),
    );
  }

  Future<List<DeviceRecord>> listManagerDevices({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/manager/devices',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Cihaz listesi',
      () => (payload['devices'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => DeviceRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<DoorRecord> assignManagerDoorDevice({
    required String token,
    required int doorId,
    required String deviceUid,
  }) async {
    final response = await _authorizedRequest(
      method: 'PATCH',
      path: '/manager/doors/$doorId/device',
      token: token,
      body: {'device_uid': deviceUid.trim().toUpperCase()},
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapi kaydi',
      () => DoorRecord.fromJson(payload['door'] as Map<String, dynamic>),
    );
  }

  Future<void> deleteManagerDevice({
    required String token,
    required int deviceId,
  }) async {
    final response = await _authorizedRequest(
      method: 'DELETE',
      path: '/manager/devices/$deviceId',
      token: token,
    );

    _ensureStatus(response, 204, allowEmptyBody: true);
  }

  Future<List<DoorRecord>> listMyDoors({required String token}) async {
    final response = await _authorizedRequest(
      method: 'GET',
      path: '/app/my-doors',
      token: token,
    );

    _ensureStatus(response, 200);
    final payload = _decodePayload(response);
    return _parsePayload(
      'Kapi listesi',
      () => (payload['doors'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => DoorRecord.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
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

    return _parsePayload('Oturum bilgisi', () {
      final user = payload['user'] as Map<String, dynamic>;
      return UserSession(
        id: user['id'] as int,
        fullName: user['full_name'] as String,
        email: user['email'] as String,
        loginName: user['login_name'] as String?,
        role: UserRole.fromApi(user['role'] as String),
        isActive: user['is_active'] as bool? ?? true,
        token: payload['token'] as String,
        phoneNumber: user['phone_number'] as String?,
        createdAt: user['created_at'] == null
            ? null
            : DateTime.tryParse(user['created_at'] as String),
      );
    });
  }

  Future<Map<String, dynamic>> _postJson({
    required String path,
    required Map<String, dynamic> body,
    required int expectedCode,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final response = await _sendRequest(
      method: 'POST',
      uri: uri,
      headers: const {'Content-Type': 'application/json'},
      body: body,
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
        return _sendRequest(method: 'GET', uri: uri, headers: headers);
      case 'POST':
        return _sendRequest(
          method: 'POST',
          uri: uri,
          headers: headers,
          body: body,
        );
      case 'PATCH':
        return _sendRequest(
          method: 'PATCH',
          uri: uri,
          headers: headers,
          body: body,
        );
      case 'DELETE':
        return _sendRequest(method: 'DELETE', uri: uri, headers: headers);
      default:
        throw ArgumentError('Desteklenmeyen method: $method');
    }
  }

  Future<http.Response> _sendRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
    bool retryOnTransportError = true,
  }) async {
    Future<http.Response> execute() {
      switch (method) {
        case 'GET':
          return http.get(uri, headers: headers);
        case 'POST':
          return http.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        case 'PATCH':
          return http.patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? <String, dynamic>{}),
          );
        case 'DELETE':
          return http.delete(uri, headers: headers);
        default:
          throw ArgumentError('Desteklenmeyen method: $method');
      }
    }

    try {
      return await execute().timeout(_requestTimeout);
    } on TimeoutException {
      if (retryOnTransportError) {
        await Future<void>.delayed(_retryDelay);
        return _sendRequest(
          method: method,
          uri: uri,
          headers: headers,
          body: body,
          retryOnTransportError: false,
        );
      }
      throw ApiException('Sunucu zaman asimina ugradi. Tekrar deneyin.');
    } on http.ClientException catch (error) {
      if (retryOnTransportError) {
        await Future<void>.delayed(_retryDelay);
        return _sendRequest(
          method: method,
          uri: uri,
          headers: headers,
          body: body,
          retryOnTransportError: false,
        );
      }
      throw ApiException(_mapClientError(error));
    }
  }

  void _ensureStatus(
    http.Response response,
    int expectedCode, {
    bool allowEmptyBody = false,
  }) {
    if (response.statusCode == expectedCode) {
      return;
    }

    if (allowEmptyBody && response.body.trim().isEmpty) {
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

    try {
      final raw = jsonDecode(response.body);
      return raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    } on FormatException {
      throw ApiException('Sunucudan gecersiz yanit alindi.');
    }
  }

  String _mapClientError(http.ClientException error) {
    final message = error.message.toLowerCase();
    if (message.contains('certificate') ||
        message.contains('handshake') ||
        message.contains('tls')) {
      return 'SSL baglantisi kurulurken hata olustu.';
    }
    if (message.contains('connection closed') ||
        message.contains('connection reset') ||
        message.contains('failed host lookup') ||
        message.contains('socket')) {
      return 'Sunucuya ulasilamadi. Internet veya DNS baglantisini kontrol edin.';
    }
    return 'Sunucu baglantisinda istemci hatasi olustu.';
  }

  T _parsePayload<T>(String label, T Function() parser) {
    try {
      return parser();
    } on FormatException {
      throw ApiException('$label verisi islenemedi.');
    } on TypeError {
      throw ApiException('$label verisi beklenen formatta degil.');
    }
  }
}
