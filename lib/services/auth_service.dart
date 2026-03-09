import 'dart:convert';

import 'package:ahbu/models/device_record.dart';
import 'package:ahbu/models/door_record.dart';
import 'package:ahbu/models/site_record.dart';
import 'package:ahbu/models/site_structure_record.dart';
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
    required String identifier,
    required String password,
    required UserRole role,
  }) async {
    if (role == UserRole.superUser) {
      return 'Bu uygulamada Super User girisi kapalidir.';
    }

    try {
      _session = await api.login(
        identifier: identifier,
        password: password,
        role: role,
      );
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

  Future<String?> resendSiteManagerCode({required String email}) async {
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

  Future<String?> createManagerSite({
    required String name,
    String? address,
    String? city,
    String? district,
    required int blockCount,
    required int apartmentCount,
    required int doorCount,
  }) async {
    final active = _safeRequireSiteManagerSession();
    if (active == null) {
      return 'Bu islem icin aktif site yoneticisi oturumu gerekir.';
    }

    try {
      await api.createManagerSite(
        token: active.token,
        name: name,
        address: address,
        city: city,
        district: district,
        blockCount: blockCount,
        apartmentCount: apartmentCount,
        doorCount: doorCount,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> updateManagerSite({
    required int siteCode,
    String? name,
    String? address,
    String? city,
    String? district,
    int? blockCount,
    int? apartmentCount,
    int? doorCount,
  }) async {
    final active = _safeRequireSiteManagerSession();
    if (active == null) {
      return 'Bu islem icin aktif site yoneticisi oturumu gerekir.';
    }

    try {
      await api.updateManagerSite(
        token: active.token,
        siteCode: siteCode,
        name: name,
        address: address,
        city: city,
        district: district,
        blockCount: blockCount,
        apartmentCount: apartmentCount,
        doorCount: doorCount,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<(SiteStructureRecord?, String?)> getManagerSiteStructure({
    required int siteCode,
  }) async {
    final active = _safeRequireSiteManagerSession();
    if (active == null) {
      return (null, 'Bu islem icin aktif site yoneticisi oturumu gerekir.');
    }

    try {
      final structure = await api.getManagerSiteStructure(
        token: active.token,
        siteCode: siteCode,
      );
      return (structure, null);
    } on ApiException catch (e) {
      return (null, e.message);
    } catch (_) {
      return (null, 'Sunucuya baglanilamadi.');
    }
  }

  Future<String?> upsertManagerApartmentResident({
    required int apartmentId,
    required String fullName,
    required String loginName,
    required String password,
    String? email,
    String? phoneNumber,
    required bool isActive,
  }) async {
    final active = _safeRequireSiteManagerSession();
    if (active == null) {
      return 'Bu islem icin aktif site yoneticisi oturumu gerekir.';
    }

    try {
      await api.upsertManagerApartmentResident(
        token: active.token,
        apartmentId: apartmentId,
        fullName: fullName,
        loginName: loginName,
        password: password,
        email: email,
        phoneNumber: phoneNumber,
        isActive: isActive,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<String?> sendManagerApartmentCredentials({
    required int apartmentId,
  }) async {
    final active = _safeRequireSiteManagerSession();
    if (active == null) {
      return 'Bu islem icin aktif site yoneticisi oturumu gerekir.';
    }

    try {
      await api.sendManagerApartmentCredentials(
        token: active.token,
        apartmentId: apartmentId,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
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

  Future<String?> assignManagerDoorDevice({
    required int doorId,
    required String deviceUid,
  }) async {
    final active = _safeRequireSiteManagerSession();
    if (active == null) {
      return 'Bu islem icin aktif site yoneticisi oturumu gerekir.';
    }

    try {
      await api.assignManagerDoorDevice(
        token: active.token,
        doorId: doorId,
        deviceUid: deviceUid,
      );
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Sunucuya baglanilamadi.';
    }
  }

  Future<(List<DoorRecord>?, String?)> listMyDoors() async {
    final active = _session;
    if (active == null) {
      return (null, 'Oturum bulunamadi.');
    }

    try {
      final doors = await api.listMyDoors(token: active.token);
      return (doors, null);
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


