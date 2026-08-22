import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';
import '../services/api_service.dart';
import '../services/chat_history_service.dart';
import '../widgets/audio_message_player.dart';

enum LibraryFilter { all, images, documents }

const _customItemsKey = 'jeon_library_custom_items';

/// Satu entri di Library — bisa hasil auto-collect dari pesan chat
/// (imageUrl/videoUrl/audioUrl/filePath, [id] null), atau item yang dibuat
/// lewat tombol "New ▾" (note/document/spreadsheet/folder/upload, [id] terisi
/// dan tersimpan di SharedPreferences).
class LibraryItem {
  final String? id;
  final String name;
  final String type; // image|video|audio|doc|note|document|spreadsheet|folder|upload
  final String url;
  final DateTime modified;
  final String size;
  final String? content;
  final String? parentId;

  const LibraryItem({
    this.id,
    required this.name,
    required this.type,
    required this.url,
    required this.modified,
    required this.size,
    this.content,
    this.parentId,
  });

  bool get isVisual => type == 'image' || type == 'video';
  bool get isCustom => id != null;
  bool get isEditable => type == 'note' || type == 'document' || type == 'spreadsheet';
}

/// Halaman Library ala ChatGPT — daftar semua gambar/video/audio/file yang
/// pernah di-generate/dikirim di chat, plus note/document/spreadsheet/folder/
/// upload yang dibuat lewat tombol "New ▾" (tersimpan di SharedPreferences).
/// [folderId]/[folderName] terisi saat sedang membuka isi sebuah folder.
class LibraryScreen extends StatefulWidget {
  final String? folderId;
  final String? folderName;
  final ApiService? api;

  const LibraryScreen({super.key, this.folderId, this.folderName, this.api});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  static const _bg = Colors.black;
  static const _pillBg = Color(0xFF1A1A1A);
  static const _divider = Color(0xFF1E1E1E);
  static const _boxGrey = Color(0xFF3A3A3A);
  static const _boxBlue = Color(0xFF0A84FF);
  static const _ink = Colors.white;
  static const _inkMuted = Color(0xFF8E8E93);

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  bool _loading = true;
  List<LibraryItem> _items = [];
  List<Map<String, dynamic>> _customItems = [];
  final Set<String> _fadeInIds = {};
  LibraryFilter _filter = LibraryFilter.all;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _nameFromUrl(String url) {
    final clean = url.split('?').first;
    final slash = clean.lastIndexOf('/');
    final name = slash == -1 ? clean : clean.substring(slash + 1);
    return name.isEmpty ? clean : name;
  }

  String _sizeFor(Map<String, dynamic> raw) {
    final size = raw['size'];
    if (size is String && size.trim().isNotEmpty) return size;
    return '—';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ---- Persistence: item custom (note/document/spreadsheet/folder/upload) ----

  Future<List<Map<String, dynamic>>> _loadCustomItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customItemsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveCustomItems(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customItemsKey, jsonEncode(items));
  }

