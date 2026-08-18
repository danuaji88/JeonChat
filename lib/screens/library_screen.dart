import 'package:flutter/material.dart';

import '../models/message.dart';
import '../services/chat_history_service.dart';
import '../widgets/audio_message_player.dart';

enum LibraryFilter { all, images, documents }

/// Satu entri media/file yang pernah muncul di sebuah percakapan —
/// dikumpulkan dari imageUrl/videoUrl/audioUrl/filePath tiap ChatMessage.
class LibraryItem {
  final String name;
  final String type; // 'image' | 'video' | 'audio' | 'doc'
  final String url;
  final DateTime modified;
  final String size;

  const LibraryItem({
    required this.name,
    required this.type,
    required this.url,
    required this.modified,
    required this.size,
  });

  bool get isVisual => type == 'image' || type == 'video';
}

/// Halaman Library ala ChatGPT — daftar semua gambar/video/audio/file yang
/// pernah di-generate atau dikirim di seluruh percakapan (ChatHistoryService).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

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
    items.sort((a, b) => b.modified.compareTo(a.modified));
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  String _fmtDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

  List<LibraryItem> get _filtered {
    var list = _items;
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
    const title = Text('Library', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _ink));

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
            _newButton(),
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
              const Expanded(child: title),
              _newButton(),
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

  Widget _newButton() => PopupMenuButton<String>(
        color: _pillBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (_) => Navigator.of(context).maybePop(),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'chat', child: Text('New Chat', style: TextStyle(color: _ink))),
          PopupMenuItem(value: 'image', child: Text('New Image', style: TextStyle(color: _ink))),
          PopupMenuItem(value: 'audio', child: Text('New Audio', style: TextStyle(color: _ink))),
        ],
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(999)),
          alignment: Alignment.center,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('New', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.black)),
              SizedBox(width: 4),
              Icon(Icons.expand_more, size: 16, color: Colors.black),
            ],
          ),
        ),
      );

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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text('Belum ada file. Buat gambar/video/suara di chat dulu.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: _inkMuted)),
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

  Widget _row(LibraryItem item, bool isWide) => InkWell(
        onTap: () => _openItem(item),
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
            ],
          ),
        ),
      );

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
      default:
        _openInfo(item, 'File tersimpan di server:');
    }
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
              SelectableText(item.url, style: const TextStyle(color: _ink, fontSize: 12.8)),
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
