import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../services/api_service.dart';
import '../services/plugin_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import 'notification_badge.dart';
import 'profile_menu_sheet.dart';

/// Sidebar kiri JeonChat: header, "New chat", nav statis, mode Chat/Work,
/// daftar percakapan (Pinned/Chats) dengan rename/pin/delete, dan footer profil.
class JeonChatSidebar extends StatefulWidget {
  final ApiService api;
  final ProfileService profile;
  final List<Map<String, dynamic>> conversations;
  final String? activeConversationId;
  final VoidCallback onNewChat;
  final ValueChanged<String> onSelectConversation;
  final void Function(String id, String title) onRenameConversation;
  final void Function(String id, bool pinned) onTogglePin;
  final void Function(String id, bool archived) onToggleArchive;
  final ValueChanged<String> onDeleteConversation;
  final void Function(String conversationId, String? projectId) onMoveToProject;
  final VoidCallback onClose;
  final VoidCallback? onClearHistory;
  final VoidCallback? onProfileChanged;
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenPlugins;
  final VoidCallback? onOpenScheduled;
  final VoidCallback? onOpenMore;

  /// Nav "Buat Gambar"/"Buat Video" — tap langsung minta prompt lewat
  /// dialog kecil (dikelola chat_screen.dart), lalu jalan lewat pipeline
  /// generate yang sudah ada (_generateImageDirect/_generateVideoDirect,
  /// termasuk dialog pilih tier).
  final VoidCallback? onGenerateImage;
  final VoidCallback? onGenerateVideo;

  /// Buka TasksScreen (fase 3.3, "Tugas Terjadwal"). Null = entri "Tugas"
  /// tetap tampil tapi tap-nya no-op.
  final VoidCallback? onOpenTasks;

  /// Jumlah notifikasi belum dibaca (/notifications, di-poll tiap 30 detik
  /// oleh chat_screen.dart lewat _pollNotifications) — badge lingkaran
  /// merah kecil di samping entri "Tugas". 0 = badge disembunyikan.
  final int unreadCount;

  // ---- My Plugins ----
  final List<InstalledPlugin> installedPlugins;
  final ValueChanged<String>? onSelectPlugin;
  final ValueChanged<String>? onDeactivatePlugin;

  /// GET /quota mentah — {plan, credits: {total, used, remaining,
  /// cost_per_feature}}. Null = belum dimuat/user belum login (badge disembunyikan).
  final Map<String, dynamic>? quota;

  /// Jumlah "Skill Saya" (/skill) aktif milik user — badge "🧠 N" di footer
  /// profil, cuma tampil kalau > 0. Tap badge buka SkillListScreen.
  final int userSkillCount;
  final VoidCallback? onOpenUserSkills;

  // ---- Projects ----
  final List<Map<String, dynamic>> projects;
  final String? activeProjectId;
  final ValueChanged<String?> onSelectProject;

  /// Tap baris project (fase 2.2) — buka ProjectDetailScreen (chats/files/
  /// instruksi project). Beda dari [onSelectProject] yang cuma filter daftar
  /// chat di sidebar ini (masih dipakai lewat menu "Project home").
  final ValueChanged<String> onOpenProject;
  final Future<void> Function(String name, String color, String icon, String instructions) onCreateProject;
  final void Function(String id, String name) onRenameProject;
  final Future<void> Function(String id, {required String name, required String description, required String color, required String icon}) onUpdateProjectSettings;
  final void Function(String id, bool pinned) onPinProject;
  final void Function(String id, bool archived) onArchiveProject;
  final ValueChanged<String> onDeleteProject;

