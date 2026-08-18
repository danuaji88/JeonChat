import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'login_screen.dart';
import 'onboarding_profile_screen.dart';

enum SettingsCategory {
  general,
  notifications,
  personalization,
  plugins,
  voice,
  billing,
  usage,
  dataControls,
  cloudBrowser,
  storage,
  safety,
  securityLogin,
  parentalControls,
  trustedContact,
  account,
  keyboard,
}

extension SettingsCategoryX on SettingsCategory {
  IconData get icon {
    switch (this) {
      case SettingsCategory.general:
        return Icons.settings_outlined;
      case SettingsCategory.notifications:
        return Icons.notifications_outlined;
      case SettingsCategory.personalization:
        return Icons.auto_awesome_outlined;
      case SettingsCategory.plugins:
        return Icons.extension_outlined;
      case SettingsCategory.voice:
        return Icons.graphic_eq_rounded;
      case SettingsCategory.billing:
        return Icons.credit_card_outlined;
      case SettingsCategory.usage:
        return Icons.bar_chart_rounded;
      case SettingsCategory.dataControls:
        return Icons.dataset_outlined;
      case SettingsCategory.cloudBrowser:
        return Icons.cloud_outlined;
      case SettingsCategory.storage:
        return Icons.sd_storage_outlined;
      case SettingsCategory.safety:
        return Icons.shield_outlined;
      case SettingsCategory.securityLogin:
        return Icons.key_outlined;
      case SettingsCategory.parentalControls:
        return Icons.family_restroom_outlined;
      case SettingsCategory.trustedContact:
        return Icons.contact_emergency_outlined;
      case SettingsCategory.account:
        return Icons.person_outline;
      case SettingsCategory.keyboard:
        return Icons.keyboard_outlined;
    }
  }

  String get label {
    switch (this) {
      case SettingsCategory.general:
        return 'General';
      case SettingsCategory.notifications:
        return 'Notifications';
      case SettingsCategory.personalization:
        return 'Personalization';
      case SettingsCategory.plugins:
        return 'Plugins';
      case SettingsCategory.voice:
        return 'Voice';
      case SettingsCategory.billing:
        return 'Billing';
      case SettingsCategory.usage:
        return 'Usage';
      case SettingsCategory.dataControls:
        return 'Data controls';
      case SettingsCategory.cloudBrowser:
        return 'Cloud browser';
      case SettingsCategory.storage:
        return 'Storage';
      case SettingsCategory.safety:
        return 'Safety';
      case SettingsCategory.securityLogin:
        return 'Security and login';
      case SettingsCategory.parentalControls:
        return 'Parental controls';
      case SettingsCategory.trustedContact:
        return 'Trusted contact';
      case SettingsCategory.account:
        return 'Account';
      case SettingsCategory.keyboard:
        return 'Keyboard';
    }
  }
}

class SettingsScreen extends StatefulWidget {
  final ApiService api;
  final ProfileService profile;
  final SettingsCategory? initialCategory;
  final VoidCallback? onClearHistory;

  const SettingsScreen({
    super.key,
    required this.api,
    required this.profile,
    this.initialCategory,
    this.onClearHistory,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _SettingsCategoryScreen(
            category: initial,
            api: widget.api,
            profile: widget.profile,
            onClearHistory: widget.onClearHistory,
          ),
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      appBar: AppBar(
        backgroundColor: JeonColors.bg,
        elevation: 0,
        title: const Text('Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: SettingsCategory.values.length,
        separatorBuilder: (_, __) => const Divider(color: JeonColors.borderSoft, height: 1, indent: 56),
        itemBuilder: (context, i) {
          final cat = SettingsCategory.values[i];
          return ListTile(
            leading: Icon(cat.icon, size: 19, color: JeonColors.inkMuted),
            title: Text(cat.label, style: const TextStyle(fontSize: 13.6, color: JeonColors.ink)),
            trailing: const Icon(Icons.chevron_right, size: 18, color: JeonColors.inkFaint),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _SettingsCategoryScreen(
                category: cat,
                api: widget.api,
                profile: widget.profile,
                onClearHistory: widget.onClearHistory,
              ),
            )),
          );
        },
      ),
    );
  }
}

class _SettingsCategoryScreen extends StatefulWidget {
  final SettingsCategory category;
  final ApiService api;
  final ProfileService profile;
  final VoidCallback? onClearHistory;

  const _SettingsCategoryScreen({
    required this.category,
    required this.api,
    required this.profile,
    this.onClearHistory,
  });

  @override
  State<_SettingsCategoryScreen> createState() => _SettingsCategoryScreenState();
}

