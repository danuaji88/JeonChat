import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Custom Skills (backend, via /skills) — beda dari tab "Skills" di Plugin
/// Store (plugins_screen.dart) yang masih lokal/SharedPreferences. Halaman
/// ini list/create/delete/run skill lewat ApiService.
class SkillsScreen extends StatefulWidget {
  final ApiService api;

  const SkillsScreen({super.key, required this.api});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  static const _bg = Colors.black;
  static const _pillBg = Color(0xFF1A1A1A);
  static const _ink = Colors.white;
  static const _inkMuted = Color(0xFF8E8E93);
  static const _deleteRed = Color(0xFFEF5350);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _skills = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> _normalize(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {'name': raw.toString()};
  }

  String _idOf(Map<String, dynamic> skill) => (skill['skill_id'] ?? skill['id'] ?? '').toString();
  String _nameOf(Map<String, dynamic> skill) => (skill['name'] ?? 'Skill').toString();
  String _descOf(Map<String, dynamic> skill) => (skill['description'] ?? skill['desc'] ?? '').toString();

  String _timestampOf(Map<String, dynamic> skill) {
    final raw = skill['created_at'] ?? skill['createdAt'] ?? skill['timestamp'] ?? skill['time'];
    if (raw == null) return '';
    final ms = raw is int ? raw : int.tryParse(raw.toString());
    if (ms == null) return raw.toString();
    final date = DateTime.fromMillisecondsSinceEpoch(ms > 100000000000 ? ms : ms * 1000);
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.api.listSkills();
      if (!mounted) return;
      setState(() {
        _skills = raw.map(_normalize).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _createSkillDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final instructionController = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Skill Baru', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _ink)),
            const SizedBox(height: 14),
            _field(nameController, 'Nama skill', autofocus: true),
            const SizedBox(height: 12),
            _field(descController, 'Deskripsi singkat'),
            const SizedBox(height: 12),
            _field(instructionController, 'Instruksi (apa yang skill ini lakukan)', maxLines: 4),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ink,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('Simpan', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );

    final name = nameController.text.trim();
    if (saved != true || name.isEmpty) return;
    try {
      await widget.api.createSkill(name, descController.text.trim(), instructionController.text.trim());
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal buat skill: $e')));
    }
  }

  Future<void> _deleteSkillConfirm(Map<String, dynamic> skill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Hapus skill ini?', style: TextStyle(color: _ink, fontSize: 15.5)),
        content: Text('"${_nameOf(skill)}" akan dihapus permanen.',
            style: const TextStyle(color: _inkMuted, fontSize: 12.8)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal', style: TextStyle(color: _inkMuted))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus', style: TextStyle(color: _deleteRed))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.deleteSkill(_idOf(skill));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal hapus skill: $e')));
    }
  }

  Future<void> _runSkillDialog(Map<String, dynamic> skill) async {
    final inputController = TextEditingController();
    final input = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Jalankan "${_nameOf(skill)}"', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _ink)),
            const SizedBox(height: 14),
            _field(inputController, 'Input untuk skill ini', maxLines: 3, autofocus: true),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.of(sheetContext).pop(inputController.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ink,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('Jalankan', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
    if (input == null || input.isEmpty || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF171717),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _ink, strokeWidth: 2),
            SizedBox(width: 16),
            Text('Menjalankan skill...', style: TextStyle(color: _ink, fontSize: 13)),
          ],
        ),
      ),
    );
    String result;
    try {
      result = await widget.api.runSkill(_idOf(skill), input);
    } catch (e) {
      result = '⚠️ Gagal menjalankan skill: $e';
    }
    if (!mounted) return;
    Navigator.of(context).pop(); // tutup loading dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(_nameOf(skill), style: const TextStyle(color: _ink, fontSize: 15.5)),
        content: SingleChildScrollView(
          child: SelectableText(result, style: const TextStyle(color: _ink, fontSize: 13, height: 1.4)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup', style: TextStyle(color: _inkMuted)),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String hint, {int maxLines = 1, bool autofocus = false}) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13.4, color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _inkMuted),
        filled: true,
        fillColor: const Color(0xFF262626),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20, color: _ink),
                    tooltip: 'Kembali',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Expanded(
                    child: Text('Custom Skills', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _ink)),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _createSkillDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(999)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 16, color: Colors.black),
                          SizedBox(width: 4),
                          Text('New', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _ink));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 32, color: _inkMuted),
              const SizedBox(height: 10),
              Text('⚠️ $_error', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: _inkMuted)),
            ],
          ),
        ),
      );
    }
    if (_skills.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_outlined, size: 32, color: _inkMuted),
              SizedBox(height: 10),
              Text('Belum ada custom skill. Tap "New" untuk buat.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: _inkMuted)),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _skills.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _skillCard(_skills[i]),
    );
  }

  Widget _skillCard(Map<String, dynamic> skill) {
    final desc = _descOf(skill);
    final timestamp = _timestampOf(skill);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _pillBg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_nameOf(skill), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(desc, style: const TextStyle(fontSize: 12, color: _inkMuted, height: 1.3)),
                ],
                if (timestamp.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(timestamp, style: const TextStyle(fontSize: 10, color: _inkMuted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _runSkillDialog(skill),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(border: Border.all(color: _ink), borderRadius: BorderRadius.circular(999)),
              child: const Text('Run', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _ink)),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _deleteSkillConfirm(skill),
            child: const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.delete_outline, size: 18, color: _deleteRed),
            ),
          ),
        ],
      ),
    );
  }
}
