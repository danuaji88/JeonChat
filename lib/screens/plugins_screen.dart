import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _Tab { plugins, skills }

/// Satu entri plugin/skill — dipakai untuk Featured/Productivity/Creativity
/// (tab Plugins) maupun daftar skill JEON (tab Skills). [id] slug snake_case
/// dikirim ke backend /agent 'plugins' (lihat PluginService); skill built-in
/// (tab Skills) tidak dikirim ke situ jadi tidak butuh id.
class PluginItem {
  final String emoji;
  final String title;
  final String description;
  final String id;

  const PluginItem({required this.emoji, required this.title, required this.description, this.id = ''});
}

/// Isi Plugin Store ala ChatGPT — dipakai SEBAGAI KONTEN AREA CHAT (bukan
/// route/Scaffold sendiri) supaya sidebar tetap terlihat. Status install
/// plugin (tab Plugins) dikendalikan parent lewat [installedIds] +
/// [onTogglePlugin] — persisted lewat PluginService — supaya sinkron dengan
/// section "My Plugins" di sidebar dan badge di input bar. Tab Skills tetap
/// state internal (belum diminta ikut dipersist/diselaraskan ke luar).
class PluginsStoreView extends StatefulWidget {
  final Set<String> installedIds;
  final ValueChanged<PluginItem> onTogglePlugin;
  final VoidCallback onBack;

  const PluginsStoreView({
    super.key,
    required this.installedIds,
    required this.onTogglePlugin,
    required this.onBack,
  });

  @override
  State<PluginsStoreView> createState() => _PluginsStoreViewState();
}

class _PluginsStoreViewState extends State<PluginsStoreView> {
  static const _bg = Colors.black;
  static const _pillBg = Color(0xFF1A1A1A);
  static const _borderColor = Color(0xFF262626);
  static const _installedGreen = Color(0xFF2ECC71);
  static const _ink = Colors.white;
  static const _inkMuted = Color(0xFF8E8E93);

  static const _customSkillsKey = 'jeon_custom_skills';

  static const _featured = <PluginItem>[
    PluginItem(id: 'video_editor', emoji: '🎬', title: 'Video Editor', description: 'Cut, merge, filter, caption, subtitle'),
    PluginItem(id: 'ai_clipper', emoji: '✂️', title: 'AI Clipper', description: 'Potong video jadi klip viral otomatis'),
    PluginItem(id: 'image_generator', emoji: '🖼️', title: 'Image Generator', description: 'Gambar gratis & berbayar (Flux, Gemini, Novita)'),
    PluginItem(id: 'video_generator', emoji: '🎥', title: 'Video Generator', description: 'Veo 3.1, Hailuo, Kie Veo3'),
    PluginItem(id: 'tts', emoji: '🔊', title: 'TTS Voice-over', description: 'Edge gratis, ElevenLabs natural'),
    PluginItem(id: 'sound_effects', emoji: '🎵', title: 'Sound Effects', description: '15.992 file SFX'),
    PluginItem(id: 'photo_filter', emoji: '📸', title: 'Filter Foto', description: 'Natural skin bright, blue sky, LUT 3D'),
    PluginItem(id: 'report', emoji: '📊', title: 'Laporan', description: 'HTML, Word, Excel, PPT, PDF'),
    PluginItem(id: 'video_analysis', emoji: '🎥', title: 'Analisis Video', description: 'Teknis, visual, isi, kualitas 0-100'),
    PluginItem(id: 'hashtag_generator', emoji: '#️⃣', title: 'Hashtag Generator', description: 'Viral hashtags per platform'),
    PluginItem(id: 'thumbnail', emoji: '🖼️', title: 'Thumbnail', description: 'YouTube thumbnail intelligence'),
    PluginItem(id: 'broll', emoji: '🎬', title: 'B-Roll', description: 'Footage pendukung otomatis'),
  ];

