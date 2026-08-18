import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../screens/onboarding_profile_screen.dart';
import '../screens/settings_screen.dart';
import '../services/api_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import 'upgrade_dialog.dart';

/// Bottom-sheet menu profil (Upgrade plan / Personalization / Profile /
/// Settings / Help / Logout) — dipakai bersama oleh AgentDrawer dan
/// JeonChatSidebar supaya perilakunya konsisten di kedua tempat.
Future<void> showProfileMenu(
  BuildContext context, {
  required ApiService api,
  required ProfileService profile,
  VoidCallback? onClearHistory,
  VoidCallback? onProfileChanged,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: JeonColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: JeonColors.surface3, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 10),
          _menuTile(Icons.star_rounded, 'Upgrade plan', accent: true, onTap: () async {
            Navigator.of(sheetContext).pop();
            await showUpgradeDialog(
              context,
              api: api,
              profile: profile,
              message: 'Naikkan paket untuk membuka fitur Kreator+ dan kuota tanpa batas.',
            );
          }),
          _menuTile(Icons.auto_awesome_outlined, 'Personalization', onTap: () async {
            Navigator.of(sheetContext).pop();
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsScreen(
                api: api,
                profile: profile,
                initialCategory: SettingsCategory.personalization,
                onClearHistory: onClearHistory,
              ),
            ));
          }),
          _menuTile(Icons.person_outline, 'Profile', onTap: () async {
            Navigator.of(sheetContext).pop();
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => OnboardingProfileScreen(api: api, profile: profile, isEditing: true),
            ));
            onProfileChanged?.call();
          }),
          _menuTile(Icons.settings_outlined, 'Settings', onTap: () async {
            Navigator.of(sheetContext).pop();
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SettingsScreen(
                api: api,
                profile: profile,
                onClearHistory: onClearHistory,
              ),
            ));
          }),
          _menuTile(Icons.help_outline, 'Help', onTap: () {
            Navigator.of(sheetContext).pop();
            _showHelpSheet(context);
          }),
          const Divider(color: JeonColors.borderSoft, height: 20, indent: 16, endIndent: 16),
          _menuTile(Icons.logout, 'Log out', danger: true, onTap: () {
            Navigator.of(sheetContext).pop();
            _confirmLogout(context, api);
          }),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Widget _menuTile(IconData icon, String label, {VoidCallback? onTap, bool accent = false, bool danger = false}) {
  final color = danger ? JeonColors.danger : (accent ? JeonColors.accent : JeonColors.ink);
  return ListTile(
    onTap: onTap,
    leading: Icon(icon, size: 19, color: color),
    title: Text(label,
        style: TextStyle(fontSize: 13.6, color: color, fontWeight: accent ? FontWeight.w600 : FontWeight.normal)),
  );
}

void _showHelpSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: JeonColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bantuan & FAQ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: JeonColors.ink)),
            const SizedBox(height: 14),
            _faqItem('Bagaimana cara mulai chat baru?', 'Tap "New chat" di sidebar.'),
            _faqItem('Kenapa kuota gratis terbatas?',
                'Akun tamu/gratis punya batas pesan — upgrade paket untuk kuota lebih besar.'),
            const SizedBox(height: 6),
            const Text('JeonChat Coworker · v1.0.0', style: TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
          ],
        ),
      ),
    ),
  );
}

Widget _faqItem(String q, String a) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: JeonColors.ink)),
          const SizedBox(height: 3),
          Text(a, style: const TextStyle(fontSize: 12, color: JeonColors.inkFaint, height: 1.4)),
        ],
      ),
    );

Future<void> _confirmLogout(BuildContext context, ApiService api) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: JeonColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Keluar akun?', style: TextStyle(color: JeonColors.ink, fontSize: 15.5)),
      content:
          const Text('Kamu perlu login lagi untuk melanjutkan.', style: TextStyle(color: JeonColors.inkFaint, fontSize: 12.8)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal', style: TextStyle(color: JeonColors.inkMuted))),
        TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keluar', style: TextStyle(color: JeonColors.danger))),
      ],
    ),
  );
  if (confirmed != true) return;
  await api.logout();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => LoginScreen(api: api)),
    (route) => false,
  );
}
