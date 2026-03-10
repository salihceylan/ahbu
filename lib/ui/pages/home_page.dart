import 'dart:math' as math;

import 'package:ahbu/config/app_config.dart';
import 'package:ahbu/models/apartment_record.dart';
import 'package:ahbu/models/device_record.dart';
import 'package:ahbu/models/door_record.dart';
import 'package:ahbu/models/site_record.dart';
import 'package:ahbu/models/site_structure_record.dart';
import 'package:ahbu/models/user_role.dart';
import 'package:ahbu/models/user_session.dart';
import 'package:ahbu/services/auth_service.dart';
import 'package:ahbu/services/mqtt_door_service.dart';
import 'package:ahbu/styles/app_colors.dart';
import 'package:ahbu/styles/app_decorations.dart';
import 'package:ahbu/ui/pages/qr_scan_page.dart';
import 'package:ahbu/ui/pages/wifi_provision_page.dart';
import 'package:ahbu/ui/widgets/yan_menu.dart';
import 'package:flutter/material.dart';

double _dialogWidthForScreen(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return math.min(420, math.max(280, width - 32));
}

String _blockLabelFromIndex(int index) {
  var current = index + 1;
  var label = '';
  while (current > 0) {
    current -= 1;
    label = '${String.fromCharCode(65 + (current % 26))}$label';
    current = current ~/ 26;
  }
  return '$label Blok';
}

List<int> _distributeApartmentCounts({
  required int blockCount,
  required int apartmentCount,
}) {
  final totalBlocks = blockCount > 0 ? blockCount : 1;
  var remainingApartments = apartmentCount < 0 ? 0 : apartmentCount;
  final counts = <int>[];

  for (var index = 0; index < totalBlocks; index += 1) {
    final blocksLeft = totalBlocks - index;
    final targetForBlock = blocksLeft <= 0
        ? 0
        : (remainingApartments / blocksLeft).ceil();
    counts.add(targetForBlock);
    remainingApartments -= targetForBlock;
  }

  return counts;
}