  static const _productivity = <PluginItem>[
    PluginItem(id: 'google_workspace', emoji: '📧', title: 'Google Workspace', description: 'Gmail, Calendar, Drive'),
    PluginItem(id: 'github', emoji: '🐙', title: 'GitHub', description: 'Kelola repo & issue langsung dari chat'),
    PluginItem(id: 'notion', emoji: '📓', title: 'Notion', description: 'Sinkron catatan & database Notion'),
    PluginItem(id: 'slack', emoji: '💬', title: 'Slack', description: 'Kirim & baca pesan tim di Slack'),
  ];

  static const _creativity = <PluginItem>[
    PluginItem(id: 'canva', emoji: '🎨', title: 'Canva', description: 'Desain grafis siap pakai'),
    PluginItem(id: 'capcut', emoji: '✂️', title: 'CapCut', description: 'Edit video gaya CapCut'),
    PluginItem(id: 'suno', emoji: '🎼', title: 'Suno AI Music', description: 'Bikin musik dari prompt teks'),
    PluginItem(id: 'stable_audio', emoji: '🎧', title: 'Stable Audio', description: 'Generate audio & musik AI'),
  ];

  static const _skills = <PluginItem>[
    PluginItem(emoji: '🧠', title: 'AI Clipper', description: 'Potong video panjang jadi klip viral'),
    PluginItem(emoji: '📝', title: 'Caption Pro', description: 'Subtitle profesional auto-generate'),
    PluginItem(emoji: '🎨', title: 'Color Correction', description: 'Color grading LUT 3D'),
    PluginItem(emoji: '📱', title: 'Shortform Editor', description: 'Edit untuk TikTok/Reels/Shorts'),
    PluginItem(emoji: '🗣️', title: 'Storytelling', description: 'Analisis cerita video'),
    PluginItem(emoji: '🏷️', title: 'Thumbnail Intel', description: 'Optimasi thumbnail YouTube'),
    PluginItem(emoji: '🎵', title: 'Sound Design', description: 'Music by mood + SFX'),
    PluginItem(emoji: '📈', title: 'Platform Intelligence', description: 'Format optimal per platform'),
    PluginItem(emoji: '🎙️', title: 'Scene Understanding', description: 'Analisis adegan video'),
    PluginItem(emoji: '✅', title: 'Quality Control', description: 'QC video sebelum publish'),
  ];

  _Tab _tab = _Tab.plugins;
  final _searchController = TextEditingController();
  String _query = '';

  final Set<String> _installedSkills = {};
  List<Map<String, String>> _customSkills = [];

