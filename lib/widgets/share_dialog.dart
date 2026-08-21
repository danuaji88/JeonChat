import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api_service.dart';
import '../theme.dart';
import '../utils/file_download.dart';

/// Dialog "Bagikan Percakapan" (fase 4.2) — buat link publik read-only,
/// export Markdown/HTML, dan kelola (hapus) link yang sudah dibuat. Semua
/// lewat /share (action create/list/revoke/export_md/export_html, lihat
/// ApiService.createShare dkk.) — backend sudah live, dialog ini murni UI.
class ShareDialog extends StatefulWidget {
  final ApiService api;
  final String conversationId;
  final String? conversationTitle;

  const ShareDialog({
    super.key,
    required this.api,
    required this.conversationId,
    this.conversationTitle,
  });

  @override
  State<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<ShareDialog> {
  final _linkController = TextEditingController();

  bool _creatingLink = false;
  String? _createdLink;
  bool _exportingMd = false;
  bool _exportingHtml = false;

  List<Map<String, dynamic>> _shares = [];
  bool _loadingShares = true;

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _loadShares() async {
    setState(() => _loadingShares = true);
    try {
      final shares = await widget.api.listShares();
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _loadingShares = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingShares = false);
      _showError('Gagal memuat daftar link: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: JeonColors.danger));
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 1)));
  }

  Future<void> _createLink() async {
    setState(() => _creatingLink = true);
    try {
      final res = await widget.api.createShare(widget.conversationId);
      final url = (res['url'] ?? '').toString();
      if (url.isEmpty) throw Exception('URL tidak ditemukan pada respons server');
      if (!mounted) return;
      setState(() {
        _createdLink = url;
        _linkController.text = url;
        _creatingLink = false;
      });
      await _loadShares();
    } catch (e) {
      if (!mounted) return;
      setState(() => _creatingLink = false);
      _showError('Gagal membuat link: $e');
    }
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    _showInfo('Link disalin');
  }

  String _fileBase() {
    final title = widget.conversationTitle?.trim();
    final base = (title != null && title.isNotEmpty ? title : 'percakapan')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_')
        .toLowerCase();
    return base.isEmpty ? 'percakapan' : base;
  }

  Future<void> _export(String format) async {
    setState(() {
      if (format == 'export_md') _exportingMd = true;
      if (format == 'export_html') _exportingHtml = true;
    });
    try {
      final content = await widget.api.exportConversation(widget.conversationId, format);
      final ext = format == 'export_md' ? 'md' : 'html';
      final filename = '${_fileBase()}.$ext';
      if (kIsWeb) {
        downloadTextFile(filename, content);
        if (!mounted) return;
        _showInfo('$filename terunduh');
      } else {
        final bytes = Uint8List.fromList(utf8.encode(content));
        await Share.shareXFiles([XFile.fromData(bytes, name: filename, mimeType: 'text/plain')]);
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Gagal export: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (format == 'export_md') _exportingMd = false;
          if (format == 'export_html') _exportingHtml = false;
        });
      }
    }
  }

  Future<void> _confirmRevoke(Map<String, dynamic> share) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JeonColors.surface,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        elevation: 16,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus link ini?',
            style: TextStyle(color: JeonColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('Link ini tidak akan bisa diakses lagi setelah dihapus.',
            style: TextStyle(color: JeonColors.inkFaint, fontSize: 13, height: 1.4)),
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
    final shareId = (share['share_id'] ?? '').toString();
    if (shareId.isEmpty) return;
    try {
      await widget.api.revokeShare(shareId);
      if (!mounted) return;
      setState(() => _shares.removeWhere((s) => (s['share_id'] ?? '').toString() == shareId));
      _showInfo('Link dihapus');
    } catch (e) {
      if (!mounted) return;
      _showError('Gagal hapus link: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.conversationTitle?.trim();
    return Dialog(
      backgroundColor: JeonColors.surface,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      elevation: 16,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Bagikan Percakapan',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                        if (title != null && title.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: JeonColors.inkFaint)),
                        ],
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 18, color: JeonColors.inkMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PremiumButton(label: 'Buat Link', loading: _creatingLink, onTap: _creatingLink ? null : _createLink),
                      if (_createdLink != null) ...[
                        const SizedBox(height: 10),
                        _linkRow(_createdLink!),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _outlineButton('Export Markdown',
                                loading: _exportingMd, onTap: _exportingMd ? null : () => _export('export_md')),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _outlineButton('Export HTML',
                                loading: _exportingHtml, onTap: _exportingHtml ? null : () => _export('export_html')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel('LINK AKTIF'),
                      const SizedBox(height: 8),
                      _sharesSection(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkRow(String url) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _linkController,
            readOnly: true,
            style: const TextStyle(fontSize: 12.5, color: JeonColors.ink),
            decoration: InputDecoration(
              filled: true,
              fillColor: JeonColors.ink.withValues(alpha: 0.06),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _copyLink(url),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: JeonColors.accent, borderRadius: BorderRadius.circular(10)),
            child: const Text('Copy',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF04150A))),
          ),
        ),
      ],
    );
  }

  Widget _outlineButton(String label, {required bool loading, required VoidCallback? onTap}) {
    return SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: JeonColors.accent,
          side: const BorderSide(color: JeonColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: loading
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: JeonColors.accent))
            : Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style:
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: JeonColors.inkMuted, letterSpacing: 1.2));

  Widget _sharesSection() {
    if (_loadingShares) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: JeonColors.accent)),
        ),
      );
    }
    if (_shares.isEmpty) {
      return const Text('Belum ada link aktif',
          style: TextStyle(fontSize: 13, color: JeonColors.inkFaint, fontStyle: FontStyle.italic));
    }
    return Column(children: _shares.map(_shareRow).toList());
  }

  Widget _shareRow(Map<String, dynamic> share) {
    final title = (share['title'] ?? '').toString();
    final url = (share['url'] ?? '').toString();
    final createdAt = (share['created_at'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: JeonColors.surface2,
        border: Border.all(color: JeonColors.borderSoft),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.isEmpty ? 'Percakapan' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                if (url.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(url,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: JeonColors.accent)),
                ],
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(createdAt, style: const TextStyle(fontSize: 10, color: JeonColors.inkFaint)),
                ],
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _confirmRevoke(share),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.delete_outline, size: 18, color: JeonColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tombol premium bersama — tinggi 46, radius 12, shadow halus (black 0.08
/// blur 8), micro-interaction scale 0.98 saat ditekan, loading spinner 16px.
class _PremiumButton extends StatefulWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  const _PremiumButton({required this.label, required this.loading, required this.onTap});

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
            color: JeonColors.accent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF04150A)))
              : Text(widget.label,
                  style: const TextStyle(color: Color(0xFF04150A), fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
