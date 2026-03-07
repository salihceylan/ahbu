import 'package:flutter/material.dart';
import 'package:ahbu/config/app_config.dart';
import 'package:ahbu/models/device_record.dart';
import 'package:ahbu/models/site_record.dart';
import 'package:ahbu/models/user_role.dart';
import 'package:ahbu/models/user_session.dart';
import 'package:ahbu/services/auth_service.dart';
import 'package:ahbu/services/mqtt_door_service.dart';
import 'package:ahbu/styles/app_colors.dart';
import 'package:ahbu/styles/app_decorations.dart';
import 'package:ahbu/ui/pages/qr_scan_page.dart';
import 'package:ahbu/ui/widgets/yan_menu.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final MqttDoorService _doorService;
  final TextEditingController _gateNameController = TextEditingController();

  AhbuMenuItem _selectedMenu = AhbuMenuItem.dashboard;
  List<SiteRecord> _sites = const <SiteRecord>[];
  bool _isLoadingSites = false;
  bool _isLookingUpDevice = false;
  bool _isSavingDevice = false;
  DeviceRecord? _selectedDevice;
  int? _selectedSiteCode;

  @override
  void initState() {
    super.initState();
    _doorService = MqttDoorService(
      host: mqttHost,
      port: mqttPort,
      username: mqttAppUser,
      password: mqttAppPassword,
      siteId: mqttSiteId,
      doorId: mqttDoorId,
    );
    _doorService.connect();
  }

  @override
  void dispose() {
    _gateNameController.dispose();
    _doorService.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectMenu(AhbuMenuItem item) {
    Navigator.pop(context);
    setState(() => _selectedMenu = item);
    if (item == AhbuMenuItem.deviceAdd && _sites.isEmpty) {
      _loadSites();
    }
  }

  String _roleDescription(UserRole role) {
    switch (role) {
      case UserRole.superUser:
        return 'Tum site ve kullanici yonetimi sirket uygulamasindan yapilir.';
      case UserRole.siteManager:
        return 'Kendi site operasyonlarinizi ve cihaz eslestirmelerinizi yonetebilirsiniz.';
      case UserRole.apartmentOwner:
        return 'Dairenizle ilgili islemleri takip edip izinli komutlari kullanabilirsiniz.';
    }
  }

  String _doorStateText(bool? locked) {
    if (locked == null) {
      return 'Bilinmiyor';
    }
    return locked ? 'Kilitli' : 'Acik / Tetiklenmis';
  }

  Future<void> _openDoor() async {
    final session = widget.authService.session;
    if (session == null) {
      return;
    }

    final error = await _doorService.sendPulseCommand(requestedBy: session.email);
    if (!mounted) {
      return;
    }
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage('Kapi acma komutu gonderildi.');
  }

  Future<void> _loadSites() async {
    if (_isLoadingSites) {
      return;
    }

    setState(() => _isLoadingSites = true);
    final (sites, error) = await widget.authService.listManagerSites();

    if (!mounted) {
      return;
    }

    setState(() => _isLoadingSites = false);
    if (error != null) {
      _showMessage(error);
      return;
    }

    final loadedSites = sites ?? const <SiteRecord>[];
    setState(() {
      _sites = loadedSites;
      _selectedSiteCode ??= _selectedDevice?.siteCode ??
          (loadedSites.length == 1 ? loadedSites.first.id : null);
    });
  }

  Future<void> _scanAndLoadDevice() async {
    if (_isLookingUpDevice) {
      return;
    }

    final scannedUid = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );

    if (!mounted || scannedUid == null || scannedUid.trim().isEmpty) {
      return;
    }

    setState(() => _isLookingUpDevice = true);
    final (device, error) = await widget.authService.lookupAssignableDevice(
      deviceUid: scannedUid,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isLookingUpDevice = false);
    if (error != null) {
      _showMessage(error);
      return;
    }
    if (device == null) {
      _showMessage('Cihaz bilgisi alinamadi.');
      return;
    }

    if (_sites.isEmpty) {
      await _loadSites();
      if (!mounted) {
        return;
      }
    }

    setState(() {
      _selectedDevice = device;
      _selectedSiteCode = device.siteCode ??
          (_sites.length == 1 ? _sites.first.id : null);
      _gateNameController.text = device.gateName ?? '';
    });

    _showMessage('Cihaz bulundu: ${device.deviceUid}');
  }

  Future<void> _saveDeviceAssignment() async {
    final device = _selectedDevice;
    final siteCode = _selectedSiteCode;
    final gateName = _gateNameController.text.trim();

    if (device == null) {
      _showMessage('Once QR koddan cihazi okuyun.');
      return;
    }
    if (siteCode == null) {
      _showMessage('Bir site secin.');
      return;
    }
    if (gateName.length < 2) {
      _showMessage('Kapi adi en az 2 karakter olmali.');
      return;
    }

    setState(() => _isSavingDevice = true);
    final (updatedDevice, error) = await widget.authService.assignDeviceToSiteGate(
      deviceId: device.id,
      siteCode: siteCode,
      gateName: gateName,
    );

    if (!mounted) {
      return;
    }

    setState(() => _isSavingDevice = false);
    if (error != null) {
      _showMessage(error);
      return;
    }
    if (updatedDevice == null) {
      _showMessage('Cihaz atanamadi.');
      return;
    }

    setState(() => _selectedDevice = updatedDevice);
    _showMessage('Cihaz site kapisina atandi.');
  }

  Widget _buildDashboard(UserSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: AppDecorations.glassCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hos Geldiniz',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                session.fullName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 28),
              ),
              const SizedBox(height: 6),
              Text('Rol: ${session.role.label}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: AppDecorations.infoCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profil Bilgisi',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              Text('E-posta: ${session.email}'),
              if (session.phoneNumber != null && session.phoneNumber!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Telefon: ${session.phoneNumber}'),
              ],
              if (session.createdAt != null) ...[
                const SizedBox(height: 8),
                Text('Kayit Tarihi: ${session.createdAt!.toLocal()}'),
              ],
              const SizedBox(height: 8),
              Text(_roleDescription(session.role)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AnimatedBuilder(
          animation: _doorService,
          builder: (context, _) {
            final connectionText = _doorService.connected
                ? 'Bagli'
                : _doorService.connecting
                ? 'Baglaniyor'
                : 'Bagli degil';
            final stateText = _doorStateText(_doorService.doorLocked);

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: AppDecorations.glassCard,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kapi Kontrol',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('MQTT: $connectionText'),
                  const SizedBox(height: 6),
                  Text('Kapi Durumu: $stateText'),
                  if (_doorService.lastUpdatedAt != null) ...[
                    const SizedBox(height: 6),
                    Text('Son Guncelleme: ${_doorService.lastUpdatedAt!.toLocal()}'),
                  ],
                  if (_doorService.lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _doorService.lastError!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_doorService.lastEvent != null && _doorService.lastEvent!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Son Olay: ${_doorService.lastEvent}'),
                  ],
                  const SizedBox(height: 8),
                  Text('Cihaz: $esp32DeviceName'),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _doorService.commandEnabled ? _openDoor : null,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Kapi Ac'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDeviceAddScreen(UserSession session) {
    if (session.role != UserRole.siteManager) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: AppDecorations.glassCard,
        child: const Text('Bu alan yalnizca site yoneticileri icindir.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: AppDecorations.glassCard,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cihaz Ekle',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'QR kodu okuyun. Cihaz sirket hesabinda kayitliysa onu secilen site ve kapiya atayin.',
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isLookingUpDevice ? null : _scanAndLoadDevice,
                    icon: const Icon(Icons.qr_code_scanner_outlined),
                    label: Text(_isLookingUpDevice ? 'Araniyor...' : 'QR Kodu Oku'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isLoadingSites ? null : _loadSites,
                    icon: const Icon(Icons.refresh),
                    label: Text(_isLoadingSites ? 'Yukleniyor...' : 'Siteleri Yenile'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_selectedDevice != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: AppDecorations.infoCard,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedDevice!.deviceUid,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Kayit ID: ${_selectedDevice!.id}'),
                const SizedBox(height: 6),
                Text(
                  _selectedDevice!.siteCode == null
                      ? 'Mevcut atama: Yok'
                      : 'Mevcut atama: Site ${_selectedDevice!.siteCode} / ${_selectedDevice!.gateName ?? 'Kapi adi girilmemis'}',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _selectedSiteCode,
                  decoration: const InputDecoration(labelText: 'Site Secin'),
                  items: _sites
                      .map(
                        (site) => DropdownMenuItem<int>(
                          value: site.id,
                          child: Text('${site.name} (#${site.id})'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedSiteCode = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _gateNameController,
                  decoration: const InputDecoration(
                    labelText: 'Kapi Adi',
                    hintText: 'Ornek: Ana Giris Kapisi',
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSavingDevice ? null : _saveDeviceAssignment,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_isSavingDevice ? 'Kaydediliyor...' : 'Cihazi Ata'),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: AppDecorations.glassCard,
            child: const Text('Atama formunu acmak icin once QR kodu okutun.'),
          ),
      ],
    );
  }

  Widget _buildContent(UserSession session) {
    switch (_selectedMenu) {
      case AhbuMenuItem.dashboard:
        return _buildDashboard(session);
      case AhbuMenuItem.deviceAdd:
        return _buildDeviceAddScreen(session);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.authService.session!;
    final compact = MediaQuery.sizeOf(context).width < 760;

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedMenu == AhbuMenuItem.dashboard ? 'AHBU' : 'Cihaz Ekle'),
      ),
      drawer: YanMenu(
        fullName: session.fullName,
        userEmail: session.email,
        roleLabel: session.role.label,
        selectedItem: _selectedMenu,
        showDeviceAdd: session.role == UserRole.siteManager,
        onSelect: _selectMenu,
        onLogout: () => widget.authService.logout(),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = compact ? constraints.maxWidth : 900.0;
            return SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 16 : 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: _buildContent(session),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
