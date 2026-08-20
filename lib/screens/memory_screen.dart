import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';

/// Hijau khusus badge "auto" (fakta yang AI simpulkan sendiri) — beda dari
/// JeonColors.accent (biru) yang dipakai app-wide, dipilih supaya beda
/// makna secara visual dari "manual" (abu, JeonColors.inkMuted).
const _autoGreen = Color(0xFF3FB950);

/// "Memori Saya" (fase 2.1) — fakta & catatan stabil yang AI ingat lintas
/// percakapan lewat /memory (action get/add/remove/clear, lihat
/// ApiService.getMemory/addMemory/removeMemory/clearMemory). Facts & notes
/// SENGAJA disimpan sebagai dua list terpisah (bukan digabung jadi satu),
/// karena index yang dikirim ke action "remove" itu index DI DALAM masing-
/// masing kind (fact/note), bukan index gabungan.
class MemoryScreen extends StatefulWidget {
  final ApiService api;

  const MemoryScreen({super.key, required this.api});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  List<Map<String, dynamic>> _facts = [];
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;
  bool _clearing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getMemory();
      final facts = (data['facts'] as List?) ?? const [];
      final notes = (data['notes'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _facts = facts.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _notes = notes.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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

  Future<void> _addDialog() async {
    final controller = TextEditingController();
    String kind = 'fact';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: JeonColors.surface,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          elevation: 16,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tambah Memori',
              style: TextStyle(color: JeonColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _kindOption('Fakta', 'fact', kind, (v) => setDialogState(() => kind = v)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _kindOption('Catatan', 'note', kind, (v) => setDialogState(() => kind = v)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
                decoration: InputDecoration(
                  hintText:
                      kind == 'fact' ? 'Contoh: Bekerja sebagai desainer UI' : 'Contoh: Suka kopi tanpa gula',
                  hintStyle: const TextStyle(color: JeonColors.inkFaint, fontSize: 12.5),
                  filled: true,
                  fillColor: JeonColors.ink.withValues(alpha: 0.06),
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  enabledBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  focusedBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal', style: TextStyle(color: JeonColors.inkFaint)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Simpan', style: TextStyle(color: JeonColors.accent, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    final text = controller.text.trim();
    if (saved == true && text.isNotEmpty) {
      try {
        await widget.api.addMemory(kind, text);
        await _load();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
      }
    }
  }

  Widget _kindOption(String label, String value, String current, ValueChanged<String> onSelect) {
    final active = value == current;
    return GestureDetector(
      onTap: () => onSelect(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? JeonColors.accent.withValues(alpha: 0.15) : JeonColors.ink.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? JeonColors.accent : Colors.transparent),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: active ? JeonColors.accent : JeonColors.inkMuted)),
      ),
    );
  }

  Future<void> _removeItem(String kind, int index) async {
    try {
      await widget.api.removeMemory(kind, index);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal hapus: $e')));
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JeonColors.surface,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        elevation: 16,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus semua memori?',
            style: TextStyle(color: JeonColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text(
          'Semua fakta dan catatan yang AI ingat tentang kamu akan dihapus permanen dari server. Tindakan ini tidak bisa dibatalkan.',
          style: TextStyle(color: JeonColors.inkFaint, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal', style: TextStyle(color: JeonColors.inkFaint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus Semua', style: TextStyle(color: JeonColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearing = true);
    try {
      await widget.api.clearMemory();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membersihkan: $e')));
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      appBar: AppBar(
        backgroundColor: JeonColors.bg,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Memori Saya', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: JeonColors.ink)),
            SizedBox(height: 2),
            Text('Hal yang AI ingat tentang kamu', style: TextStyle(fontSize: 12, color: JeonColors.inkFaint)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDialog,
        backgroundColor: JeonColors.accent,
        foregroundColor: const Color(0xFF04150A),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Tambah', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: JeonColors.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 30, color: JeonColors.inkFaint),
              const SizedBox(height: 12),
              Text('Gagal memuat memori.\n$_error',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: JeonColors.inkFaint)),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: _load,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: JeonColors.accent,
                    side: const BorderSide(color: JeonColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Coba Lagi', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final isEmpty = _facts.isEmpty && _notes.isEmpty;
    return RefreshIndicator(
      color: JeonColors.accent,
      backgroundColor: JeonColors.surface2,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (isEmpty)
            _emptyState()
          else ...[
            _sectionLabel('🧠 FAKTA YANG DIINGAT AI'),
            const SizedBox(height: 10),
            if (_facts.isEmpty)
              _sectionEmptyHint('Belum ada fakta.')
            else
              ..._facts.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _memoryCard(e.value, kind: 'fact', index: e.key),
                    ),
                  ),
            const SizedBox(height: 22),
            _sectionLabel('📝 CATATAN SAYA'),
            const SizedBox(height: 10),
            if (_notes.isEmpty)
              _sectionEmptyHint('Belum ada catatan.')
            else
              ..._notes.asMap().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _memoryCard(e.value, kind: 'note', index: e.key),
                    ),
                  ),
            const SizedBox(height: 28),
            _clearAllButton(),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() => const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology_outlined, size: 30, color: JeonColors.inkFaint),
            SizedBox(height: 12),
            Text('Belum ada memori. AI akan mengingat hal penting saat kamu chat.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: JeonColors.inkFaint)),
          ],
        ),
      );

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: JeonColors.inkMuted, letterSpacing: 1.2),
      );

  Widget _sectionEmptyHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: const TextStyle(fontSize: 12, color: JeonColors.inkFaint)),
      );

  Widget _memoryCard(Map<String, dynamic> item, {required String kind, required int index}) {
    final text = (item['text'] ?? '').toString();
    final auto = item['auto'] == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JeonColors.surface2,
        border: Border.all(color: JeonColors.borderSoft),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (kind == 'fact') ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (auto ? _autoGreen : JeonColors.inkMuted).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(auto ? 'auto' : 'manual',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: auto ? _autoGreen : JeonColors.inkMuted)),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(text, style: const TextStyle(fontSize: 13, color: JeonColors.ink, height: 1.4)),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _removeItem(kind, index),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.delete_outline, size: 18, color: JeonColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clearAllButton() => _PremiumButton(
        label: 'Bersihkan Semua',
        icon: Icons.cleaning_services_outlined,
        loading: _clearing,
        onTap: _clearing ? null : _confirmClearAll,
        bg: JeonColors.danger.withValues(alpha: 0.12),
        fg: JeonColors.danger,
        border: JeonColors.danger.withValues(alpha: 0.3),
      );
}

/// Tombol premium bersama — tinggi 46, radius 12, shadow halus (black 0.08
/// blur 8), micro-interaction scale 0.98 saat ditekan, loading spinner 16px.
class _PremiumButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onTap;
  final Color bg;
  final Color fg;
  final Color? border;

  const _PremiumButton({
    required this.label,
    this.icon,
    required this.loading,
    required this.onTap,
    required this.bg,
    required this.fg,
    this.border,
  });

  @override
  State<_PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<_PremiumButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
        onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          height: 46,
          decoration: BoxDecoration(
            color: widget.bg,
            borderRadius: BorderRadius.circular(12),
            border: widget.border != null ? Border.all(color: widget.border!) : null,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: widget.fg),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 18, color: widget.fg),
                      const SizedBox(width: 8),
                    ],
                    Text(widget.label, style: TextStyle(color: widget.fg, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ],
                ),
        ),
      ),
    );
  }
}
