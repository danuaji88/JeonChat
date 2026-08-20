import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';

/// Fitur #4 (roadmap JeonChat) — UI untuk endpoint /instructions yang sudah
/// live di backend (lihat ApiService.getInstructions/saveInstructions/
/// clearInstructions). Diakses dari Settings > "Instruksi Kustom".
class CustomInstructionsScreen extends StatefulWidget {
  final ApiService api;

  const CustomInstructionsScreen({super.key, required this.api});

  @override
  State<CustomInstructionsScreen> createState() => _CustomInstructionsScreenState();
}

class _CustomInstructionsScreenState extends State<CustomInstructionsScreen> {
  static const _maxLen = 1500;

  final _aboutMeController = TextEditingController();
  final _responseStyleController = TextEditingController();
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _clearing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _aboutMeController.dispose();
    _responseStyleController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getInstructions();
      if (!mounted) return;
      setState(() {
        _aboutMeController.text = (data['about_me'] ?? '').toString();
        _responseStyleController.text = (data['response_style'] ?? '').toString();
        _enabled = data['enabled'] == true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Gagal memuat instruksi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.api.saveInstructions(
        aboutMe: _aboutMeController.text.trim(),
        responseStyle: _responseStyleController.text.trim(),
        enabled: _enabled,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Instruksi kustom disimpan')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JeonColors.surface,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        elevation: 16,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus instruksi kustom?',
            style: TextStyle(color: JeonColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text(
          'Tentang Kamu dan gaya respons yang tersimpan akan dihapus permanen dari server.',
          style: TextStyle(color: JeonColors.inkFaint, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal', style: TextStyle(color: JeonColors.inkFaint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus', style: TextStyle(color: JeonColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearing = true);
    try {
      await widget.api.clearInstructions();
      if (!mounted) return;
      setState(() {
        _aboutMeController.clear();
        _responseStyleController.clear();
        _enabled = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Instruksi kustom dihapus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus: $e')),
      );
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
        title: const Text('Instruksi Kustom', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: JeonColors.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: JeonColors.danger.withValues(alpha: 0.1),
                      border: Border.all(color: JeonColors.danger.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_error!, style: const TextStyle(fontSize: 12, color: JeonColors.danger)),
                  ),
                  const SizedBox(height: 16),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: JeonColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: JeonColors.border),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('Aktifkan Instruksi Kustom',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                      ),
                      Switch(
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                        activeThumbColor: JeonColors.accent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel('TENTANG KAMU'),
                const SizedBox(height: 8),
                _instructionField(
                  controller: _aboutMeController,
                  hint: 'Contoh: Saya seorang developer Flutter, suka jawaban teknis dan langsung ke inti.',
                ),
                const SizedBox(height: 20),
                _sectionLabel('BAGAIMANA JEON CHAT HARUS MERESPONS'),
                const SizedBox(height: 8),
                _instructionField(
                  controller: _responseStyleController,
                  hint: 'Contoh: Selalu jawab singkat, gunakan bullet point, hindari basa-basi.',
                ),
                const SizedBox(height: 26),
                _PremiumButton(
                  label: 'Simpan',
                  loading: _saving,
                  onTap: _saving ? null : _save,
                  bg: JeonColors.accent,
                  fg: const Color(0xFF04150A),
                ),
                const SizedBox(height: 10),
                _PremiumButton(
                  label: 'Hapus Instruksi',
                  loading: _clearing,
                  onTap: _clearing ? null : _confirmClear,
                  bg: JeonColors.danger.withValues(alpha: 0.12),
                  fg: JeonColors.danger,
                  border: JeonColors.danger.withValues(alpha: 0.3),
                ),
              ],
            ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: JeonColors.inkMuted, letterSpacing: 1.2),
      );

  Widget _instructionField({required TextEditingController controller, required String hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: controller,
          maxLines: 5,
          maxLength: _maxLen,
          style: const TextStyle(fontSize: 13.4, color: JeonColors.ink, height: 1.4),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: JeonColors.inkFaint, fontSize: 12.5),
            filled: true,
            fillColor: JeonColors.ink.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.all(14),
            counterText: '',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 2),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => Text('${controller.text.length}/$_maxLen',
                style: const TextStyle(fontSize: 10.5, color: JeonColors.inkFaint)),
          ),
        ),
      ],
    );
  }
}

/// Tombol premium bersama — tinggi 46, radius 12, shadow halus (black 0.08
/// blur 8), micro-interaction scale 0.98 saat ditekan, loading spinner 16px.
class _PremiumButton extends StatefulWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  final Color bg;
  final Color fg;
  final Color? border;

  const _PremiumButton({
    required this.label,
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
              : Text(widget.label,
                  style: TextStyle(color: widget.fg, fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
