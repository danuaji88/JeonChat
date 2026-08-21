import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../services/api_service.dart';
import '../services/chat_history_service.dart';
import '../theme.dart';

/// Detail sebuah Project/Workspace (fase 2.2) — 3 tab: Chats (conversation
/// yang masuk project ini), Files (lampiran project via /projects
/// add_file/remove_file), Instruksi (disuntikkan ke AI lewat project_id di
/// /chat & /agent, lihat ApiService.sendChat/sendAgentPrompt).
///
/// Dibuka dari sidebar (tap baris project). Hasil pop (Map) memberi tahu
/// chat_screen.dart apa yang harus dilakukan: buka chat tertentu, buat chat
/// baru di project ini, atau project barusan dihapus (sidebar perlu refresh).
class ProjectDetailScreen extends StatefulWidget {
  final ApiService api;

  /// Snapshot lokal project (dari ChatHistoryService) — dipakai untuk
  /// tampilan instan (nama/instruksi cache lokal) sebelum data fresh dari
  /// /projects (get) selesai dimuat.
  final Map<String, dynamic> project;

  /// Dipanggil setiap kali rename/instruksi/file berubah — supaya sidebar
  /// (chat_screen.dart) me-refresh daftar project-nya.
  final VoidCallback? onChanged;

  const ProjectDetailScreen({super.key, required this.api, required this.project, this.onChanged});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> with SingleTickerProviderStateMixin {
  static const _maxUploadBytes = 50 * 1024 * 1024;

  late final TabController _tabController;
  final _instructionsController = TextEditingController();

  String get _projectId => widget.project['id'] as String;

  String _name = '';
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  bool _fileBusy = false;
  bool _savingInstructions = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _name = (widget.project['name'] as String?)?.trim().isNotEmpty == true
        ? widget.project['name'] as String
        : 'Project';
    _instructionsController.text = (widget.project['instructions'] ?? '').toString();
    _tabController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final all = await ChatHistoryService.listConversations();
    final mine = all.where((c) => c['projectId'] == _projectId).toList();
    try {
      final fresh = await widget.api.getProject(_projectId);
      if (!mounted) return;
      setState(() {
        _conversations = mine;
        if (fresh != null) {
          final freshName = (fresh['name'] as String?)?.trim();
          if (freshName != null && freshName.isNotEmpty) _name = freshName;
          _instructionsController.text = (fresh['instructions'] ?? _instructionsController.text).toString();
          final rawFiles = fresh['files'] as List?;
          _files = rawFiles?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _conversations = mine;
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _renameDialog() async {
    final controller = TextEditingController(text: _name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JeonColors.surface,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        elevation: 16,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ganti nama project',
            style: TextStyle(color: JeonColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: JeonColors.ink.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal', style: TextStyle(color: JeonColors.inkFaint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Simpan', style: TextStyle(color: JeonColors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == _name) return;
    try {
      await ChatHistoryService.renameProject(_projectId, newName);
      if (!mounted) return;
      setState(() => _name = newName);
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal ganti nama: $e')));
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JeonColors.surface,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        elevation: 16,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus project ini?',
            style: TextStyle(color: JeonColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text('"$_name" akan dihapus. Chat di dalamnya tidak ikut terhapus, cuma dilepas dari project.',
            style: const TextStyle(color: JeonColors.inkFaint, fontSize: 13, height: 1.4)),
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
    await ChatHistoryService.deleteProject(_projectId);
    if (!mounted) return;
    Navigator.of(context).pop({'action': 'deleted', 'projectId': _projectId});
  }

  Future<void> _saveInstructions() async {
    setState(() => _savingInstructions = true);
    try {
      await ChatHistoryService.updateProjectInstructions(_projectId, _instructionsController.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Instruksi disimpan'), duration: Duration(seconds: 1)));
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan instruksi: $e')));
    } finally {
      if (mounted) setState(() => _savingInstructions = false);
    }
  }

  void _openChat(String id) => Navigator.of(context).pop({'action': 'open_chat', 'conversationId': id});

  void _createChatInProject() => Navigator.of(context).pop({'action': 'new_chat', 'projectId': _projectId});

  Future<void> _pickAndAddFile() async {
    if (_fileBusy) return;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File "${file.name}" gagal dibaca (kosong) — coba pilih ulang file ini.')),
        );
        return;
      }
      if (bytes.length > _maxUploadBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('File terlalu besar (maks 50MB)')));
        return;
      }
      setState(() => _fileBusy = true);
      final up = await widget.api.uploadFile(name: file.name, bytes: bytes);
      final url = (up['url'] ?? '').toString();
      if (url.isEmpty) throw Exception('Server tidak mengembalikan URL file');
      final added = await widget.api.addFileToProject(_projectId, {
        'name': file.name,
        'url': url,
        'size': bytes.length,
        'type': _extOf(file.name),
      });
      if (!mounted) return;
      setState(() => _files = [..._files, added.isNotEmpty ? added : {'name': file.name, 'url': url}]);
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menambah file: $e')));
    } finally {
      if (mounted) setState(() => _fileBusy = false);
    }
  }

  Future<void> _removeFile(Map<String, dynamic> file) async {
    final fileId = (file['id'] ?? file['file_id'] ?? file['url'] ?? '').toString();
    if (fileId.isEmpty) return;
    try {
      await widget.api.removeFileFromProject(_projectId, fileId);
      if (!mounted) return;
      setState(() => _files.removeWhere((f) => (f['id'] ?? f['file_id'] ?? f['url'])?.toString() == fileId));
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal hapus file: $e')));
    }
  }

  String _extOf(String name) => name.contains('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';

  IconData _fileTypeIcon(String type) {
    const imageExt = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'};
    const docExt = {'pdf', 'doc', 'docx', 'txt', 'md'};
    const sheetExt = {'xls', 'xlsx', 'csv'};
    if (imageExt.contains(type)) return Icons.image_outlined;
    if (sheetExt.contains(type)) return Icons.table_chart_outlined;
    if (docExt.contains(type)) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatSize(dynamic sizeRaw) {
    final bytes = sizeRaw is num ? sizeRaw.toInt() : int.tryParse(sizeRaw?.toString() ?? '');
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      appBar: AppBar(
        backgroundColor: JeonColors.bg,
        elevation: 0,
        title: Text(_name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: JeonColors.ink)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20, color: JeonColors.inkMuted),
            tooltip: 'Ganti nama',
            onPressed: _renameDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: JeonColors.danger),
            tooltip: 'Hapus project',
            onPressed: _confirmDelete,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: JeonColors.accent,
          labelColor: JeonColors.accent,
          unselectedLabelColor: JeonColors.inkFaint,
          labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Chats'),
            Tab(text: 'Files'),
            Tab(text: 'Instruksi'),
          ],
        ),
      ),
      floatingActionButton: _fab(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: JeonColors.accent))
          : TabBarView(
              controller: _tabController,
              children: [
                _chatsTab(),
                _filesTab(),
                _instructionsTab(),
              ],
            ),
    );
  }

  Widget? _fab() {
    if (_loading) return null;
    if (_tabController.index == 0) {
      return FloatingActionButton.extended(
        onPressed: _createChatInProject,
        backgroundColor: JeonColors.accent,
        foregroundColor: const Color(0xFF04150A),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Chat Baru', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      );
    }
    if (_tabController.index == 1) {
      return FloatingActionButton.extended(
        onPressed: _fileBusy ? null : _pickAndAddFile,
        backgroundColor: JeonColors.accent,
        foregroundColor: const Color(0xFF04150A),
        icon: _fileBusy
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF04150A)))
            : const Icon(Icons.attach_file, size: 18),
        label: const Text('Tambah File', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      );
    }
    return null;
  }

