import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/profile_service.dart';
import 'profile_menu_sheet.dart';

/// Sidebar kiri ala ChatGPT: header, "New chat", nav statis, daftar
/// percakapan (Pinned/Chats) dengan rename/pin/delete, dan footer profil.
class SidebarChatGPT extends StatefulWidget {
  final ApiService api;
  final ProfileService profile;
  final List<Map<String, dynamic>> conversations;
  final String? activeConversationId;
  final VoidCallback onNewChat;
  final ValueChanged<String> onSelectConversation;
  final void Function(String id, String title) onRenameConversation;
  final void Function(String id, bool pinned) onTogglePin;
  final ValueChanged<String> onDeleteConversation;
  final VoidCallback onClose;
  final VoidCallback? onClearHistory;
  final VoidCallback? onProfileChanged;

  const SidebarChatGPT({
    super.key,
    required this.api,
    required this.profile,
    required this.conversations,
    required this.activeConversationId,
    required this.onNewChat,
    required this.onSelectConversation,
    required this.onRenameConversation,
    required this.onTogglePin,
    required this.onDeleteConversation,
    required this.onClose,
    this.onClearHistory,
    this.onProfileChanged,
  });

  @override
  State<SidebarChatGPT> createState() => _SidebarChatGPTState();
}

class _SidebarChatGPTState extends State<SidebarChatGPT> {
  static const _bg = Color(0xFF000000);
  static const _ink = Colors.white;
  static const _inkMuted = Colors.white70;
  static const _inkFaint = Colors.white38;
  static const _activeBg = Color(0xFF2D2D2D);
  static const _hoverBg = Color(0xFF1E1E1E);
  static const _borderColor = Color(0xFF3A3A3A);

  bool _searchOpen = false;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.conversations
        : widget.conversations
            .where((c) => (c['title'] as String? ?? '').toLowerCase().contains(query))
            .toList();
    final pinned = filtered.where((c) => c['pinned'] == true).toList();
    final others = filtered.where((c) => c['pinned'] != true).toList();

