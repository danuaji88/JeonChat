import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';
import 'skill_edit_screen.dart';

/// Isi lengkap satu "Skill Saya" (GET action=get) + tombol Edit/Hapus.
/// pop(true) kalau skill ini diedit atau dihapus, biar SkillListScreen tahu
/// harus refresh.
class SkillDetailScreen extends StatefulWidget {
  final ApiService api;
  final String name;

  const SkillDetailScreen({super.key, required this.api, required this.name});

  @override
  State<SkillDetailScreen> createState() => _SkillDetailScreenState();
}

class _SkillDetailScreenState extends State<SkillDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _skill;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final skill = await widget.api.getUserSkill(widget.name);
      if (!mounted) return;
      setState(() {
        _skill = skill;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal memuat skill'), backgroundColor: JeonColors.danger),
      );
    }
  }

  Future<void> _edit() async {
    final skill = _skill;
    if (skill == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SkillEditScreen(
          api: widget.api,
          initialName: (skill['name'] ?? widget.name).toString(),
          initialContent: (skill['content'] ?? '').toString(),
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: JeonColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Hapus skill ini?', style: TextStyle(color: JeonColors.ink, fontSize: 15.5)),
        content: Text('"${widget.name}" akan dihapus permanen.',
            style: const TextStyle(color: JeonColors.inkFaint, fontSize: 12.8)),
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
      await widget.api.deleteUserSkill(widget.name);
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
        title: Text(widget.name,
            overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (_skill != null) ...[
            TextButton(onPressed: _edit, child: const Text('Edit', style: TextStyle(color: JeonColors.accent))),
            TextButton(onPressed: _delete, child: const Text('Hapus', style: TextStyle(color: JeonColors.danger))),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: JeonColors.accent))
          : _skill == null
              ? const Center(
                  child: Text('Skill tidak ditemukan', style: TextStyle(fontSize: 13, color: JeonColors.inkFaint)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    (_skill?['content'] ?? '').toString(),
                    style: const TextStyle(fontSize: 13.5, color: JeonColors.ink, height: 1.5),
                  ),
                ),
    );
  }
}