List<int> _siteBlockApartmentCounts({
  SiteRecord? site,
  SiteStructureRecord? structure,
}) {
  if (site == null && structure == null) {
    return const <int>[1];
  }
  if (structure != null && structure.blocks.isNotEmpty) {
    return structure.blocks.map((block) {
      return structure.apartments
          .where((apartment) => apartment.blockId == block.id)
          .length;
    }).toList();
  }

  return _distributeApartmentCounts(
    blockCount: site?.blockCount ?? 1,
    apartmentCount: site?.apartmentCount ?? 0,
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final MqttDoorService _doorService;

  AhbuMenuItem _selectedMenu = AhbuMenuItem.dashboard;
  List<SiteRecord> _sites = const <SiteRecord>[];
  SiteRecord? _selectedSite;
  SiteStructureRecord? _selectedStructure;
  List<DoorRecord> _myDoors = const <DoorRecord>[];
  List<DeviceRecord> _managedDevices = const <DeviceRecord>[];
  bool _loadingSites = false;
  bool _loadingStructure = false;
  bool _loadingDoors = false;
  bool _loadingManagedDevices = false;
  bool _lookingUpDevice = false;
  bool _assigningQuickDevice = false;
  final Set<int> _busyApartments = <int>{};
  final Set<int> _busyDoors = <int>{};
  final Set<int> _busyManagedDevices = <int>{};
  DeviceRecord? _scannedDevice;
  int? _quickSiteCode;
  int? _quickDoorId;

  UserSession? get _session => widget.authService.session;
  bool get _isSiteManager => _session?.role == UserRole.siteManager;
  bool get _selectedSiteApproved => _selectedSite?.isApproved ?? false;
  bool get _quickSiteApproved =>
      _siteByCode(_quickSiteCode)?.isApproved ?? false;

  String _siteApprovalMessage(SiteRecord? site) {
    if (site == null || site.isApproved) {
      return '';
    }
    return site.approvalStatus == 'rejected'
        ? 'Bu site sirket tarafindan reddedildi. Kapilara cihaz atamadan once sirket onayi gerekir.'
        : 'Bu site sirket onayi bekliyor. Onay gelmeden kapilara cihaz atanamaz.';
  }

  SiteRecord? _siteByCode(int? siteCode) {
    if (siteCode == null) {
      return null;
    }
    for (final site in _sites) {
      if (site.id == siteCode) {
        return site;
      }
    }
    return null;
  }

  Color _siteApprovalColor(String approvalStatus) {
    switch (approvalStatus) {
      case 'pending':
        return Colors.orange.shade700;
      case 'rejected':
        return Colors.red.shade700;
      default:
        return Colors.green.shade700;
    }
  }

  @override
  void initState() {
    super.initState();
    _doorService = MqttDoorService(
      host: mqttHost,
      port: mqttPort,
      username: mqttAppUser,
      password: mqttAppPassword,
    );
    _doorService.connect();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMyDoors();
      if (_isSiteManager) {
        _loadSites();
        _loadManagedDevices();
      }
    });
  }

  @override
  void dispose() {
    _doorService.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectMenu(AhbuMenuItem item) {
    Navigator.pop(context);
    setState(() => _selectedMenu = item);
    if (item == AhbuMenuItem.dashboard) {
      _loadMyDoors();
    } else {
      _loadSites(force: true);
      if (item == AhbuMenuItem.deviceManagement) {
        _loadManagedDevices(force: true);
      }
    }
  }

  Future<void> _loadSites({bool force = false}) async {
    if (_loadingSites) return;
    if (!force && _sites.isNotEmpty) return;

    setState(() => _loadingSites = true);
    final (sites, error) = await widget.authService.listManagerSites();
    if (!mounted) return;
    setState(() => _loadingSites = false);
    if (error != null) {
      _showMessage(error);
      return;
    }

    final loaded = sites ?? const <SiteRecord>[];
    SiteRecord? selected;
    if (_selectedSite != null) {
      for (final site in loaded) {
        if (site.id == _selectedSite!.id) {
          selected = site;
          break;
        }
      }
    }
    selected ??= loaded.isEmpty ? null : loaded.first;

    setState(() {
      _sites = loaded;
      _selectedSite = selected;
      _quickSiteCode = selected?.id;
      _quickDoorId = null;
    });

    if (selected != null) {
      await _loadSiteStructure(selected.id);
    } else if (mounted) {
      setState(() => _selectedStructure = null);
    }
  }

  Future<void> _loadSiteStructure(int siteCode) async {
    if (_loadingStructure) return;
    setState(() => _loadingStructure = true);
    final (structure, error) = await widget.authService.getManagerSiteStructure(
      siteCode: siteCode,
    );
    if (!mounted) return;
    setState(() => _loadingStructure = false);
    if (error != null) {
      _showMessage(error);
      return;
    }
    setState(() {
      _selectedStructure = structure;
      _selectedSite = structure?.site;
      if (_quickSiteCode == siteCode &&
          _quickDoorId != null &&
          !(structure?.doors.any((door) => door.id == _quickDoorId) ?? false)) {
        _quickDoorId = null;
      }
    });
  }

  Future<void> _loadMyDoors() async {
    if (_loadingDoors) return;
    setState(() => _loadingDoors = true);
    final (doors, error) = await widget.authService.listMyDoors();
    if (!mounted) return;
    setState(() => _loadingDoors = false);
    if (error != null) {
      _showMessage(error);
      return;
    }
    final loaded = doors ?? const <DoorRecord>[];
    await _doorService.watchDoors(loaded);
    if (!mounted) return;
    setState(() => _myDoors = loaded);
  }

  Future<void> _loadManagedDevices({bool force = false}) async {
    if (_loadingManagedDevices) return;
    if (!force && _managedDevices.isNotEmpty) return;

    setState(() => _loadingManagedDevices = true);
    final (devices, error) = await widget.authService.listManagerDevices();
    if (!mounted) return;
    setState(() => _loadingManagedDevices = false);
    if (error != null) {
      _showMessage(error);
      return;
    }

    setState(() => _managedDevices = devices ?? const <DeviceRecord>[]);
  }

  Future<void> _openDoor(DoorRecord door) async {
    final session = _session;
    if (session == null || door.mqttSiteId == null) {
      _showMessage('Bu kapiya aktif cihaz tanimlanmamis.');
      return;
    }
    final error = await _doorService.sendPulseCommand(
      mqttSiteId: door.mqttSiteId!,
      doorIndex: door.doorIndex,
      requestedBy: session.loginName ?? session.email,
    );
    if (!mounted) return;
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage('${door.doorName} icin komut gonderildi.');
  }

  Future<void> _openSiteDialog({SiteRecord? site}) async {
    final result = await showDialog<_SiteFormResult>(
      context: context,
      builder: (context) => _SiteDialog(
        site: site,
        structure: site != null && _selectedStructure?.site.id == site.id
            ? _selectedStructure
            : null,
      ),
    );
    if (!mounted || result == null) return;

    final error = site == null
        ? await widget.authService.createManagerSite(
            name: result.name,
            address: result.address,
            city: result.city,
            district: result.district,
            blockApartmentCounts: result.blockApartmentCounts,
            doorCount: result.doorCount,
          )
        : await widget.authService.updateManagerSite(
            siteCode: site.id,
            name: result.name,
            address: result.address,
            city: result.city,
            district: result.district,
            blockApartmentCounts: result.blockApartmentCounts,
            doorCount: result.doorCount,
          );

    if (!mounted) return;
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage(site == null ? 'Site olusturuldu.' : 'Site guncellendi.');
    await _loadSites(force: true);
    await _loadMyDoors();
  }

  Future<void> _openApartmentDialog(ApartmentRecord apartment) async {
    final result = await showDialog<_ApartmentResidentResult>(
      context: context,
      builder: (context) => _ApartmentResidentDialog(apartment: apartment),
    );
    if (!mounted || result == null) return;

    setState(() => _busyApartments.add(apartment.id));
    final error = await widget.authService.upsertManagerApartmentResident(
      apartmentId: apartment.id,
      fullName: result.fullName,
      loginName: result.loginName,
      password: result.password,
      email: result.email,
      phoneNumber: result.phoneNumber,
      isActive: result.isActive,
    );
    if (!mounted) return;
    setState(() => _busyApartments.remove(apartment.id));
    if (error != null) {
      _showMessage(error);
      return;
    }
    await _loadSiteStructure(apartment.siteCode);
    _showMessage('Daire kullanicisi guncellendi.');
  }

  Future<void> _sendApartmentCredentials(ApartmentRecord apartment) async {
    setState(() => _busyApartments.add(apartment.id));
    final error = await widget.authService.sendManagerApartmentCredentials(
      apartmentId: apartment.id,
    );
    if (!mounted) return;
    setState(() => _busyApartments.remove(apartment.id));
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage('Daire giris bilgileri e-posta ile gonderildi.');
  }

  Future<void> _scanAndAssignDoor(DoorRecord door) async {
    final site = _siteByCode(door.siteCode) ?? _selectedStructure?.site;
    if (site != null && !site.isApproved) {
      _showMessage(_siteApprovalMessage(site));
      return;
    }
    final scannedUid = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (!mounted || scannedUid == null || scannedUid.trim().isEmpty) return;

    setState(() => _busyDoors.add(door.id));
    final (device, lookupError) = await widget.authService
        .lookupAssignableDevice(deviceUid: scannedUid);
    if (!mounted) return;
    if (lookupError != null || device == null) {
      setState(() => _busyDoors.remove(door.id));
      _showMessage(lookupError ?? 'Cihaz bilgisi okunamadi.');
      return;
    }

    final assignError = await widget.authService.assignManagerDoorDevice(
      doorId: door.id,
      deviceUid: device.deviceUid,
    );
    if (!mounted) return;
    setState(() => _busyDoors.remove(door.id));
    if (assignError != null) {
      _showMessage(assignError);
      return;
    }
    await _loadSiteStructure(door.siteCode);
    await _loadMyDoors();
    _showMessage('Cihaz ${door.doorName} kapisina atandi.');
  }

  Future<void> _scanAndLoadQuickDevice() async {
    if (_lookingUpDevice) return;
    final scannedUid = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (!mounted || scannedUid == null || scannedUid.trim().isEmpty) return;

    setState(() => _lookingUpDevice = true);
    final (device, error) = await widget.authService.lookupAssignableDevice(
      deviceUid: scannedUid,
    );
    if (!mounted) return;
    setState(() => _lookingUpDevice = false);
    if (error != null || device == null) {
      _showMessage(error ?? 'Cihaz bilgisi okunamadi.');
      return;
    }

    if (_sites.isEmpty) {
      await _loadSites(force: true);
    }
    if (!mounted) return;

    setState(() {
      _scannedDevice = device;
      _quickSiteCode = _selectedSite?.id ?? device.siteCode;
      _quickDoorId = null;
    });
    if (_quickSiteCode != null) {
      await _loadSiteStructure(_quickSiteCode!);
    }
    _showMessage('Cihaz bulundu: ${device.deviceUid}');
  }

  Future<void> _saveQuickAssignment() async {
    if (_scannedDevice == null || _quickDoorId == null) {
      _showMessage('Cihaz ve kapi secimi zorunlu.');
      return;
    }
    final selectedQuickSite = _siteByCode(_quickSiteCode);
    if (selectedQuickSite != null && !selectedQuickSite.isApproved) {
      _showMessage(_siteApprovalMessage(selectedQuickSite));
      return;
    }
    setState(() => _assigningQuickDevice = true);
    final error = await widget.authService.assignManagerDoorDevice(
      doorId: _quickDoorId!,
      deviceUid: _scannedDevice!.deviceUid,
    );
    if (!mounted) return;
    setState(() => _assigningQuickDevice = false);
    if (error != null) {
      _showMessage(error);
      return;
    }
    if (_quickSiteCode != null) {
      await _loadSiteStructure(_quickSiteCode!);
    }
    await _loadManagedDevices(force: true);
    await _loadMyDoors();
    _showMessage('Cihaz secilen kapiya atandi.');
  }

  Future<void> _prepareManagedDeviceEdit(DeviceRecord device) async {
    if (_sites.isEmpty) {
      await _loadSites(force: true);
    }
    if (!mounted) return;

    setState(() {
      _selectedMenu = AhbuMenuItem.deviceManagement;
      _scannedDevice = device;
      _quickSiteCode = device.siteCode ?? _selectedSite?.id;
      _quickDoorId = device.assignedDoorId;
    });

    if (_quickSiteCode != null) {
      await _loadSiteStructure(_quickSiteCode!);
    }
    if (!mounted) return;
    _showMessage('Cihaz baglantisi duzenleme icin secildi.');
  }

  Future<void> _deleteManagedDevice(DeviceRecord device) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cihazi Sil'),
        content: Text(
          '${device.deviceUid} kaydini silmek istediginize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgec'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (approved != true) {
      return;
    }

    setState(() => _busyManagedDevices.add(device.id));
    final error = await widget.authService.deleteManagerDevice(
      deviceId: device.id,
    );
    if (!mounted) return;
    setState(() => _busyManagedDevices.remove(device.id));
    if (error != null) {
      _showMessage(error);
      return;
    }

    if (_scannedDevice?.id == device.id) {
      setState(() {
        _scannedDevice = null;
        _quickDoorId = null;
      });
    }

    await _loadManagedDevices(force: true);
    await _loadMyDoors();
    if (_quickSiteCode != null) {
      await _loadSiteStructure(_quickSiteCode!);
    }
    _showMessage('Cihaz silindi.');
  }

  List<DoorRecord> get _quickDoors {
    final structure = _selectedStructure;
    if (structure == null || structure.site.id != _quickSiteCode) {
      return const <DoorRecord>[];
    }
    return structure.doors;
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.glassCard,
      child: child,
    );
  }

  Widget _buildDashboard(UserSession session) {
    return AnimatedBuilder(
      animation: _doorService,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hos Geldiniz',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    session.fullName,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: 28),
                  ),
                  const SizedBox(height: 6),
                  Text('Rol: ${session.role.label}'),
                  if ((session.loginName ?? '').isNotEmpty)
                    Text('Kullanici adi: ${session.loginName}'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  Chip(
                    label: Text('Site: ${_isSiteManager ? _sites.length : 1}'),
                  ),
                  Chip(label: Text('Erisimli Kapi: ${_myDoors.length}')),
                  Chip(
                    label: Text(
                      _doorService.connected
                          ? 'MQTT Bagli'
                          : _doorService.connecting
                          ? 'MQTT Baglaniyor'
                          : 'MQTT Kapali',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Kapi Erisimleri',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _loadingDoors ? null : _loadMyDoors,
                        icon: _loadingDoors
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_myDoors.isEmpty)
                    const Text(
                      'Bu hesap icin tanimli aktif kapi bulunmuyor.',
                      style: TextStyle(color: AppColors.textMuted),
                    )
                  else
                    ..._myDoors.map(
                      (door) => Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          door.doorName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          door.siteName ??
                                              'Site ${door.siteCode}',
                                          style: const TextStyle(
                                            color: AppColors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed:
                                        _doorService.commandEnabled &&
                                            door.isActive &&
                                            door.mqttSiteId != null
                                        ? () => _openDoor(door)
                                        : null,
                                    icon: const Icon(Icons.lock_open_outlined),
                                    label: const Text('Kapi Ac'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Durum: ${_doorService.doorLockedFor(door) == null
                                    ? 'Durum bilinmiyor'
                                    : _doorService.doorLockedFor(door)!
                                    ? 'Kilitli'
                                    : 'Acik / Tetiklenmis'}',
                              ),
                              Text(
                                door.assignedDeviceUid == null
                                    ? 'Cihaz tanimli degil'
                                    : 'Cihaz: ${door.assignedDeviceUid}',
                              ),
                              if ((_doorService.lastEventFor(door) ?? '')
                                  .isNotEmpty)
                                Text(
                                  'Son olay: ${_doorService.lastEventFor(door)}',
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSiteManagement() {
    if (!_isSiteManager) {
      return _sectionCard(
        child: const Text('Bu alan yalnizca site yoneticileri icindir.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              const SizedBox(
                width: 260,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Site Yonetimi',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Site, blok, daire ve kapi yapisini buradan yonetin.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openSiteDialog(),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Site Ekle'),
              ),
              OutlinedButton.icon(
                onPressed: _loadingSites ? null : () => _loadSites(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Yenile'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_sites.isEmpty && !_loadingSites)
          _sectionCard(
            child: const Text(
              'Henuz yonettiginiz bir site yok. Ilk siteyi olusturun.',
            ),
          )
        else ...[
          ..._sites.map((site) {
            final approvalColor = _siteApprovalColor(site.approvalStatus);
            return Card(
              child: ListTile(
                selected: _selectedSite?.id == site.id,
                title: Row(
                  children: [
                    Expanded(child: Text(site.name)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: approvalColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        site.approvalLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: approvalColor,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${site.blockCount} blok, ${site.apartmentCount} daire, ${site.doorCount} kapi',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openSiteDialog(site: site),
                ),
                onTap: () {
                  setState(() {
                    _selectedSite = site;
                    _quickSiteCode = site.id;
                    _quickDoorId = null;
                  });
                  _loadSiteStructure(site.id);
                },
              ),
            );
          }),
          const SizedBox(height: 16),
          if (_loadingStructure)
            const Center(child: CircularProgressIndicator())
          else if (_selectedStructure != null) ...[
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedStructure!.site.name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _selectedStructure!.site.address ??
                                  '${_selectedStructure!.site.district ?? ''} ${_selectedStructure!.site.city ?? ''}'
                                      .trim(),
                              style: const TextStyle(
                                color: AppColors.textMuted,
                              ),
                            ),
                            if (!_selectedStructure!.site.isApproved) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      (_selectedStructure!
                                                      .site
                                                      .approvalStatus ==
                                                  'rejected'
                                              ? Colors.red
                                              : Colors.orange)
                                          .withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  _siteApprovalMessage(
                                    _selectedStructure!.site,
                                  ),
                                  style: TextStyle(
                                    color:
                                        _selectedStructure!
                                                .site
                                                .approvalStatus ==
                                            'rejected'
                                        ? Colors.red.shade700
                                        : Colors.orange.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            _openSiteDialog(site: _selectedStructure!.site),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          'Blok: ${_selectedStructure!.site.blockCount}',
                        ),
                      ),
                      Chip(
                        label: Text(
                          'Daire: ${_selectedStructure!.site.apartmentCount}',
                        ),
                      ),
                      Chip(
                        label: Text(
                          'Kapi: ${_selectedStructure!.site.doorCount}',
                        ),
                      ),
                      Chip(
                        label: Text(
                          'MQTT Site ID: ${_selectedStructure!.site.mqttSiteId}',
                        ),
                      ),
                      Chip(label: Text(_selectedStructure!.site.approvalLabel)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daire Kullanici Hesaplari',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  ..._selectedStructure!.apartments.map((apartment) {
                    final loginName = apartment.residentLoginName ?? '-';
                    final pinCode = apartment.residentPinCode ?? '-';
                    final active =
                        apartment.residentIsActive ?? apartment.isActive;
                    return Card(
                      child: ListTile(
                        title: Text(apartment.label),
                        subtitle: Text(
                          '${apartment.residentFullName ?? 'Henuz kullanici tanimlanmadi'} | Kullanici: $loginName | PIN: $pinCode',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _busyApartments.contains(apartment.id)
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (apartment.residentEmail != null)
                                    IconButton(
                                      tooltip: 'Giris bilgilerini mail gonder',
                                      onPressed: () =>
                                          _sendApartmentCredentials(apartment),
                                      icon: const Icon(Icons.mail_outline),
                                    ),
                                  Icon(
                                    active ? Icons.toggle_on : Icons.toggle_off,
                                    color: active
                                        ? Colors.green
                                        : Colors.redAccent,
                                    size: 32,
                                  ),
                                ],
                              ),
                        onTap: () => _openApartmentDialog(apartment),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kapilar ve Cihazlar',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  ..._selectedStructure!.doors.map(
                    (door) => Card(
                      child: ListTile(
                        title: Text(door.doorName),
                        subtitle: Text(
                          door.assignedDeviceUid == null
                              ? 'Cihaz atanmamis'
                              : 'Cihaz: ${door.assignedDeviceUid}',
                        ),
                        trailing: _busyDoors.contains(door.id)
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                Icons.qr_code_scanner_outlined,
                                color: _selectedSiteApproved
                                    ? AppColors.primary
                                    : AppColors.textMuted,
                              ),
                        onTap: _selectedSiteApproved
                            ? () => _scanAndAssignDoor(door)
                            : () => _showMessage(
                                _siteApprovalMessage(_selectedStructure!.site),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildDeviceManagement() {
    if (!_isSiteManager) {
      return _sectionCard(
        child: const Text('Bu alan yalnizca site yoneticileri icindir.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cihaz Yonetimi',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sirket hesabinda kayitli cihazi QR ile okuyun ve yonettiginiz bir kapıya atayin.',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: _lookingUpDevice
                        ? null
                        : _scanAndLoadQuickDevice,
                    icon: const Icon(Icons.qr_code_scanner_outlined),
                    label: Text(
                      _lookingUpDevice ? 'Araniyor...' : 'QR Kodu Oku',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loadingSites || _loadingManagedDevices
                        ? null
                        : () async {
                            await _loadSites(force: true);
                            await _loadManagedDevices(force: true);
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Yenile'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const WifiProvisionPage(),
                      ),
                    ),
                    icon: const Icon(Icons.bluetooth_searching_outlined),
                    label: const Text('Bluetooth ile Wi-Fi Kur'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_scannedDevice != null)
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _scannedDevice!.deviceUid,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Kayit ID: ${_scannedDevice!.id}'),
                Text(
                  _scannedDevice!.siteCode == null
                      ? 'Durum: Henuz bir kapiya atanmamis'
                      : 'Mevcut Site Kodu: ${_scannedDevice!.siteCode}',
                ),
                if (!_quickSiteApproved &&
                    _siteByCode(_quickSiteCode) != null) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final quickSite = _siteByCode(_quickSiteCode)!;
                      final warningColor =
                          quickSite.approvalStatus == 'rejected'
                          ? Colors.red
                          : Colors.orange;
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: warningColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _siteApprovalMessage(quickSite),
                          style: TextStyle(
                            color: quickSite.approvalStatus == 'rejected'
                                ? Colors.red.shade700
                                : Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _quickSiteCode,
                  decoration: const InputDecoration(labelText: 'Site'),
                  items: _sites
                      .map(
                        (site) => DropdownMenuItem<int>(
                          value: site.id,
                          child: Text('${site.name} (${site.approvalLabel})'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _quickSiteCode = value;
                      _quickDoorId = null;
                    });
                    _loadSiteStructure(value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _quickDoorId,
                  decoration: const InputDecoration(labelText: 'Kapi'),
                  items: _quickDoors
                      .map(
                        (door) => DropdownMenuItem<int>(
                          value: door.id,
                          child: Text(door.doorName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _quickDoorId = value),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _assigningQuickDevice || !_quickSiteApproved
                        ? null
                        : _saveQuickAssignment,
                    icon: const Icon(Icons.link_outlined),
                    label: Text(
                      _assigningQuickDevice
                          ? 'Ataniyor...'
                          : 'Baglantiyi Kaydet',
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tum Cihazlar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loadingManagedDevices
                        ? null
                        : () => _loadManagedDevices(force: true),
                    icon: _loadingManagedDevices
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_loadingManagedDevices && _managedDevices.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (_managedDevices.isEmpty)
                const Text('Bu yonetici icin kayitli cihaz bulunmuyor.')
              else
                ..._managedDevices.map((device) {
                  final busy = _busyManagedDevices.contains(device.id);
                  final siteLabel = device.siteName ?? 'Bagli site yok';
                  final doorLabel =
                      device.assignedDoorName ??
                      device.gateName ??
                      'Kapi atanmamis';
                  final statusColor = device.siteCode == null
                      ? AppColors.textMuted
                      : device.siteApproved
                      ? Colors.green.shade700
                      : device.siteApprovalStatus == 'rejected'
                      ? Colors.red.shade700
                      : Colors.orange.shade700;
                  final statusLabel = device.siteCode == null
                      ? 'Bosta'
                      : device.siteApproved
                      ? 'Bagli'
                      : device.siteApprovalStatus == 'rejected'
                      ? 'Reddedilen Site'
                      : 'Onay Bekleyen Site';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(device.deviceUid),
                      subtitle: Text(
                        'Site: $siteLabel | Kapi: $doorLabel',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Wrap(
                              spacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Duzenle',
                                  onPressed: () =>
                                      _prepareManagedDeviceEdit(device),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Sil',
                                  onPressed: () => _deleteManagedDevice(device),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    Widget content;
    if (_selectedMenu == AhbuMenuItem.siteManagement) {
      content = _buildSiteManagement();
    } else if (_selectedMenu == AhbuMenuItem.deviceManagement) {
      content = _buildDeviceManagement();
    } else {
      content = _buildDashboard(session);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedMenu == AhbuMenuItem.dashboard
              ? 'AHBU'
              : _selectedMenu == AhbuMenuItem.siteManagement
              ? 'Site Yonetimi'
              : 'Cihaz Yonetimi',
        ),
      ),
      drawer: YanMenu(
        fullName: session.fullName,
        identityText: session.loginName ?? session.email,
        roleLabel: session.role.label,
        selectedItem: _selectedMenu,
        showSiteManagement: session.role == UserRole.siteManager,
        showDeviceManagement: session.role == UserRole.siteManager,
        onSelect: _selectMenu,
        onLogout: () => widget.authService.logout(),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 720 ? 16.0 : 24.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Align(alignment: Alignment.topCenter, child: content),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SiteDialog extends StatefulWidget {
  const _SiteDialog({this.site, this.structure});

  final SiteRecord? site;
  final SiteStructureRecord? structure;

  @override
  State<_SiteDialog> createState() => _SiteDialogState();
}

class _SiteDialogState extends State<_SiteDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _districtController;
  late final TextEditingController _blockController;
  late final TextEditingController _doorController;
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _blockApartmentControllers =
      <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    final initialBlockApartmentCounts = _siteBlockApartmentCounts(
      site: widget.site,
      structure: widget.structure,
    );
    _nameController = TextEditingController(text: widget.site?.name ?? '');
    _addressController = TextEditingController(
      text: widget.site?.address ?? '',
    );
    _cityController = TextEditingController(text: widget.site?.city ?? '');
    _districtController = TextEditingController(
      text: widget.site?.district ?? '',
    );
    _blockController = TextEditingController(
      text: '${initialBlockApartmentCounts.length}',
    );
    _doorController = TextEditingController(
      text: '${widget.site?.doorCount ?? 1}',
    );
    _syncBlockApartmentControllers(
      initialBlockApartmentCounts.length,
      seedCounts: initialBlockApartmentCounts,
    );
    _blockController.addListener(_handleBlockCountChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _districtController.dispose();
    _blockController.removeListener(_handleBlockCountChanged);
    _blockController.dispose();
    _doorController.dispose();
    for (final controller in _blockApartmentControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleBlockCountChanged() {
    final blockCount = int.tryParse(_blockController.text.trim());
    if (blockCount == null ||
        blockCount <= 0 ||
        blockCount == _blockApartmentControllers.length) {
      return;
    }
    setState(() {
      _syncBlockApartmentControllers(blockCount);
    });
  }

  void _syncBlockApartmentControllers(
    int targetCount, {
    List<int>? seedCounts,
  }) {
    final counts =
        seedCounts ??
        _blockApartmentControllers
            .map((controller) => int.tryParse(controller.text.trim()) ?? 1)
            .toList();

    while (_blockApartmentControllers.length < targetCount) {
      _blockApartmentControllers.add(TextEditingController());
    }
    while (_blockApartmentControllers.length > targetCount) {
      _blockApartmentControllers.removeLast().dispose();
    }

    for (var index = 0; index < _blockApartmentControllers.length; index += 1) {
      final value = index < counts.length ? counts[index] : 1;
      _blockApartmentControllers[index].text = '$value';
    }
  }

  List<int> get _blockApartmentCounts => _blockApartmentControllers
      .map((controller) => int.tryParse(controller.text.trim()) ?? 0)
      .toList();

  @override
  Widget build(BuildContext context) {
    final totalApartments = _blockApartmentCounts.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    return AlertDialog(
      title: Text(widget.site == null ? 'Site Ekle' : 'Siteyi Duzenle'),
      content: SizedBox(
        width: _dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Site Adi'),
                  validator: (value) => (value ?? '').trim().length < 3
                      ? 'Site adi en az 3 karakter olmali.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Adres'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(labelText: 'Il'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _districtController,
                  decoration: const InputDecoration(labelText: 'Ilce'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _blockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Blok Sayisi'),
                  validator: (value) =>
                      (int.tryParse((value ?? '').trim()) ?? 0) < 1
                      ? 'Blok sayisi en az 1 olmali.'
                      : null,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.inputBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Blok Daire Dagilimi',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      for (
                        var index = 0;
                        index < _blockApartmentControllers.length;
                        index += 1
                      ) ...[
                        Text(
                          _blockLabelFromIndex(index),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _blockApartmentControllers[index],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Daire Sayisi',
                          ),
                          validator: (value) =>
                              (int.tryParse((value ?? '').trim()) ?? 0) < 1
                              ? 'Her blokta en az 1 daire olmali.'
                              : null,
                        ),
                        if (index != _blockApartmentControllers.length - 1)
                          const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Toplam Daire: $totalApartments',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _doorController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Otomatik Kapi Sayisi',
                  ),
                  validator: (value) =>
                      (int.tryParse((value ?? '').trim()) ?? 0) < 1
                      ? 'Kapi sayisi en az 1 olmali.'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgec'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              _SiteFormResult(
                name: _nameController.text.trim(),
                address: _addressController.text.trim(),
                city: _cityController.text.trim(),
                district: _districtController.text.trim(),
                blockApartmentCounts: _blockApartmentCounts,
                doorCount: int.parse(_doorController.text.trim()),
              ),
            );
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _ApartmentResidentDialog extends StatefulWidget {
  const _ApartmentResidentDialog({required this.apartment});

  final ApartmentRecord apartment;

  @override
  State<_ApartmentResidentDialog> createState() =>
      _ApartmentResidentDialogState();
}

class _ApartmentResidentDialogState extends State<_ApartmentResidentDialog> {
  late final TextEditingController _fullNameController;
  late final TextEditingController _loginController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _phoneController;
  final _formKey = GlobalKey<FormState>();
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.apartment.residentFullName ?? '',
    );
    _loginController = TextEditingController(
      text: widget.apartment.residentLoginName ?? '',
    );
    _emailController = TextEditingController(
      text: widget.apartment.residentEmail ?? '',
    );
    _passwordController = TextEditingController(
      text: widget.apartment.residentPinCode ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.apartment.residentPhoneNumber ?? '',
    );
    _isActive = widget.apartment.residentIsActive ?? widget.apartment.isActive;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _loginController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.apartment.label} kullanicisi'),
      content: SizedBox(
        width: _dialogWidthForScreen(context),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'Ad Soyad'),
                  validator: (value) => (value ?? '').trim().length < 3
                      ? 'Ad Soyad en az 3 karakter olmali.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _loginController,
                  decoration: const InputDecoration(labelText: 'Kullanici Adi'),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.length < 3) {
                      return 'Kullanici adi en az 3 karakter olmali.';
                    }
                    if (!RegExp(r'^[a-z0-9._-]+$').hasMatch(text)) {
                      return 'Kullanici adi yalnizca harf, rakam, nokta, alt tire ve tire icerebilir.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Daire Sakini E-postasi',
                    helperText: 'Mail gonderimi icin opsiyonel.',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    return text.contains('@') ? null : 'Gecerli e-posta girin.';
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    helperText: '4 haneli sayisal sifre.',
                  ),
                  validator: (value) =>
                      RegExp(r'^\d{4}$').hasMatch((value ?? '').trim())
                      ? null
                      : 'PIN 4 haneli sayisal olmali.',
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      final randomPin = (1000 + math.Random().nextInt(9000))
                          .toString();
                      _passwordController.text = randomPin;
                    },
                    icon: const Icon(Icons.password_outlined),
                    label: const Text('Rastgele PIN'),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  title: const Text('Aktif'),
                  subtitle: const Text(
                    'Pasif kullanici giris yapamaz ve kapi komutu veremez.',
                  ),
                  onChanged: (value) => setState(() => _isActive = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgec'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              _ApartmentResidentResult(
                fullName: _fullNameController.text.trim(),
                loginName: _loginController.text.trim().toLowerCase(),
                email: _emailController.text.trim(),
                password: _passwordController.text.trim(),
                phoneNumber: _phoneController.text.trim(),
                isActive: _isActive,
              ),
            );
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _SiteFormResult {
  const _SiteFormResult({
    required this.name,
    required this.address,
    required this.city,
    required this.district,
    required this.blockApartmentCounts,
    required this.doorCount,
  });

  final String name;
  final String address;
  final String city;
  final String district;
  final List<int> blockApartmentCounts;
  final int doorCount;
}

class _ApartmentResidentResult {
  const _ApartmentResidentResult({
    required this.fullName,
    required this.loginName,
    required this.email,
    required this.password,
    required this.phoneNumber,
    required this.isActive,
  });

  final String fullName;
  final String loginName;
  final String email;
  final String password;
  final String phoneNumber;
  final bool isActive;
}