    return Container(
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          if (_searchOpen) _searchField(),
          _newChatButton(),
          const SizedBox(height: 4),
          _navItem(Icons.auto_stories_outlined, 'Library'),
          _navItem(Icons.schedule_outlined, 'Scheduled'),
          _navItem(Icons.alternate_email, 'Plugins'),
          _navItem(Icons.cloud_outlined, 'Codex'),
          _navItem(Icons.more_horiz, 'More'),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (pinned.isNotEmpty) ...[
                  _sectionLabel('Pinned'),
                  ...pinned.map(_conversationRow),
                ],
                _sectionLabel('Chats'),
                if (others.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                    child: Text(
                      query.isEmpty ? 'Belum ada percakapan' : 'Tidak ditemukan',
                      style: const TextStyle(fontSize: 11.5, color: _inkFaint),
                    ),
                  )
                else
                  ...others.map(_conversationRow),
              ],
            ),
          ),
          const Divider(color: Color(0xFF262626), height: 1),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 4),
        child: Row(
          children: [
            const Expanded(
              child: Text('JeonChat',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
            ),
            IconButton(
              icon: Icon(_searchOpen ? Icons.close : Icons.search, size: 19, color: _inkMuted),
              tooltip: 'Cari percakapan',
              onPressed: () => setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  _searchController.clear();
                  _query = '';
                }
              }),
            ),
            IconButton(
              icon: const Icon(Icons.menu_open, size: 19, color: _inkMuted),
              tooltip: 'Tutup sidebar',
              onPressed: widget.onClose,
            ),
          ],
        ),
      );

  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 13, color: _ink),
          decoration: InputDecoration(
            hintText: 'Cari percakapan…',
            hintStyle: const TextStyle(color: _inkFaint),
            filled: true,
            fillColor: const Color(0xFF171717),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  Widget _newChatButton() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: _hoverBg,
          onTap: widget.onNewChat,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: _borderColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.edit_outlined, size: 16, color: _ink),
                SizedBox(width: 10),
                Text('New chat', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: _ink)),
              ],
            ),
          ),
        ),
      );

  Widget _navItem(IconData icon, String label) => InkWell(
        onTap: () {},
        hoverColor: _hoverBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 17, color: _inkMuted),
                const SizedBox(width: 10),
                Text(label, style: const TextStyle(fontSize: 14, color: _ink)),
              ],
            ),
          ),
        ),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Text(text, style: const TextStyle(fontSize: 11, color: _inkFaint, fontWeight: FontWeight.w600)),
      );

  Widget _conversationRow(Map<String, dynamic> conv) {
    final id = conv['id'] as String;
    final rawTitle = (conv['title'] as String?)?.trim();
    final title = (rawTitle == null || rawTitle.isEmpty) ? 'Percakapan Baru' : rawTitle;
    final pinned = conv['pinned'] == true;
    final active = id == widget.activeConversationId;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: active ? _activeBg : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: active ? _activeBg : _hoverBg,
        onTap: () {
          widget.onSelectConversation(id);
          if (MediaQuery.of(context).size.width < 600) Navigator.of(context).maybePop();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(pinned ? Icons.push_pin : Icons.chat_bubble_outline, size: 14, color: _inkMuted),
              const SizedBox(width: 9),
              Expanded(
                child: Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _ink)),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _openConversationMenu(conv),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.more_vert, size: 16, color: _inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openConversationMenu(Map<String, dynamic> conv) async {
    final id = conv['id'] as String;
    final pinned = conv['pinned'] == true;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: _ink, size: 19),
              title: const Text('Rename', style: TextStyle(color: _ink, fontSize: 13.6)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _promptRename(conv);
              },
            ),
            ListTile(
              leading: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, color: _ink, size: 19),
              title: Text(pinned ? 'Unpin' : 'Pin', style: const TextStyle(color: _ink, fontSize: 13.6)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onTogglePin(id, !pinned);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 19),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13.6)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _confirmDelete(conv);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _promptRename(Map<String, dynamic> conv) async {
    final controller = TextEditingController(text: conv['title'] as String? ?? '');
    final newTitle = await showModalBottomSheet<String>(
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
            const Text('Ganti nama chat', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _ink)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(fontSize: 13.4, color: _ink),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF262626),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onSubmitted: (v) => Navigator.of(sheetContext).pop(v),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.of(sheetContext).pop(controller.text.trim()),
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
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      widget.onRenameConversation(conv['id'] as String, newTitle.trim());
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> conv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Hapus percakapan ini?', style: TextStyle(color: _ink, fontSize: 15.5)),
        content: Text('"${conv['title'] ?? 'Percakapan ini'}" akan dihapus dan tidak bisa dikembalikan.',
            style: const TextStyle(color: _inkMuted, fontSize: 12.8)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal', style: TextStyle(color: _inkMuted))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed == true) widget.onDeleteConversation(conv['id'] as String);
  }

  Widget _footer() {
    return InkWell(
      hoverColor: _hoverBg,
      onTap: () => showProfileMenu(
        context,
        api: widget.api,
        profile: widget.profile,
        onClearHistory: widget.onClearHistory,
        onProfileChanged: widget.onProfileChanged,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2D2D2D),
                border: Border.all(color: _borderColor),
              ),
              alignment: Alignment.center,
              child: Text(widget.profile.avatarEmoji, style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.profile.displayName,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _ink)),
                  Text(widget.api.isGuest ? 'Tamu · Paket Gratis' : 'Owner · Full Access',
                      style: const TextStyle(fontSize: 10.5, color: _inkFaint)),
                ],
              ),
            ),
            const Icon(Icons.unfold_more_rounded, size: 16, color: _inkFaint),
          ],
        ),
      ),
    );
  }
}