  const JeonChatSidebar({
    super.key,
    required this.api,
    required this.profile,
    required this.conversations,
    required this.activeConversationId,
    required this.onNewChat,
    required this.onSelectConversation,
    required this.onRenameConversation,
    required this.onTogglePin,
    required this.onToggleArchive,
    required this.onDeleteConversation,
    required this.onMoveToProject,
    required this.onClose,
    required this.projects,
    required this.activeProjectId,
    required this.onSelectProject,
    required this.onOpenProject,
    required this.onCreateProject,
    required this.onRenameProject,
    required this.onUpdateProjectSettings,
    required this.onPinProject,
    required this.onArchiveProject,
    required this.onDeleteProject,
    this.onClearHistory,
    this.onProfileChanged,
    this.onOpenLibrary,
    this.onOpenPlugins,
    this.onOpenScheduled,
    this.onOpenMore,
    this.onGenerateImage,
    this.onGenerateVideo,
    this.onOpenTasks,
    this.unreadCount = 0,
    this.installedPlugins = const [],
    this.onSelectPlugin,
    this.onDeactivatePlugin,
    this.quota,
    this.userSkillCount = 0,
    this.onOpenUserSkills,
  });

  @override
  State<JeonChatSidebar> createState() => _JeonChatSidebarState();
}

class _JeonChatSidebarState extends State<JeonChatSidebar> {
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
  bool _workMode = false;
  bool _projectsExpanded = true;
  bool _archiveExpanded = false;

  static const _projectColors = <String>[
    '#58A6FF', '#3FB950', '#DB6D28', '#DB61A2', '#A371F7', '#39C5CF', '#F85149', '#D29922',
  ];
  static const _projectIcons = <String, IconData>{
    'folder': Icons.folder,
    'work': Icons.work_outline,
    'star': Icons.star_outline,
    'science': Icons.science_outlined,
    'code': Icons.code,
    'palette': Icons.palette_outlined,
    'rocket': Icons.rocket_launch_outlined,
    'book': Icons.menu_book_outlined,
  };

  Color _colorFromHex(String hex) => Color(int.parse(hex.replaceFirst('#', '0xFF')));
  IconData _iconFromKey(String key) => _projectIcons[key] ?? Icons.folder;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    var filtered = query.isEmpty
        ? widget.conversations
        : widget.conversations
            .where((c) => (c['title'] as String? ?? '').toLowerCase().contains(query))
            .toList();
    if (widget.activeProjectId != null) {
      filtered = filtered.where((c) => c['projectId'] == widget.activeProjectId).toList();
    }
    final archivedList = filtered.where((c) => c['archived'] == true).toList();
    final visible = filtered.where((c) => c['archived'] != true).toList();
    final pinned = visible.where((c) => c['pinned'] == true).toList();
    final others = visible.where((c) => c['pinned'] != true).toList();