  Widget _chatsTab() {
    if (_conversations.isEmpty) {
      return _emptyHint(Icons.chat_bubble_outline, 'Belum ada chat di project ini.\nTap "Chat Baru" untuk mulai.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      itemCount: _conversations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final c = _conversations[i];
        final title = (c['title'] as String?)?.trim().isNotEmpty == true ? c['title'] as String : 'Percakapan Baru';
        return Container(
          decoration: BoxDecoration(
            color: JeonColors.surface2,
            border: Border.all(color: JeonColors.borderSoft),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: const Icon(Icons.chat_bubble_outline, size: 18, color: JeonColors.inkMuted),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.4, color: JeonColors.ink)),
            trailing: const Icon(Icons.chevron_right, size: 18, color: JeonColors.inkFaint),
            onTap: () => _openChat(c['id'] as String),
          ),
        );
      },
    );
  }

  Widget _filesTab() {
    return Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text('⚠️ Gagal memuat file terbaru: $_error',
                style: const TextStyle(fontSize: 11.5, color: JeonColors.danger)),
          ),
        Expanded(
          child: _files.isEmpty
              ? _emptyHint(Icons.folder_open_outlined, 'Belum ada file di project ini.\nTap "Tambah File" untuk upload.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  itemCount: _files.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final f = _files[i];
                    final name = (f['name'] ?? 'File').toString();
                    final type = (f['type'] ?? _extOf(name)).toString();
                    final url = (f['url'] ?? '').toString();
                    final sizeLabel = _formatSize(f['size']);
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: JeonColors.surface2,
                        border: Border.all(color: JeonColors.borderSoft),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: url.isEmpty ? null : () => launchUrlString(url, mode: LaunchMode.externalApplication),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                  color: JeonColors.surface3, borderRadius: BorderRadius.circular(8)),
                              alignment: Alignment.center,
                              child: Icon(_fileTypeIcon(type), size: 17, color: JeonColors.inkMuted),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                                  if (sizeLabel.isNotEmpty)
                                    Text(sizeLabel, style: const TextStyle(fontSize: 10.5, color: JeonColors.inkFaint)),
                                ],
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => _removeFile(f),
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.delete_outline, size: 18, color: JeonColors.danger),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _instructionsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Text('INSTRUKSI AI UNTUK PROJECT INI',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: JeonColors.inkMuted, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        const Text('Disuntikkan otomatis ke AI setiap chat di dalam project ini.',
            style: TextStyle(fontSize: 12, color: JeonColors.inkFaint)),
        const SizedBox(height: 12),
        TextField(
          controller: _instructionsController,
          maxLines: 8,
          style: const TextStyle(fontSize: 13.4, color: JeonColors.ink, height: 1.4),
          decoration: InputDecoration(
            hintText: 'Contoh: Bahasa santai, fokus penjualan, selalu tawarkan produk terkait.',
            hintStyle: const TextStyle(color: JeonColors.inkFaint, fontSize: 12.5),
            filled: true,
            fillColor: JeonColors.ink.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),
        _PremiumButton(
          label: 'Simpan Instruksi',
          loading: _savingInstructions,
          onTap: _savingInstructions ? null : _saveInstructions,
        ),
      ],
    );
  }

  Widget _emptyHint(IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 30, color: JeonColors.inkFaint),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: JeonColors.inkFaint)),
            ],
          ),
        ),
      );
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
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF04150A)),
                )
              : Text(widget.label,
                  style: const TextStyle(color: Color(0xFF04150A), fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
