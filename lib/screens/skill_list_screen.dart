import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';
import 'skill_detail_screen.dart';
import 'skill_edit_screen.dart';

/// "Skill Saya" — daftar instruksi/pengetahuan personal yang AI pelajari
/// dari user via /skill. Backend /agent menyuntikkannya otomatis ke setiap
/// percakapan (lihat AutoLearn di chat_bubble.dart) — tidak dipilih manual
/// di sini, halaman ini murni buat lihat/tambah/hapus.
class SkillListScreen extends StatefulWidget {
  final ApiService api;

  /// Dipanggil tiap kali daftar berubah (load/tambah/hapus) — dibubblekan
  /// sampai ke sidebar biar badge "🧠 N skill" ikut segar.
  final VoidCallback? onChanged;

  const SkillListScreen({super.key, required this.api, this.onChanged});

  @override
  State<SkillListScreen> createState() => _SkillListScreenState();
}

class _SkillListScreenState extends State<SkillListScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _skills = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _nameOf(Map<String, dynamic> s) => (s['name'] ?? '').toString();

  String _sizeOf(Map<String, dynamic> s) {
    final raw = s['size'];
    return raw == null ? '' : '$raw B';
  }

  String _updatedOf(Map<String, dynamic> s) => (s['updated'] ?? '').toString();

  /// Ikon default 🧠, tapi sedikit bervariasi berdasar kata kunci di nama
  /// skill supaya daftar lebih mudah dipindai sekilas.
  String _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('video')) return '🎬';
    if (n.contains('thumbnail') || n.contains('gambar') || n.contains('foto')) return '🖼️';
    if (n.contains('suara') || n.contains('voice') || n.contains('audio')) return '🔊';
    if (n.contains('tulis') || n.contains('caption') || n.contains('teks')) return '✍️';
    return '🧠';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final skills = await widget.api.listUserSkills();
      if (!mounted) return;
      setState(() {
        _skills = skills;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal memuat skill'), backgroundColor: JeonColors.danger),
      );
    } finally {
      widget.onChanged?.call();
    }
  }

  Future<void> _openDetail(Map<String, dynamic> skill) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SkillDetailScreen(api: widget.api, name: _nameOf(skill))),
    );
    if (changed == true) await _load();
  }

  Future<void> _addSkill() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SkillEditScreen(api: widget.api)),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(Map<String, dynamic> skill) async {
    final name = _nameOf(skill);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: JeonColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Hapus skill ini?', style: TextStyle(color: JeonColors.ink, fontSize: 15.5)),
        content: Text('"$name" akan dihapus permanen.', style: const TextStyle(color: JeonColors.inkFaint, fontSize: 12.8)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal', style: TextStyle(color: JeonColors.inkMuted))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus', style: TextStyle(color: JeonColors.danger))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.deleteUserSkill(name);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menghapus skill'), backgroundColor: JeonColors.danger),
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
        title: const Text('Skill Saya', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSkill,
        backgroundColor: JeonColors.accent,
        foregroundColor: const Color(0xFF04150A),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JeonColors.accent))
          : _skills.isEmpty
              ? _emptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _skills.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _skillCard(_skills[i]),
                ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🧠', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 14),
              const Text('Belum ada skill.',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: JeonColors.ink)),
              const SizedBox(height: 8),
              const Text(
                'Ajarkan AI sesuatu — contoh: "Ingat, setiap buat video selalu 9:16". Sistem akan otomatis menyimpannya.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: JeonColors.inkFaint, height: 1.5),
              ),
            ],
          ),
        ),
      );

  Widget _skillCard(Map<String, dynamic> skill) {
    final name = _nameOf(skill);
    final size = _sizeOf(skill);
    final updated = _updatedOf(skill);
    final meta = [if (size.isNotEmpty) size, if (updated.isNotEmpty) 'diperbarui $updated'].join(' • ');
    return InkWell(
      borderRadius: BorderRadius.circular(JeonRadius.card),
      onTap: () => _openDetail(skill),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: JeonColors.surface2,
          border: Border.all(color: JeonColors.borderSoft),
          borderRadius: BorderRadius.circular(JeonRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: JeonColors.surface3, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: Text(_iconFor(name), style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: JeonColors.ink)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(meta, style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
                  ],
                ],
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _delete(skill),
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.delete_outline, size: 18, color: JeonColors.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
