import 'package:flutter/material.dart';

import '../models/agent.dart';
import '../screens/login_screen.dart';
import '../screens/onboarding_profile_screen.dart';
import '../screens/settings_screen.dart';
import '../services/api_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import 'upgrade_dialog.dart';

class AgentDrawer extends StatelessWidget {
  final List<Agent> agents;
  final ApiService api;
  final ProfileService profile;
  final VoidCallback? onClearHistory;
  final VoidCallback? onProfileChanged;

  const AgentDrawer({
    super.key,
    required this.agents,
    required this.api,
    required this.profile,
    this.onClearHistory,
    this.onProfileChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: JeonColors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [JeonColors.accent, JeonColors.accentDim],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Text('J',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF04150A))),
                  ),
                  const SizedBox(width: 10),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: JeonColors.ink),
                      children: [
                        TextSpan(text: 'JeonChat '),
                        TextSpan(
                          text: 'Coworker',
                          style: TextStyle(color: JeonColors.inkFaint, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _navItem(Icons.chat_bubble_outline, 'Percakapan', active: true),
            _navItem(Icons.dashboard_outlined, 'Ruang Kerja'),
            _navItem(Icons.perm_media_outlined, 'Media & Konten'),
            _navItem(Icons.hub_outlined, 'Integrasi'),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'AGENT AKTIF',
                  style: TextStyle(fontSize: 10.5, letterSpacing: 1.0, color: JeonColors.inkFaint, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            ...agents.map((a) => _agentCard(a)),
            const Spacer(),
            const Divider(color: JeonColors.borderSoft, height: 1),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, {bool active = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: active ? JeonColors.accentGlow : null,
        borderRadius: BorderRadius.circular(JeonRadius.small),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: active ? JeonColors.accent : JeonColors.inkMuted),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.2,
              color: active ? JeonColors.accent : JeonColors.inkMuted,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _agentCard(Agent agent) {
    final running = agent.status == AgentStatus.running;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: running ? JeonColors.accent : JeonColors.inkFaint,
              boxShadow: running
                  ? [BoxShadow(color: JeonColors.accentGlow, blurRadius: 0, spreadRadius: 3)]
                  : null,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(agent.name, style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w500, color: JeonColors.ink)),
                Text(
                  agent.task,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return InkWell(
      onTap: () => _openProfileMenu(context),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: JeonColors.surface3,
                border: Border.all(color: JeonColors.border),
              ),
              alignment: Alignment.center,
              child: Text(profile.avatarEmoji, style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.displayName,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: JeonColors.ink)),
                  Text(api.isGuest ? 'Tamu · Paket Gratis' : 'Owner · Full Access',
                      style: const TextStyle(fontSize: 10.5, color: JeonColors.inkFaint)),
                ],
              ),
            ),
            const Icon(Icons.unfold_more_rounded, size: 16, color: JeonColors.inkFaint),
          ],
        ),
      ),
    );
  }

  Future<void> _openProfileMenu(BuildContext context) async {
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
              _confirmLogout(context);
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
              _faqItem('Bagaimana cara mulai chat baru?', 'Tap ikon "Chat Baru" di kanan atas layar percakapan.'),
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

  Future<void> _confirmLogout(BuildContext context) async {
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
}