  @override
  void initState() {
    super.initState();
    _loadCustomSkills();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomSkills() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_customSkillsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List;
      final skills = decoded.whereType<Map>().map((m) => {
            'name': (m['name'] ?? '').toString(),
            'description': (m['description'] ?? '').toString(),
          }).toList();
      if (!mounted) return;
      setState(() => _customSkills = skills);
    } catch (_) {
      // Data lama rusak/format tidak dikenal — biarkan daftar custom skill kosong.
    }
  }

  Future<void> _saveCustomSkills(List<Map<String, String>> skills) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customSkillsKey, jsonEncode(skills));
  }

  void _toggleSkill(String title) => setState(() {
        if (_installedSkills.contains(title)) {
          _installedSkills.remove(title);
        } else {
          _installedSkills.add(title);
        }
      });

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    return Container(
      color: _bg,
      child: Column(
        children: [
          _backRow(),
          _tabSwitcher(),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: _tab == _Tab.plugins ? _pluginsBody(isWide) : _skillsBody(isWide),
            ),
          ),
        ],
      ),
    );
  }

  Widget _backRow() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onBack,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 18, color: _ink),
                    SizedBox(width: 6),
                    Text('Back', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _ink)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _tabSwitcher() => Center(
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: _pillBg, borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tabSegment('Plugins', _Tab.plugins),
              _tabSegment('Skills', _Tab.skills),
            ],
          ),
        ),
      );

  Widget _tabSegment(String label, _Tab value) {
    final active = _tab == value;
    return GestureDetector(
      onTap: () => setState(() => _tab = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2D2D2D) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500, color: active ? _ink : _inkMuted)),
      ),
    );
  }

  Widget _header(bool isWide, String title, String subtitle) {
    final titleCol = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _ink)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 12.5, color: _inkMuted)),
      ],
    );
    if (isWide) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleCol),
            SizedBox(width: 240, child: _searchBar()),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleCol,
          const SizedBox(height: 12),
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
                decoration: InputDecoration(
                  hintText: _tab == _Tab.plugins ? 'Search plugins' : 'Search skills',
                  hintStyle: const TextStyle(color: _inkMuted),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _sectionLabel(String text, {bool trailingChevron = false}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(fontSize: 12, color: _inkMuted, fontWeight: FontWeight.w600)),
          if (trailingChevron) ...[
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, size: 14, color: _inkMuted),
          ],
        ],
      );

  Widget _seeMore() => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: InkWell(
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Plugin lainnya segera hadir'), duration: Duration(seconds: 1)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('See more', style: TextStyle(fontSize: 12, color: _inkMuted)),
              SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 14, color: _inkMuted),
            ],
          ),
        ),
      );

  Widget _noResults() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.search_off, size: 40, color: _inkMuted),
              SizedBox(height: 10),
              Text('Tidak ditemukan', style: TextStyle(fontSize: 13, color: _inkMuted)),
            ],
          ),
        ),
      );

  // ---- Tab Plugins ----
  // Plugin yang sudah di-install "pindah" ke section Installed di paling
  // atas (dan hilang dari section kategori aslinya) — status install datang
  // dari widget.installedIds (dikendalikan parent, persisted).

  Widget _pluginsBody(bool isWide) {
    final q = _query.trim().toLowerCase();
    bool matches(PluginItem p) => q.isEmpty || p.title.toLowerCase().contains(q);
    bool isInstalled(PluginItem p) => widget.installedIds.contains(p.id);

    final allPlugins = [..._featured, ..._productivity, ..._creativity];
    final installed = allPlugins.where((p) => isInstalled(p) && matches(p)).toList();
    final featured = _featured.where((p) => !isInstalled(p) && matches(p)).toList();
    final productivity = _productivity.where((p) => !isInstalled(p) && matches(p)).toList();
    final creativity = _creativity.where((p) => !isInstalled(p) && matches(p)).toList();
    final empty = installed.isEmpty && featured.isEmpty && productivity.isEmpty && creativity.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(isWide, 'Plugins', 'Tambahkan tools untuk membuat JeonAI lebih cerdas'),
        if (empty) _noResults(),
        if (installed.isNotEmpty) ...[
          _sectionLabel('Installed'),
          const SizedBox(height: 10),
          _grid(installed.map((p) => _toolTile(p, true, () => widget.onTogglePlugin(p))).toList(), isWide),
          const SizedBox(height: 22),
        ],
        if (featured.isNotEmpty) ...[
          _sectionLabel('Featured'),
          const SizedBox(height: 10),
          _grid(featured.map((p) => _toolTile(p, false, () => widget.onTogglePlugin(p))).toList(), isWide),
          _seeMore(),
          const SizedBox(height: 22),
        ],
        if (productivity.isNotEmpty) ...[
          _sectionLabel('Productivity'),
          const SizedBox(height: 10),
          _grid(productivity.map((p) => _toolTile(p, false, () => widget.onTogglePlugin(p))).toList(), isWide),
          _seeMore(),
          const SizedBox(height: 22),
        ],
        if (creativity.isNotEmpty) ...[
          _sectionLabel('Creativity'),
          const SizedBox(height: 10),
          _grid(creativity.map((p) => _toolTile(p, false, () => widget.onTogglePlugin(p))).toList(), isWide),
          _seeMore(),
        ],
      ],
    );
  }

  // ---- Tab Skills ----

  Widget _skillsBody(bool isWide) {
    final q = _query.trim().toLowerCase();
    final builtin = _skills.where((s) => q.isEmpty || s.title.toLowerCase().contains(q)).toList();
    final custom = _customSkills.where((s) => q.isEmpty || (s['name'] ?? '').toLowerCase().contains(q)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(isWide, 'Skills', 'Ajarkan JeonAI skill baru dari workflow kerjamu'),
        _sectionLabel('JEON Skills'),
        const SizedBox(height: 10),
        if (builtin.isEmpty && custom.isEmpty)
          _noResults()
        else ...[
          ...builtin.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _toolTile(s, _installedSkills.contains(s.title), () => _toggleSkill(s.title)),
              )),
          if (custom.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionLabel('Custom Skills'),
            const SizedBox(height: 10),
            ...custom.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _toolTile(
                    PluginItem(
                      emoji: '⭐',
                      title: s['name'] ?? '',
                      description: (s['description']?.isNotEmpty ?? false) ? s['description']! : 'Custom skill',
                    ),
                    true,
                    null,
                  ),
                )),
          ],
        ],
        const SizedBox(height: 8),
        _addCustomSkillButton(),
      ],
    );
  }

  Widget _addCustomSkillButton() => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _addCustomSkillSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border.all(color: _borderColor), borderRadius: BorderRadius.circular(10)),
          alignment: Alignment.center,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: _ink),
              SizedBox(width: 8),
              Text('Add Custom Skill', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: _ink)),
            ],
          ),
        ),
      );

  Future<void> _addCustomSkillSheet() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
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
            const Text('Add Custom Skill', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: _ink)),
            const SizedBox(height: 14),
            TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(fontSize: 13.4, color: _ink),
              decoration: InputDecoration(
                hintText: 'Nama skill',
                hintStyle: const TextStyle(color: _inkMuted),
                filled: true,
                fillColor: const Color(0xFF262626),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              maxLines: 3,
              style: const TextStyle(fontSize: 13.4, color: _ink),
              decoration: InputDecoration(
                hintText: 'Deskripsi singkat',
                hintStyle: const TextStyle(color: _inkMuted),
                filled: true,
                fillColor: const Color(0xFF262626),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
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
                child: const Text('Simpan Skill', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );

    final name = nameController.text.trim();
    if (saved == true && name.isNotEmpty) {
      final updated = [
        ..._customSkills,
        {'name': name, 'description': descController.text.trim()},
      ];
      await _saveCustomSkills(updated);
      if (!mounted) return;
      setState(() => _customSkills = updated);
    }
  }

  // ---- Shared tile/grid helpers ----

  Widget _grid(List<Widget> tiles, bool isWide) {
    if (!isWide) {
      return Column(children: tiles.map((t) => Padding(padding: const EdgeInsets.only(bottom: 10), child: t)).toList());
    }
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final second = i + 1 < tiles.length ? tiles[i + 1] : null;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 12),
            Expanded(child: second ?? const SizedBox()),
          ],
        ),
      ));
    }
    return Column(children: rows);
  }

  Widget _toolTile(PluginItem item, bool installed, VoidCallback? onToggle) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _pillBg, borderRadius: BorderRadius.circular(10)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: _borderColor, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: Text(item.emoji, style: const TextStyle(fontSize: 15)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
                  const SizedBox(height: 2),
                  Text(item.description,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: _inkMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _installButton(installed, onToggle),
          ],
        ),
      );

  Widget _installButton(bool installed, VoidCallback? onTap) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: installed ? _installedGreen : Colors.transparent,
            border: Border.all(color: installed ? _installedGreen : _ink, width: 1),
          ),
          alignment: Alignment.center,
          child: Icon(installed ? Icons.check : Icons.add, size: 15, color: installed ? Colors.white : _ink),
        ),
      );
}