  Future<void> _load() async {
    final conversations = await ChatHistoryService.listConversations();
    final items = <LibraryItem>[];
    for (final conv in conversations) {
      final updatedAt = conv['updatedAt'] as int?;
      final modified =
          updatedAt != null ? DateTime.fromMillisecondsSinceEpoch(updatedAt) : DateTime.now();
      final rawMessages = conv['messages'];
      if (rawMessages is! List) continue;
      for (final raw in rawMessages.whereType<Map<String, dynamic>>()) {
        final message = ChatMessage.fromJson(raw);
        final size = _sizeFor(raw);
        if (message.imageUrl != null) {
          items.add(LibraryItem(
            name: _nameFromUrl(message.imageUrl!),
            type: 'image',
            url: message.imageUrl!,
            modified: modified,
            size: size,
          ));
        }
        if (message.videoUrl != null) {
          items.add(LibraryItem(
            name: _nameFromUrl(message.videoUrl!),
            type: 'video',
            url: message.videoUrl!,
            modified: modified,
            size: size,
          ));
        }
        if (message.audioUrl != null) {
          items.add(LibraryItem(
            name: _nameFromUrl(message.audioUrl!),
            type: 'audio',
            url: message.audioUrl!,
            modified: modified,
            size: size,
          ));
        }
        if (message.filePath != null) {
          items.add(LibraryItem(
            name: _nameFromUrl(message.filePath!),
            type: 'doc',
            url: message.filePath!,
            modified: modified,
            size: size,
          ));
        }
      }
    }

    final customRaw = await _loadCustomItems();
    for (final raw in customRaw) {
      final createdAt = raw['createdAt'] as int?;
      items.add(LibraryItem(
        id: raw['id'] as String?,
        name: (raw['name'] as String?) ?? 'Untitled',
        type: (raw['type'] as String?) ?? 'document',
        url: '',
        modified: createdAt != null ? DateTime.fromMillisecondsSinceEpoch(createdAt) : DateTime.now(),
        size: (raw['size'] as String?) ?? '0 KB',
        content: raw['content'] as String?,
        parentId: raw['parentId'] as String?,
      ));
    }

    items.sort((a, b) => b.modified.compareTo(a.modified));
    if (!mounted) return;
    setState(() {
      _items = items;
      _customItems = customRaw;
      _loading = false;
    });
  }