    return Container(
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          if (_searchOpen) _searchField(),
          _newChatButton(),
          const SizedBox(height: 6),
          _modeToggle(),
          const SizedBox(height: 6),
          _navItem(Icons.auto_stories_outlined, 'Library', onTap: widget.onOpenLibrary, locked: !widget.api.isLoggedIn),
          _navItem(
            Icons.schedule_outlined,
            'Tugas',
            onTap: widget.onOpenTasks,
            locked: !widget.api.isLoggedIn,
            trailing: widget.unreadCount > 0
                ? Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: NotificationBadge(count: widget.unreadCount, iconSize: 15),
                  )
                : null,
          ),
          _navItem(Icons.extension_outlined, 'Plugins', onTap: widget.onOpenPlugins, locked: !widget.api.isLoggedIn),
          _navItem(Icons.image_outlined, 'Buat Gambar', onTap: widget.onGenerateImage, locked: !widget.api.isLoggedIn),
          _navItem(Icons.movie_outlined, 'Buat Video', onTap: widget.onGenerateVideo, locked: !widget.api.isLoggedIn),
          _navItem(Icons.more_horiz_rounded, 'More', onTap: widget.onOpenMore, locked: !widget.api.isLoggedIn),
          if (widget.installedPlugins.isNotEmpty) ...[
            const SizedBox(height: 6),
            _myPluginsSection(),
          ],
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _projectsSection(),
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
                if (archivedList.isNotEmpty) _archivedSection(archivedList),
              ],
            ),
          ),
          const Divider(color: Color(0xFF262626), height: 1),
          _creditBadge(),
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
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
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
                Text('New Chat', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: _ink)),
              ],
            ),
          ),
        ),
      );

  /// Toggle Chat/Work — murni visual untuk sekarang; belum ada perbedaan
  /// endpoint/perilaku yang didefinisikan untuk mode "Work".
  Widget _modeToggle() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _borderColor),
          ),
          child: Row(
            children: [
              _modeSegment('Chat', !_workMode),
              _modeSegment('Work', _workMode),
            ],
          ),
        ),
      );

  Widget _modeSegment(String label, bool active) => Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _workMode = label == 'Work'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: active ? _activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    color: active ? _ink : _inkFaint)),
          ),
        ),
      );

  Widget _navItem(IconData icon, String label, {VoidCallback? onTap, bool locked = false, Widget? trailing}) =>
      InkWell(
        onTap: onTap ?? () {},
        hoverColor: _hoverBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 17, color: _inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: _ink)),
                ),
                if (trailing != null) trailing,
                if (locked) const Icon(Icons.lock_outline, size: 14, color: _inkFaint),
              ],
            ),
          ),
        ),
      );

  Widget _myPluginsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('My Plugins'),
          ...widget.installedPlugins.map(_pluginRow),
        ],
      );

  Widget _pluginRow(InstalledPlugin plugin) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: _hoverBg,
          onTap: () => widget.onSelectPlugin?.call(plugin.title),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Text(plugin.emoji, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(plugin.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _ink)),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _openPluginMenu(plugin),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.more_horiz, size: 16, color: _inkMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<void> _openPluginMenu(InstalledPlugin plugin) async {
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
            const SizedBox(height: 6),
            _menuTile(Icons.info_outline, 'Lihat detail', onTap: () {
              Navigator.of(sheetContext).pop();
              _showPluginDetail(plugin);
            }),
            _menuTile(Icons.power_settings_new, 'Nonaktifkan', color: _deleteRed, onTap: () {
              Navigator.of(sheetContext).pop();
              widget.onDeactivatePlugin?.call(plugin.id);
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showPluginDetail(InstalledPlugin plugin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(plugin.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Flexible(child: Text(plugin.title, style: const TextStyle(color: _ink, fontSize: 15.5))),
          ],
        ),
        content: const Text('Plugin ini aktif dan bisa dipakai JeonAI di percakapanmu.',
            style: TextStyle(color: _inkMuted, fontSize: 12.8)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup', style: TextStyle(color: _inkMuted)),
          ),
        ],
      ),
    );
  }

  Widget _projectsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _projectsExpanded = !_projectsExpanded),
                  hoverColor: _hoverBg,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
                    child: Row(
                      children: [
                        Icon(_projectsExpanded ? Icons.expand_more : Icons.chevron_right,
                            size: 18, color: _inkFaint),
                        const SizedBox(width: 4),
                        const Text('Projects',
                            style: TextStyle(fontSize: 11, color: _inkFaint, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _createProjectDialog,
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(4, 10, 12, 6),
                  child: Icon(Icons.add, size: 16, color: _inkFaint),
                ),
              ),
            ],
          ),
          if (_projectsExpanded)
            widget.projects.isEmpty
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('Belum ada project', style: TextStyle(fontSize: 11.5, color: _inkFaint)),
                  )
                : Column(children: widget.projects.map(_projectRow).toList()),
        ],
      );

  Widget _projectRow(Map<String, dynamic> project) {
    final id = project['id'] as String;
    final name = (project['name'] as String?)?.trim().isNotEmpty == true ? project['name'] as String : 'Project';
    final color = _colorFromHex(project['color'] as String? ?? '#58A6FF');
    final icon = _iconFromKey(project['icon'] as String? ?? 'folder');
    final active = id == widget.activeProjectId;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: active ? _activeBg : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: active ? _activeBg : _hoverBg,
        onTap: () => widget.onOpenProject(id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 9),
              Expanded(
                child: Text(name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _ink)),
              ),
              if (project['pinned'] == true) ...[
                const Icon(Icons.push_pin, size: 12, color: _inkFaint),
                const SizedBox(width: 4),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _openProjectMenu(project),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.more_horiz, size: 16, color: _inkMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openProjectMenu(Map<String, dynamic> project) async {
    final id = project['id'] as String;
    final pinned = project['pinned'] == true;
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
            const SizedBox(height: 6),
            // Group 1: Share project, Rename project, Project settings, Project home
            _menuTile(Icons.ios_share_outlined, 'Share project', onTap: () {
              Navigator.of(sheetContext).pop();
              _shareProject(project);
            }),
            _menuTile(Icons.edit_outlined, 'Rename project', onTap: () async {
              Navigator.of(sheetContext).pop();
              await _promptRenameProject(project);
            }),
            _menuTile(Icons.tune_outlined, 'Project settings', onTap: () async {
              Navigator.of(sheetContext).pop();
              await _openProjectSettingsSheet(project);
            }),
            _menuTile(Icons.home_outlined, 'Project home', onTap: () {
              Navigator.of(sheetContext).pop();
              widget.onSelectProject(id);
            }),
            const Divider(color: Color(0xFF262626), height: 16, indent: 16, endIndent: 16),
            // Group 2: Pin project, Delete project (merah)
            _menuTile(pinned ? Icons.push_pin : Icons.push_pin_outlined, pinned ? 'Unpin project' : 'Pin project',
                onTap: () {
              Navigator.of(sheetContext).pop();
              widget.onPinProject(id, !pinned);
            }),
            _menuTile(Icons.delete_outline, 'Delete project', color: _deleteRed, onTap: () async {
              Navigator.of(sheetContext).pop();
              await _confirmDeleteProject(project);
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// "Share project" — sama seperti share chat: belum ada backend
  /// sharing/deep-link, jadi yang benar-benar terjadi adalah info project
  /// (nama + deskripsi) disalin ke clipboard, bukan link URL palsu.
  Future<void> _shareProject(Map<String, dynamic> project) async {
    final name = (project['name'] as String?)?.trim().isNotEmpty == true ? project['name'] as String : 'Project';
    final description = (project['description'] as String?)?.trim() ?? '';
    final text = description.isEmpty ? 'JeonChat Project — $name' : 'JeonChat Project — $name\n\n$description';
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Info project disalin ke clipboard')),
    );
  }

  Future<void> _openProjectSettingsSheet(Map<String, dynamic> project) async {
    final id = project['id'] as String;
    final nameController = TextEditingController(text: project['name'] as String? ?? '');
    final descController = TextEditingController(text: project['description'] as String? ?? '');
    String selectedColor = project['color'] as String? ?? _projectColors.first;
    String selectedIcon = project['icon'] as String? ?? _projectIcons.keys.first;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Project settings', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _ink)),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Nama', style: TextStyle(fontSize: 11.5, color: _inkFaint, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13.4, color: _ink),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF262626),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Deskripsi', style: TextStyle(fontSize: 11.5, color: _inkFaint, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 13.4, color: _ink),
                  decoration: InputDecoration(
                    hintText: 'Opsional',
                    hintStyle: const TextStyle(color: _inkFaint),
                    filled: true,
                    fillColor: const Color(0xFF262626),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Warna', style: TextStyle(fontSize: 11.5, color: _inkFaint, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _projectColors.map((hex) {
                    final color = _colorFromHex(hex);
                    final selected = hex == selectedColor;
                    return GestureDetector(
                      onTap: () => setSheetState(() => selectedColor = hex),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: selected ? Border.all(color: _ink, width: 2) : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Ikon', style: TextStyle(fontSize: 11.5, color: _inkFaint, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _projectIcons.entries.map((entry) {
                    final selected = entry.key == selectedIcon;
                    return GestureDetector(
                      onTap: () => setSheetState(() => selectedIcon = entry.key),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: selected ? _activeBg : const Color(0xFF262626),
                          shape: BoxShape.circle,
                          border: selected ? Border.all(color: _ink, width: 1.5) : null,
                        ),
                        alignment: Alignment.center,
                        child: Icon(entry.value, size: 17, color: _ink),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
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
        ),
      ),
    );

    final name = nameController.text.trim();
    if (saved == true && name.isNotEmpty) {
      await widget.onUpdateProjectSettings(
        id,
        name: name,
        description: descController.text.trim(),
        color: selectedColor,
        icon: selectedIcon,
      );
    }
  }

  Future<void> _promptRenameProject(Map<String, dynamic> project) async {
    final controller = TextEditingController(text: project['name'] as String? ?? '');
    final newName = await showModalBottomSheet<String>(
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
            const Text('Ganti nama project', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _ink)),
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
    if (newName != null && newName.trim().isNotEmpty) {
      widget.onRenameProject(project['id'] as String, newName.trim());
    }
  }

  Future<void> _confirmDeleteProject(Map<String, dynamic> project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF171717),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Hapus project ini?', style: TextStyle(color: _ink, fontSize: 15.5)),
        content: Text(
            '"${project['name'] ?? 'Project ini'}" akan dihapus. Chat di dalamnya tidak ikut terhapus, cuma dilepas dari project.',
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
    if (confirmed == true) {
      widget.onDeleteProject(project['id'] as String);
      if (widget.activeProjectId == project['id']) widget.onSelectProject(null);
    }
  }

  Future<void> _createProjectDialog() async {
    final controller = TextEditingController();
    final instructionsController = TextEditingController();
    String selectedColor = _projectColors.first;
    String selectedIcon = _projectIcons.keys.first;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
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
              const Text('Project baru', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _ink)),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(fontSize: 13.4, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Nama project',
                  hintStyle: const TextStyle(color: _inkFaint),
                  filled: true,
                  fillColor: const Color(0xFF262626),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Instruksi (opsional)',
                    style: TextStyle(fontSize: 11.5, color: _inkFaint, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: instructionsController,
                maxLines: 3,
                style: const TextStyle(fontSize: 13.4, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Contoh: Bahasa santai, fokus penjualan',
                  hintStyle: const TextStyle(color: _inkFaint),
                  filled: true,
                  fillColor: const Color(0xFF262626),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Warna', style: TextStyle(fontSize: 11.5, color: _inkFaint, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _projectColors.map((hex) {
                  final color = _colorFromHex(hex);
                  final selected = hex == selectedColor;
                  return GestureDetector(
                    onTap: () => setSheetState(() => selectedColor = hex),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: selected ? Border.all(color: _ink, width: 2) : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Ikon', style: TextStyle(fontSize: 11.5, color: _inkFaint, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _projectIcons.entries.map((entry) {
                  final selected = entry.key == selectedIcon;
                  return GestureDetector(
                    onTap: () => setSheetState(() => selectedIcon = entry.key),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: selected ? _activeBg : const Color(0xFF262626),
                        shape: BoxShape.circle,
                        border: selected ? Border.all(color: _ink, width: 1.5) : null,
                      ),
                      alignment: Alignment.center,
                      child: Icon(entry.value, size: 17, color: _ink),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
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
                  child: const Text('Buat Project', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final name = controller.text.trim();
    if (created == true && name.isNotEmpty) {
      await widget.onCreateProject(name, selectedColor, selectedIcon, instructionsController.text.trim());
    }
  }

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
                child: Row(
                  children: [
                    // Badge cabang (fase 4.3) — percakapan yang dibuat via
                    // "Buat Cabang" ditandai ikon pohon kecil agar beda dari
                    // percakapan biasa di sidebar.
                    if (conv['branchOf'] != null) ...[
                      const Icon(Icons.account_tree_outlined, size: 12, color: JeonColors.accent),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(title,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _ink)),
                    ),
                  ],
                ),
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

  Widget _archivedSection(List<Map<String, dynamic>> archived) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _archiveExpanded = !_archiveExpanded),
            hoverColor: _hoverBg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  const Icon(Icons.archive_outlined, size: 13, color: _inkFaint),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text('ARCHIVED (${archived.length})',
                        style: const TextStyle(
                            fontSize: 11, letterSpacing: 0.4, color: _inkFaint, fontWeight: FontWeight.w600)),
                  ),
                  Icon(_archiveExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 15, color: _inkFaint),
                ],
              ),
            ),
          ),
          if (_archiveExpanded) ...archived.map(_conversationRow),
        ],
      );

  static const _deleteRed = Color(0xFFEF5350);

  Future<void> _openConversationMenu(Map<String, dynamic> conv) async {
    final id = conv['id'] as String;
    final pinned = conv['pinned'] == true;
    final archived = conv['archived'] == true;
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
            const SizedBox(height: 6),
            // Group 1: Share, Rename
            _menuTile(Icons.ios_share_outlined, 'Share', onTap: () {
              Navigator.of(sheetContext).pop();
              _shareConversation(conv);
            }),
            _menuTile(Icons.edit_outlined, 'Rename', onTap: () async {
              Navigator.of(sheetContext).pop();
              await _promptRename(conv);
            }),
            const Divider(color: Color(0xFF262626), height: 16, indent: 16, endIndent: 16),
            // Group 2: Pin chat, Archive, Delete (merah)
            _menuTile(pinned ? Icons.push_pin : Icons.push_pin_outlined, pinned ? 'Unpin chat' : 'Pin chat',
                onTap: () {
              Navigator.of(sheetContext).pop();
              widget.onTogglePin(id, !pinned);
            }),
            _menuTile(archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                archived ? 'Unarchive' : 'Archive', onTap: () {
              Navigator.of(sheetContext).pop();
              widget.onToggleArchive(id, !archived);
            }),
            _menuTile(Icons.delete_outline, 'Delete', color: _deleteRed, onTap: () async {
              Navigator.of(sheetContext).pop();
              await _confirmDelete(conv);
            }),
            const Divider(color: Color(0xFF262626), height: 16, indent: 16, endIndent: 16),
            // Group 3: Move to project
            _menuTile(Icons.drive_file_move_outline, 'Move to project',
                trailing: Icons.chevron_right, onTap: () async {
              Navigator.of(sheetContext).pop();
              await _promptMoveToProject(conv);
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String label, {VoidCallback? onTap, Color? color, IconData? trailing}) {
    final c = color ?? _ink;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 19, color: c),
      title: Text(label, style: TextStyle(color: c, fontSize: 13.6)),
      trailing: trailing != null ? Icon(trailing, size: 17, color: _inkFaint) : null,
    );
  }

  /// "Share" — belum ada backend sharing/deep-link, jadi yang benar-benar
  /// terjadi: transkrip percakapan disalin ke clipboard (nyata, bukan
  /// tombol mati), bukan link URL palsu yang kalau dibuka tidak ke mana-mana.
  Future<void> _shareConversation(Map<String, dynamic> conv) async {
    final title = (conv['title'] as String?)?.trim().isNotEmpty == true ? conv['title'] as String : 'Percakapan';
    final rawMessages = conv['messages'];
    final messages = rawMessages is List ? rawMessages.whereType<Map<String, dynamic>>() : const <Map<String, dynamic>>[];
    final transcript = messages.map((m) {
      final isUser = m['isUser'] == true;
      final text = (m['text'] ?? '').toString();
      return '${isUser ? 'User' : 'AI'}: $text';
    }).join('\n\n');
    final shareText = transcript.isEmpty ? 'JeonChat — $title' : 'JeonChat — $title\n\n$transcript';
    await Clipboard.setData(ClipboardData(text: shareText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transkrip chat disalin ke clipboard')),
    );
  }

  Future<void> _promptMoveToProject(Map<String, dynamic> conv) async {
    final currentProjectId = conv['projectId'] as String?;
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Pindahkan ke project',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _inkMuted)),
              ),
            ),
            ListTile(
              leading: Icon(Icons.close, color: _inkMuted, size: 19),
              title: const Text('Tanpa project', style: TextStyle(color: _ink, fontSize: 13.6)),
              trailing: currentProjectId == null ? const Icon(Icons.check, color: _ink, size: 18) : null,
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onMoveToProject(conv['id'] as String, null);
              },
            ),
            ...widget.projects.map((p) {
              final id = p['id'] as String;
              final name = (p['name'] as String?)?.trim().isNotEmpty == true ? p['name'] as String : 'Project';
              final color = _colorFromHex(p['color'] as String? ?? '#58A6FF');
              final icon = _iconFromKey(p['icon'] as String? ?? 'folder');
              return ListTile(
                leading: Icon(icon, color: color, size: 19),
                title: Text(name, style: const TextStyle(color: _ink, fontSize: 13.6)),
                trailing: id == currentProjectId ? const Icon(Icons.check, color: _ink, size: 18) : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  widget.onMoveToProject(conv['id'] as String, id);
                },
              );
            }),
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

  /// Dashboard kredit — badge "Kredit: X/Y" + progress bar tipis dekat
  /// footer profil, tap buka rincian (plan, biaya per fitur, Upgrade).
  /// Disembunyikan kalau [quota] belum dimuat (mis. user belum login).
  Widget _creditBadge() {
    final quota = widget.quota;
    if (quota == null) return const SizedBox.shrink();
    final plan = (quota['plan'] ?? '').toString();
    // Owner/master tanpa kuota — jangan tampilkan badge kredit
    if (plan == 'master' || plan.isEmpty && (quota['message'] ?? '').toString().contains('Master')) {
      return const SizedBox.shrink();
    }
    final credits = quota['credits'] as Map<String, dynamic>? ?? {};
    final total = (credits['total'] as num?)?.toInt() ?? 0;
    final remaining = (credits['remaining'] as num?)?.toInt() ?? 0;
    final ratio = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0.0;
    final depleted = remaining <= 0;
    const okGreen = Color(0xFF3FB950);

    return InkWell(
      onTap: () => _showQuotaDetail(quota),
      hoverColor: _hoverBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, size: 13, color: depleted ? _deleteRed : okGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    depleted ? 'Kredit habis — upgrade untuk lanjut' : 'Kredit: $remaining/$total',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: depleted ? _deleteRed : _ink, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                backgroundColor: _borderColor,
                valueColor: AlwaysStoppedAnimation(depleted ? _deleteRed : okGreen),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuotaDetail(Map<String, dynamic> quota) {
    final plan = (quota['plan'] ?? 'free').toString();
    // Owner/master tanpa kuota — tampilkan info full access, bukan kredit
    if (plan == 'master') {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF171717),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.workspace_premium, size: 20, color: Color(0xFF3FB950)),
                    const SizedBox(width: 8),
                    Text('Plan: Master', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: _ink)),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('Akses penuh tanpa batas kuota. Semua fitur tersedia.',
                    style: TextStyle(fontSize: 13, color: _inkMuted)),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Tutup', style: TextStyle(color: Color(0xFF3FB950), fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    final planLabel = plan.isEmpty ? plan : '${plan[0].toUpperCase()}${plan.substring(1)}';
    final credits = quota['credits'] as Map<String, dynamic>? ?? {};
    final total = (credits['total'] as num?)?.toInt() ?? 0;
    final remaining = (credits['remaining'] as num?)?.toInt() ?? 0;
    final used = (credits['used'] as num?)?.toInt() ?? (total - remaining);
    final costs = credits['cost_per_feature'] as Map<String, dynamic>? ?? {};

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171717),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Plan: $planLabel',
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: _ink)),
              const SizedBox(height: 6),
              Text('Kredit tersisa: $remaining dari $total (terpakai $used)',
                  style: const TextStyle(fontSize: 13, color: _inkMuted)),
              if (costs.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Biaya per fitur',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _inkFaint)),
                const SizedBox(height: 8),
                ...costs.entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(_prettifyFeature(e.key), style: const TextStyle(fontSize: 13, color: _ink)),
                          ),
                          Text('${e.value} kredit', style: const TextStyle(fontSize: 12, color: _inkMuted)),
                        ],
                      ),
                    )),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 44,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Halaman upgrade segera hadir')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: const Text('Upgrade', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _prettifyFeature(String key) => key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}';

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
            if (widget.userSkillCount > 0) ...[
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: widget.onOpenUserSkills,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x29A371F7),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFA371F7)),
                  ),
                  child: Text('🧠 ${widget.userSkillCount}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFA371F7))),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.settings_outlined, size: 16, color: _inkFaint),
          ],
        ),
      ),
    );
  }
}