class _SettingsCategoryScreenState extends State<_SettingsCategoryScreen> {
  SettingsService? _settings;

  @override
  void initState() {
    super.initState();
    SettingsService.loadFromPrefs().then((s) {
      if (!mounted) return;
      setState(() => _settings = s);
    });
  }

  Future<void> _persist() => _settings?.save() ?? Future.value();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      appBar: AppBar(
        backgroundColor: JeonColors.bg,
        elevation: 0,
        title: Text(widget.category.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: _settings == null
          ? const Center(child: CircularProgressIndicator(color: JeonColors.accent))
          : _content(),
    );
  }

  Widget _content() {
    switch (widget.category) {
      case SettingsCategory.general:
        return _generalContent();
      case SettingsCategory.personalization:
        return _personalizationContent();
      case SettingsCategory.securityLogin:
        return _securityContent();
      case SettingsCategory.dataControls:
        return _dataControlsContent();
      case SettingsCategory.account:
        return _accountContent();
      case SettingsCategory.billing:
        return _statsContent(const []);
      case SettingsCategory.usage:
        return _statsContent(const []);
      default:
        return _placeholder();
    }
  }

  Widget _generalContent() {
    final s = _settings!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: JeonColors.accentGlow,
            border: Border.all(color: JeonColors.accent.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(JeonRadius.card),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, color: JeonColors.accent, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Amankan akunmu dengan verifikasi dua langkah (MFA).',
                    style: TextStyle(fontSize: 12.2, color: JeonColors.ink)),
              ),
              TextButton(
                onPressed: () {},
                child: const Text('Set up MFA', style: TextStyle(fontSize: 12, color: JeonColors.accent)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _dropdownRow('Appearance', s.appearance, const ['System', 'Light', 'Dark'],
            (v) => setState(() {
                  s.appearance = v;
                  _persist();
                })),
        _dropdownRow('Contrast', s.contrast, const ['System', 'Standard', 'High'],
            (v) => setState(() {
                  s.contrast = v;
                  _persist();
                })),
        _dropdownRow('Accent color', s.accentColorPref, const ['Default', 'Hijau', 'Biru', 'Ungu'],
            (v) => setState(() {
                  s.accentColorPref = v;
                  _persist();
                })),
        _dropdownRow('Icon color', s.iconColorPref, const ['Black', 'White', 'Mengikuti aksen'],
            (v) => setState(() {
                  s.iconColorPref = v;
                  _persist();
                })),
        _dropdownRow('Language', s.language, const ['Auto-detect', 'Indonesia', 'English'],
            (v) => setState(() {
                  s.language = v;
                  _persist();
                })),
        const SizedBox(height: 4),
        const Text(
          'Preferensi tampilan di atas tersimpan lokal — efek visual penuh menyusul di update berikutnya.',
          style: TextStyle(fontSize: 10.8, color: JeonColors.inkFaint, height: 1.4),
        ),
        const Divider(color: JeonColors.borderSoft, height: 30),
        _toggleRow('Higher intelligence', 'AI otomatis pakai model lebih pintar (High) untuk pertanyaan kompleks',
            s.higherIntelligence,
            (v) => setState(() {
                  s.higherIntelligence = v;
                  _persist();
                })),
        _toggleRow('Enable Dictation', 'Tampilkan ikon mic dikte di kotak chat', s.enableDictation,
            (v) => setState(() {
                  s.enableDictation = v;
                  _persist();
                })),
      ],
    );
  }

  Widget _dropdownRow(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: JeonColors.ink))),
          DropdownButton<String>(
            value: value,
            dropdownColor: JeonColors.surface2,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontSize: 12.5, color: JeonColors.inkMuted),
            items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, color: JeonColors.ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint, height: 1.3)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeThumbColor: JeonColors.accent),
        ],
      ),
    );
  }

  Widget _personalizationContent() {
    final s = _settings!;
    final callController = TextEditingController(text: s.callMeAs);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Panggil saya sebagai',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.inkMuted)),
        const SizedBox(height: 8),
        TextField(
          controller: callController,
          style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
          decoration: InputDecoration(
            hintText: 'Appa Jeon',
            hintStyle: const TextStyle(color: JeonColors.inkFaint),
            filled: true,
            fillColor: JeonColors.surface2,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(JeonRadius.card), borderSide: const BorderSide(color: JeonColors.border)),
          ),
          onChanged: (v) {
            s.callMeAs = v;
            _persist();
          },
        ),
        const SizedBox(height: 20),
        const Text('Gaya jawaban AI',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.inkMuted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Ringkas', 'Detail', 'Santai', 'Profesional'].map((style) {
            final active = s.aiStyle == style;
            return ChoiceChip(
              label: Text(style),
              selected: active,
              onSelected: (_) => setState(() {
                s.aiStyle = style;
                _persist();
              }),
              selectedColor: JeonColors.accentGlow,
              backgroundColor: JeonColors.surface2,
              labelStyle: TextStyle(fontSize: 12, color: active ? JeonColors.accent : JeonColors.inkMuted),
              side: BorderSide(color: active ? JeonColors.accent : JeonColors.border),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _securityContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.api.isGuest ? 'Mode: Tamu' : 'Mode: Masuk (email)',
            style: const TextStyle(fontSize: 13, color: JeonColors.ink)),
        const SizedBox(height: 4),
        const Text(
          'Password, 2FA, dan sesi aktif akan tersedia setelah backend autentikasi lengkap terhubung.',
          style: TextStyle(fontSize: 11.5, color: JeonColors.inkFaint, height: 1.4),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout, size: 16, color: JeonColors.danger),
            label: const Text('Log out', style: TextStyle(fontSize: 13, color: JeonColors.danger)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: JeonColors.danger),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
            ),
          ),
        ),
      ],
    );
  }

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
    if (confirmed != true || !mounted) return;
    await widget.api.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(api: widget.api)),
      (route) => false,
    );
  }

  Widget _dataControlsContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Semua percakapan JeonChat tersimpan secara lokal di perangkat ini dan tetap ada setelah app ditutup — belum tersinkron ke akun/cloud.',
          style: TextStyle(fontSize: 12, color: JeonColors.inkFaint, height: 1.4),
        ),
        const SizedBox(height: 16),
        if (widget.onClearHistory != null) ...[
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: widget.onClearHistory,
              icon: const Icon(Icons.delete_sweep_outlined, size: 16, color: JeonColors.danger),
              label: const Text('Hapus semua riwayat chat', style: TextStyle(fontSize: 13, color: JeonColors.danger)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: JeonColors.danger),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          height: 44,
          child: OutlinedButton(
            onPressed: () async {
              await _settings?.resetLocalPrefs();
              if (!mounted) return;
              setState(() {});
              ScaffoldMessenger.maybeOf(context)
                  ?.showSnackBar(const SnackBar(content: Text('Preferensi lokal direset ke default')));
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: JeonColors.border),
              foregroundColor: JeonColors.inkMuted,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
            ),
            child: const Text('Reset preferensi lokal', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _accountContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: JeonColors.surface2, border: Border.all(color: JeonColors.border)),
              alignment: Alignment.center,
              child: Text(widget.profile.avatarEmoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.profile.displayName,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                  Text(widget.api.isGuest ? 'Akun Tamu' : 'Akun Login',
                      style: const TextStyle(fontSize: 11.5, color: JeonColors.inkFaint)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 44,
          child: OutlinedButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OnboardingProfileScreen(api: widget.api, profile: widget.profile, isEditing: true),
              ));
              if (mounted) setState(() {});
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: JeonColors.border),
              foregroundColor: JeonColors.inkMuted,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
            ),
            child: const Text('Edit avatar & nama', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _statsContent(List<(String, String)> stats) {
    if (stats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(widget.category.icon, size: 30, color: JeonColors.inkFaint),
            const SizedBox(height: 14),
            Text(widget.category.label,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: JeonColors.ink)),
            const SizedBox(height: 8),
            const Text(
              'Belum ada data — akan terisi otomatis setelah akun ini punya riwayat pemakaian.',
              style: TextStyle(fontSize: 12.5, color: JeonColors.inkFaint, height: 1.5),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: stats
              .map((s) => Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: JeonColors.surface2,
                      border: Border.all(color: JeonColors.borderSoft),
                      borderRadius: BorderRadius.circular(JeonRadius.small),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(s.$1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: JeonColors.ink)),
                        const SizedBox(height: 2),
                        Text(s.$2, style: const TextStyle(fontSize: 10.6, color: JeonColors.inkFaint)),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(widget.category.icon, size: 30, color: JeonColors.inkFaint),
          const SizedBox(height: 14),
          Text(widget.category.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: JeonColors.ink)),
          const SizedBox(height: 8),
          const Text(
            'Pengaturan kategori ini akan dibangun lebih lengkap di update berikutnya.',
            style: TextStyle(fontSize: 12.5, color: JeonColors.inkFaint, height: 1.5),
          ),
        ],
      ),
    );
  }
}
