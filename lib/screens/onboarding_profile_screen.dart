import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import 'chat_screen.dart';

class OnboardingProfileScreen extends StatefulWidget {
  final ApiService api;
  final ProfileService profile;
  final bool isEditing;

  const OnboardingProfileScreen({
    super.key,
    required this.api,
    required this.profile,
    this.isEditing = false,
  });

  @override
  State<OnboardingProfileScreen> createState() => _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState extends State<OnboardingProfileScreen> {
  static const _avatarChoices = ['🙂', '🚀', '🎬', '🎨', '🦊', '🌱', '⚡', '🐉'];

  final _nameController = TextEditingController();
  late String _selectedAvatar = _avatarChoices.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.profile.displayName;
    _selectedAvatar = widget.profile.avatarEmoji;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_saving) return;
    setState(() => _saving = true);
    widget.profile.displayName =
        _nameController.text.trim().isEmpty ? 'Appa Jeon' : _nameController.text.trim();
    widget.profile.avatarEmoji = _selectedAvatar;
    await widget.profile.save();
    if (!mounted) return;
    if (widget.isEditing) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => JeonChatScreen(api: widget.api, profile: widget.profile),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.isEditing ? 'Edit Profil' : 'Pilih avatar & nama kamu',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: JeonColors.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.isEditing
                      ? 'Ubah avatar & nama tampilan kamu'
                      : 'Ditampilkan di sidebar percakapan — bisa diubah nanti',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: JeonColors.inkFaint),
                ),
                const SizedBox(height: 28),
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: JeonColors.surface2,
                      border: Border.all(color: JeonColors.accent.withValues(alpha: 0.4), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(_selectedAvatar, style: const TextStyle(fontSize: 34)),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: _avatarChoices.map((emoji) {
                    final selected = emoji == _selectedAvatar;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedAvatar = emoji),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? JeonColors.accentGlow : JeonColors.surface2,
                          border: Border.all(
                            color: selected ? JeonColors.accent : JeonColors.border,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(emoji, style: const TextStyle(fontSize: 19)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 26),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Nama tampilan',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.inkMuted)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(fontSize: 13.5, color: JeonColors.ink),
                  decoration: InputDecoration(
                    hintText: 'Appa Jeon',
                    hintStyle: const TextStyle(color: JeonColors.inkFaint),
                    filled: true,
                    fillColor: JeonColors.surface2,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(JeonRadius.card),
                      borderSide: const BorderSide(color: JeonColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(JeonRadius.card),
                      borderSide: const BorderSide(color: JeonColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(JeonRadius.card),
                      borderSide: const BorderSide(color: JeonColors.accent),
                    ),
                  ),
                  onSubmitted: (_) => _continue(),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _continue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: JeonColors.accent,
                      foregroundColor: const Color(0xFF04150A),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF04150A)),
                          )
                        : Text(widget.isEditing ? 'Simpan' : 'Lanjutkan',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
