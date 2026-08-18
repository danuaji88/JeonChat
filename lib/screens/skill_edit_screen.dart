import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';

/// Tambah/edit satu "Skill Saya" — mode tambah kalau [initialName]/
/// [initialContent] null, mode edit kalau keduanya sudah terisi (dari GET
/// action=get). pop(true) kalau berhasil simpan, biar caller tahu harus
/// refresh daftarnya.
class SkillEditScreen extends StatefulWidget {
  final ApiService api;
  final String? initialName;
  final String? initialContent;

  const SkillEditScreen({super.key, required this.api, this.initialName, this.initialContent});

  @override
  State<SkillEditScreen> createState() => _SkillEditScreenState();
}

class _SkillEditScreenState extends State<SkillEditScreen> {
  late final _nameController = TextEditingController(text: widget.initialName ?? '');
  late final _contentController = TextEditingController(text: widget.initialContent ?? '');
  bool _saving = false;

  bool get _isEditing => widget.initialName != null;

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final content = _contentController.text.trim();
    if (name.isEmpty || content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama dan isi skill wajib diisi')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.saveUserSkill(name, content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Skill "$name" tersimpan'), backgroundColor: const Color(0xFF238636)),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menyimpan skill'), backgroundColor: JeonColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      appBar: AppBar(
        backgroundColor: JeonColors.bg,
        elevation: 0,
        title: Text(_isEditing ? 'Edit Skill' : 'Skill Baru',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nama skill',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.inkMuted)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
              decoration: _decoration('Nama skill, mis: gaya-konten'),
            ),
            const SizedBox(height: 18),
            const Text('Isi skill',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.inkMuted)),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              minLines: 4,
              maxLines: 14,
              style: const TextStyle(fontSize: 13.4, color: JeonColors.ink, height: 1.4),
              decoration: _decoration(
                  'Instruksi lengkap... mis: Kalau bikin konten selalu bahasa santai + emoji'),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 46,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
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
                    : const Text('Simpan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: JeonColors.inkFaint),
        filled: true,
        fillColor: JeonColors.surface2,
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(JeonRadius.card), borderSide: const BorderSide(color: JeonColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(JeonRadius.card), borderSide: const BorderSide(color: JeonColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(JeonRadius.card), borderSide: const BorderSide(color: JeonColors.accent)),
      );
}