  Future<void> _addCustomItem({
    required String id,
    required String name,
    required String type,
    required String size,
    String content = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = {
      'id': id,
      'name': name,
      'type': type,
      'createdAt': now,
      'size': size,
      'content': content,
      'parentId': widget.folderId,
    };
    final updated = [..._customItems, entry];
    await _saveCustomItems(updated);
    if (!mounted) return;
    setState(() {
      _customItems = updated;
      _items = [
        LibraryItem(
          id: id,
          name: name,
          type: type,
          url: '',
          modified: DateTime.fromMillisecondsSinceEpoch(now),
          size: size,
          content: content,
          parentId: widget.folderId,
        ),
        ..._items,
      ];
      _fadeInIds.add(id);
    });
  }

  Future<void> _saveItemContent(String id, String content) async {
    final idx = _customItems.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    final sizeLabel = _formatBytes(content.length);
    final updated = [..._customItems];
    updated[idx] = {...updated[idx], 'content': content, 'size': sizeLabel};
    await _saveCustomItems(updated);
    if (!mounted) return;
    setState(() {
      _customItems = updated;
      _items = _items
          .map((i) => i.id == id
              ? LibraryItem(
                  id: i.id,
                  name: i.name,
                  type: i.type,
                  url: i.url,
                  modified: DateTime.now(),
                  size: sizeLabel,
                  content: content,
                  parentId: i.parentId,
                )
              : i)
          .toList();
    });
  }

  String _fmtDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

  Future<void> _renameCustomItem(String id) async {
    final idx = _customItems.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    final currentName = (_customItems[idx]['name'] ?? '').toString();
    final newName = await _askNameDialog(currentName, 'Ubah nama');
    if (newName == null || newName.isEmpty) return;
    final updated = [..._customItems];
    updated[idx] = {...updated[idx], 'name': newName};
    await _saveCustomItems(updated);
    if (!mounted) return;
    setState(() {
      _customItems = updated;
      _items = _items.map((i) => i.id == id ? LibraryItem(
        id: i.id,
        name: newName,
        type: i.type,
        url: i.url,
        modified: i.modified,
        size: i.size,
        content: i.content,
        parentId: i.parentId,
      ) : i).toList();
    });
  }

  Future<void> _removeCustomItem(String id) async {
    final updated = _customItems.where((c) => c['id'] != id).toList();
    await _saveCustomItems(updated);
    if (!mounted) return;
    setState(() {
      _customItems = updated;
      _items = _items.where((i) => i.id != id).toList();
    });
  }

  List<LibraryItem> get _filtered {
    var list = _items.where((i) => i.parentId == widget.folderId).toList();
    switch (_filter) {
      case LibraryFilter.all:
        break;
      case LibraryFilter.images:
        list = list.where((i) => i.isVisual).toList();
        break;
      case LibraryFilter.documents:
        list = list.where((i) => !i.isVisual).toList();
        break;
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((i) => i.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final items = _filtered;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(isWide),
            const SizedBox(height: 14),
            _filterTabs(),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _ink))
                  : items.isEmpty
                      ? _emptyState()
                      : _list(items, isWide),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(bool isWide) {
    final backButton = IconButton(
      icon: const Icon(Icons.arrow_back, size: 20, color: _ink),
      tooltip: 'Kembali',
      onPressed: () => Navigator.of(context).maybePop(),
    );
    final title = Text(widget.folderName ?? 'Library',
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _ink));

    if (isWide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 20, 0),
        child: Row(
          children: [
            backButton,
            const SizedBox(width: 4),
            title,
            const Spacer(),
            SizedBox(width: 260, child: _searchBar()),
            const SizedBox(width: 12),
            _newButton(isWide),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              backButton,
              const SizedBox(width: 2),
              Expanded(child: title),
              _newButton(isWide),
            ],
          ),
          const SizedBox(height: 10),
          _searchBar(),
        ],
      ),
    );
  }

  Widget _searchBar() => Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: _pillBg, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.search, size: 17, color: _inkMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 13.5, color: _ink),
                decoration: const InputDecoration(
                  hintText: 'Search',
                  hintStyle: TextStyle(color: _inkMuted),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      );

  // ---- Tombol "New ▾" + dropdown ----

  Widget _newButton(bool isWide) {
    final screenWidth = MediaQuery.of(context).size.width;
    final menuWidth = isWide ? 240.0 : (screenWidth - 32).clamp(200.0, screenWidth);

    return Theme(
      data: Theme.of(context).copyWith(
        hoverColor: const Color(0xFF3A3A3A),
        dividerColor: const Color(0xFF4A4A4A),
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFF2A2A2A),
          menuPadding: EdgeInsets.all(8),
        ),
      ),
      child: PopupMenuButton<String>(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        constraints: BoxConstraints(minWidth: 200, maxWidth: menuWidth),
        onSelected: _handleNewMenuSelected,
        itemBuilder: (context) => [
          _menuItem('note', '📝', 'New Note'),
          _menuItem('document', '📄', 'New Document'),
          _menuItem('spreadsheet', '📊', 'New Spreadsheet'),
          _menuItem('folder', '📁', 'New Folder'),
          _menuItem('upload', '⬆️', 'Upload Files'),
          const PopupMenuDivider(height: 9),
          _menuItem('drive', '📂', 'Connect Google Drive'),
        ],
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(999)),
          alignment: Alignment.center,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('New', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black)),
              SizedBox(width: 4),
              Icon(Icons.expand_more, size: 16, color: Colors.black),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, String emoji, String label) => PopupMenuItem<String>(
        value: value,
        height: 40,
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 14, color: _ink)),
          ],
        ),
      );

  void _handleNewMenuSelected(String value) {
    switch (value) {
      case 'note':
        _createTextItem('note', 'Untitled Note');
        break;
      case 'document':
        _createTextItem('document', 'Untitled Document');
        break;
      case 'spreadsheet':
        _createTextItem('spreadsheet', 'Untitled Spreadsheet');
        break;
      case 'folder':
        _createFolderDialog();
        break;
      case 'upload':
        _uploadFiles();
        break;
      case 'drive':
        _showComingSoon('Connect Google Drive');
        break;
    }
  }

  Future<void> _createTextItem(String type, String baseName) async {
    // Minta nama dulu (ala New Folder) — kalau kosong pakai nama default.
    final name = await _askNameDialog(baseName, 'Nama ${_typeLabel(type)}');
    if (name == null) return; // Batal
    await _addCustomItem(
      id: 'lib_${DateTime.now().millisecondsSinceEpoch}',
      name: name.isEmpty ? baseName : name,
      type: type,
      size: '0 KB',
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'note':
        return 'catatan';
      case 'document':
        return 'dokumen';
      case 'spreadsheet':
        return 'spreadsheet';
      default:
        return 'file';
    }
  }

  /// Dialog input nama (dipakai New Note/Document/Spreadsheet & rename).
  /// Return null jika batal, string (mungkin kosong) jika OK.
  Future<String?> _askNameDialog(String initial, String title) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(title, style: const TextStyle(color: _ink, fontSize: 15.5)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: _ink, fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'Nama',
            hintStyle: const TextStyle(color: _inkMuted),
            filled: true,
            fillColor: const Color(0xFF262626),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal', style: TextStyle(color: _inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Simpan', style: TextStyle(color: _ink)),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _createFolderDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Folder baru', style: TextStyle(color: _ink, fontSize: 15.5)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: _ink, fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'Nama folder',
            hintStyle: const TextStyle(color: _inkMuted),
            filled: true,
            fillColor: const Color(0xFF262626),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Batal', style: TextStyle(color: _inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Buat', style: TextStyle(color: _ink)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await _addCustomItem(
      id: 'lib_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      type: 'folder',
      size: '—',
    );
  }

  Future<void> _uploadFiles() async {
    final api = widget.api;
    if (api == null || !api.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login dulu untuk upload file.')),
      );
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true, withData: true);
      if (result == null || result.files.isEmpty) return;
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File "${file.name}" gagal dibaca (kosong) — coba pilih ulang file ini.')),
          );
          continue;
        }
        // Upload beneran ke server → dapatkan URL publik.
        final up = await api.uploadFile(name: file.name, bytes: bytes);
        final url = (up['url'] ?? '').toString();
        final sizeLabel = _formatBytes(file.size);
        await _addCustomItem(
          id: 'lib_${DateTime.now().millisecondsSinceEpoch}_${file.name}',
          name: file.name,
          type: 'upload',
          size: sizeLabel,
          content: url, // simpan URL sebagai referensi
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File berhasil diupload ke server.')),
      );
    } catch (e) {
      debugPrint('Upload file gagal: $e');
      if (!mounted) return;
      final raw = e.toString();
      String friendly;
      if (raw.contains('file_kosong')) {
        friendly = 'File gagal diupload (kosong) — coba pilih ulang file yang berbeda atau refresh halaman lalu coba lagi.';
      } else {
        // Backend kadang balas body JSON mentah (mis. "Upload gagal (400):
        // {"error":"..."}") — coba ambil pesan bersihnya dulu, jangan
        // tampilkan JSON mentah itu ke user.
        String? cleanMessage;
        final braceIndex = raw.indexOf('{');
        if (braceIndex != -1) {
          try {
            final decoded = jsonDecode(raw.substring(braceIndex));
            if (decoded is Map) {
              final msg = (decoded['message'] ?? decoded['error'] ?? decoded['detail'])?.toString().trim();
              if (msg != null && msg.isNotEmpty) cleanMessage = msg;
            }
          } catch (_) {
            // Bukan JSON valid — pakai fallback generik di bawah.
          }
        }
        friendly = cleanMessage != null
            ? 'Gagal upload file: $cleanMessage'
            : 'Gagal upload file. Coba lagi beberapa saat lagi.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendly)),
      );
    }
  }

  void _showComingSoon(String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(feature, style: const TextStyle(color: _ink, fontSize: 15.5)),
        content: const Text('Fitur segera hadir.', style: TextStyle(color: _inkMuted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Oke', style: TextStyle(color: _ink)),
          ),
        ],
      ),
    );
  }

  Widget _filterTabs() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _filterPill('All', LibraryFilter.all),
            const SizedBox(width: 8),
            _filterPill('Images', LibraryFilter.images),
            const SizedBox(width: 8),
            _filterPill('Documents', LibraryFilter.documents),
          ],
        ),
      );

  Widget _filterPill(String label, LibraryFilter value) {
    final active = _filter == value;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: active ? _ink : _pillBg, borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? Colors.black : _ink)),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_outlined, size: 64, color: _inkMuted),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.folderId != null
                    ? 'Folder ini masih kosong.'
                    : 'Belum ada file. Buat gambar/video/suara di chat dulu.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: _inkMuted),
              ),
            ),
          ],
        ),
      );

  Widget _list(List<LibraryItem> items, bool isWide) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              const SizedBox(width: 48 + 12),
              const Expanded(child: Text('Name', style: TextStyle(fontSize: 12, color: _inkMuted))),
              if (isWide)
                const SizedBox(
                  width: 90,
                  child: Text('Modified', style: TextStyle(fontSize: 12, color: _inkMuted)),
                ),
              const SizedBox(
                width: 70,
                child: Text('Size', textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: _inkMuted)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: _divider, indent: 16, endIndent: 16),
            itemBuilder: (context, i) => _row(items[i], isWide),
          ),
        ),
      ],
    );
  }

  Widget _row(LibraryItem item, bool isWide) {
    final content = InkWell(
      onTap: () => _openItem(item),
      onLongPress: item.isCustom
          ? () => _showItemMenu(item)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _thumbnail(item),
            const SizedBox(width: 12),
            Expanded(
              child: Text(item.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: _ink)),
            ),
            if (isWide)
              SizedBox(
                width: 90,
                child: Text(_fmtDate(item.modified), style: const TextStyle(fontSize: 12, color: _inkMuted)),
              ),
            SizedBox(
              width: 70,
              child:
                  Text(item.size, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12, color: _inkMuted)),
            ),
            if (item.isCustom)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18, color: _inkMuted),
                padding: EdgeInsets.zero,
                color: const Color(0xFF2A2A2A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  if (v == 'rename') _renameCustomItem(item.id!);
                  if (v == 'delete') _removeCustomItem(item.id!);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', height: 40, child: Text('Ubah nama', style: TextStyle(fontSize: 13.5, color: Colors.white))),
                  PopupMenuItem(value: 'delete', height: 40, child: Text('Hapus', style: TextStyle(fontSize: 13.5, color: Color(0xFFFF6B6B)))),
                ],
              ),
          ],
        ),
      ),
    );
    if (item.id != null && _fadeInIds.contains(item.id)) {
      return _FadeIn(key: ValueKey('fade_${item.id}'), child: content);
    }
    return KeyedSubtree(key: ValueKey(item.id ?? '${item.type}_${item.url}_${item.modified.millisecondsSinceEpoch}'), child: content);
  }

  void _showItemMenu(LibraryItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.white),
              title: const Text('Ubah nama', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.of(context).pop(); _renameCustomItem(item.id!); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFFF6B6B)),
              title: const Text('Hapus', style: TextStyle(color: Color(0xFFFF6B6B))),
              onTap: () { Navigator.of(context).pop(); _removeCustomItem(item.id!); },
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(LibraryItem item) {
    if (item.type == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          item.url,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _iconBox(Icons.broken_image_outlined, _boxGrey),
        ),
      );
    }
    if (item.type == 'video') return _iconBox(Icons.movie_outlined, _boxGrey);
    if (item.type == 'audio') return _iconBox(Icons.music_note, _boxBlue);
    if (item.type == 'note') return _iconBox(Icons.sticky_note_2_outlined, _boxGrey);
    if (item.type == 'document') return _iconBox(Icons.description_outlined, _boxGrey);
    if (item.type == 'spreadsheet') return _iconBox(Icons.grid_on_outlined, const Color(0xFF2E7D32));
    if (item.type == 'folder') return _iconBox(Icons.folder_outlined, const Color(0xFFF5B93D));
    if (item.type == 'upload') return _iconBox(Icons.upload_file_outlined, _boxGrey);
    return _iconBox(Icons.insert_drive_file_outlined, _boxGrey);
  }

  Widget _iconBox(IconData icon, Color color) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: _ink),
      );

  void _openItem(LibraryItem item) {
    switch (item.type) {
      case 'image':
        _openImage(item);
        break;
      case 'audio':
        _openAudio(item);
        break;
      case 'video':
        _openInfo(item, 'Video tersimpan di server. Link untuk menonton:');
        break;
      case 'note':
      case 'document':
      case 'spreadsheet':
        _openEditor(item);
        break;
      case 'folder':
        _openFolder(item);
        break;
      case 'upload':
        // Upload kini punya URL publik di content → buka/tampilkan link-nya.
        final url = (item.content != null && item.content!.isNotEmpty) ? item.content! : item.url;
        if (url.isNotEmpty) {
          _openInfo(item, 'File terupload. Link unduh:');
        } else {
          _openInfo(item, 'File yang di-upload (belum ada link):');
        }
        break;
      default:
        _openInfo(item, 'File tersimpan di server:');
    }
  }

  Future<void> _openEditor(LibraryItem item) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _LibraryEditorScreen(
        name: item.name,
        type: item.type,
        content: item.content ?? '',
        onSave: (newContent) => _saveItemContent(item.id!, newContent),
      ),
    ));
  }

  void _openFolder(LibraryItem item) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LibraryScreen(folderId: item.id, folderName: item.name, api: widget.api),
    ));
  }

  void _openImage(LibraryItem item) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                item.url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 240,
                  height: 240,
                  color: _boxGrey,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, size: 32, color: _inkMuted),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: _ink),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  void _openAudio(LibraryItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _ink)),
              AudioMessagePlayer(url: item.url),
            ],
          ),
        ),
      ),
    );
  }

  void _openInfo(LibraryItem item, String label) {
    final displayUrl = item.url.isNotEmpty
        ? item.url
        : ((item.content != null && item.content!.startsWith('http')) ? item.content! : item.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(item.name, style: const TextStyle(color: _ink, fontSize: 15.5)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: _inkMuted, fontSize: 12.5)),
              const SizedBox(height: 8),
              SelectableText(displayUrl,
                  style: const TextStyle(color: _ink, fontSize: 12.8)),
            ],
          ),
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
}

