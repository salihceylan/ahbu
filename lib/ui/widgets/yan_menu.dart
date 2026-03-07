import 'package:flutter/material.dart';
import 'package:ahbu/styles/app_colors.dart';

enum AhbuMenuItem {
  dashboard,
  deviceAdd,
}

class YanMenu extends StatelessWidget {
  const YanMenu({
    super.key,
    required this.fullName,
    required this.userEmail,
    required this.roleLabel,
    required this.selectedItem,
    required this.showDeviceAdd,
    required this.onSelect,
    required this.onLogout,
  });

  final String fullName;
  final String userEmail;
  final String roleLabel;
  final AhbuMenuItem selectedItem;
  final bool showDeviceAdd;
  final ValueChanged<AhbuMenuItem> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(topRight: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white,
                    child: ClipOval(
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: Transform.scale(
                          scale: 1.28,
                          child: Image.asset(
                            'assets/images/app_logo.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  userEmail,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  roleLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              children: [
                _MenuTile(
                  icon: Icons.home_outlined,
                  title: 'Ana Sayfa',
                  selected: selectedItem == AhbuMenuItem.dashboard,
                  onTap: () => onSelect(AhbuMenuItem.dashboard),
                ),
                if (showDeviceAdd) ...[
                  const SizedBox(height: 4),
                  _MenuTile(
                    icon: Icons.qr_code_scanner_outlined,
                    title: 'Cihaz Ekle',
                    selected: selectedItem == AhbuMenuItem.deviceAdd,
                    onTap: () => onSelect(AhbuMenuItem.deviceAdd),
                  ),
                ],
                const SizedBox(height: 4),
                _MenuTile(
                  icon: Icons.logout,
                  title: 'Cikis Yap',
                  selected: false,
                  onTap: () {
                    Navigator.pop(context);
                    onLogout();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: selected ? AppColors.primary.withValues(alpha: 0.1) : null,
      leading: Icon(icon, color: AppColors.primary),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}
