import 'dart:convert';

import 'package:ahbu/models/device_record.dart';
import 'package:ahbu/models/site_record.dart';
import 'package:ahbu/models/user_role.dart';
import 'package:ahbu/models/user_session.dart';
import 'package:ahbu/services/api_exception.dart';
import 'package:ahbu/services/auth_api.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  AuthService({required this.api});

  static const String _storageKey = 'auth_session';

  final AuthApi api;
  UserSession? _session;
  bool _isReady = false;
  bool _isDisposed = false;

  UserSession? get session => _session;
  bool get isLoggedIn => _session != null;
  bool get isReady => _isReady;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    if (raw != null && raw.isNotEmpty) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final loaded = UserSession.fromJson(data);
        if (loaded.role == UserRole.superUser) {
          await prefs.remove(_storageKey);
          _session = null;
        } else {
          _session = loaded;
        }
      } catch (_) {
        await prefs.remove(_storageKey);
      }
    }

    _isReady = true;
    _notifySafely();
  }

  Future<String?> login({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    if (role == UserRole.superUser) {
      return 'Bu uygulamada Super User girisi kapalidir.';
    }

    try {
      _session = await api.login(email: email, password: password, role: role);
      await _persist();
      _notifySafely();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<(String?, String?)> registerSiteManager({
    required String fullName,
    required String email,
    required String password,
    required String phoneNumber,
  }) async {
    try {
      final pendingEmail = await api.registerSiteManager(
        fullName: fullName,
        email: email,
        password: password,
        phoneNumber: phoneNumber,
      );
      return (pendingEmail, null);
    } on ApiException catch (e) {
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<String?> verifySiteManagerEmail({
    required String email,
    required String code,
  }) async {
    try {
      await api.verifySiteManagerEmail(email: email, code: code);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> resendSiteManagerCode({
    required String email,
  }) async {
    try {
      await api.resendSiteManagerCode(email: email);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<(List<SiteRecord>?, String?)> listManagerSites() async {
    final active = _safeRequireSiteManagerSession();
    if (active == null) {
      return (null, 'Bu islem icin aktif site yoneticisi oturumu gerekir.');
    }

    try {
      final sites = await api.listManagerSites(token: active.token);
      return (sites, null);
    } on ApiException catch (e) {
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<(DeviceRecord?, String?)> lookupAssignableDevice({
    required String deviceUid,
  }) async {
    final active = _safeRequireSiteManagerSession();
    if (active == null) {
      return (null, 'Bu islem icin aktif site yoneticisi oturumu gerekir.');
    }

    try {
      final device = await api.lookupAssignableDevice(
        token: active.token,
        deviceUid: deviceUid,
      );
      return (device, null);
    } on ApiException catch (e) {
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<(DeviceRecord?, String?)> assignDeviceToSiteGate({
    required int deviceId,
    required int siteCode,
    required String gateName,
  }) async {
    final active = _safeRequireSiteManagerSession();
    if (active == null) {
      return (null, 'Bu islem icin aktif site yoneticisi oturumu gerekir.');
    }

    try {
      final device = await api.assignDeviceToSiteGate(
        token: active.token,
        deviceId: deviceId,
        siteCode: siteCode,
        gateName: gateName,
      );
      return (device, null);
    } on ApiException catch (e) {
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<void> logout() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    _notifySafely();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_session!.toJson()));
  }

  UserSession? _safeRequireSiteManagerSession() {
    final active = _session;
    if (active == null || active.role != UserRole.siteManager) {
      return null;
    }
    return active;
  }

  void _notifySafely() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