/// Fade-in 200ms sekali jalan — dipakai buat item Library yang baru saja
/// dibuat lewat tombol "New ▾", supaya kemunculannya di list terasa halus.
class _FadeIn extends StatefulWidget {
  final Widget child;
  const _FadeIn({super.key, required this.child});

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 200))..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _controller, child: widget.child);
}

/// Editor sederhana untuk note/document/spreadsheet Library — satu TextField
/// multiline, tombol Save di AppBar. Spreadsheet diedit sebagai teks CSV.
class _LibraryEditorScreen extends StatefulWidget {
  final String name;
  final String type;
  final String content;
  final ValueChanged<String> onSave;

  const _LibraryEditorScreen({
    required this.name,
    required this.type,
    required this.content,
    required this.onSave,
  });

  @override
  State<_LibraryEditorScreen> createState() => _LibraryEditorScreenState();
}

class _LibraryEditorScreenState extends State<_LibraryEditorScreen> {
  late final TextEditingController _controller = TextEditingController(text: widget.content);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    widget.onSave(_controller.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isSpreadsheet = widget.type == 'spreadsheet';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          tooltip: 'Kembali',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(widget.name, style: const TextStyle(color: Colors.white, fontSize: 16), overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontFamily: isSpreadsheet ? 'monospace' : null,
            height: 1.4,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: isSpreadsheet ? 'kolom1,kolom2,kolom3\nnilai1,nilai2,nilai3' : 'Tulis di sini...',
            hintStyle: const TextStyle(color: Color(0xFF6E6E6E)),
          ),
        ),
      ),
    );
  }
}
