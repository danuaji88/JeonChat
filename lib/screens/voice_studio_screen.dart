import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../theme.dart';

class _VoiceCategory {
  final String emoji;
  final String label;
  final bool Function(Map<String, dynamic>) test;
  const _VoiceCategory({required this.emoji, required this.label, required this.test});
}

/// Voice Studio — pilih suara TTS default dari katalog suara Indonesia
/// (GET /voices/api). pop(namaSuara) kalau user memilih & menyimpan lewat
/// "✨ Gunakan", pop(null)/tanpa nilai kalau cuma keluar tanpa memilih.
class VoiceStudioScreen extends StatefulWidget {
  final ApiService api;

  const VoiceStudioScreen({super.key, required this.api});

  @override
  State<VoiceStudioScreen> createState() => _VoiceStudioScreenState();
}

class _VoiceStudioScreenState extends State<VoiceStudioScreen> {
  static final List<_VoiceCategory> _categories = [
    _VoiceCategory(emoji: '🚺', label: 'Perempuan', test: (v) => _lower(v['gender']) == 'female'),
    _VoiceCategory(emoji: '🚹', label: 'Laki-laki', test: (v) => _lower(v['gender']) == 'male'),
    _VoiceCategory(emoji: '👶', label: 'Bayi', test: (v) => _lower(v['kelompok']) == 'bayi'),
    _VoiceCategory(emoji: '🧒', label: 'Anak Kecil', test: (v) => _lower(v['kelompok']) == 'anak_kecil'),
    _VoiceCategory(
      emoji: '🧑',
      label: 'Remaja/Muda',
      test: (v) {
        final k = _lower(v['kelompok']);
        return k == 'remaja' || k == 'muda';
      },
    ),
    _VoiceCategory(emoji: '🧔', label: 'Dewasa', test: (v) => _lower(v['kelompok']) == 'dewasa'),
    _VoiceCategory(emoji: '👴', label: 'Tua/Bijak', test: (v) => _lower(v['kelompok']) == 'tua'),
  ];

  static String _lower(dynamic v) => (v ?? '').toString().toLowerCase();

  bool _loading = true;
  String? _error;
  int _total = 0;
  List<Map<String, dynamic>> _allVoices = [];

  _VoiceCategory? _selectedCategory;
  final _searchController = TextEditingController();
  String _query = '';

  final AudioPlayer _previewPlayer = AudioPlayer();
  String? _playingVoiceId;

  Map<String, dynamic>? _selectedVoice;
  bool _saving = false;
  bool _usePressed = false;

  @override
  void initState() {
    super.initState();
    _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingVoiceId = null);
    });
    _loadVoices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.getVoices();
      final rawVoices = res['voices'];
      final voices = rawVoices is List
          ? rawVoices.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final total = (res['total'] as num?)?.toInt() ?? voices.length;
      if (!mounted) return;
      setState(() {
        _total = total;
        _allVoices = voices;
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

  List<Map<String, dynamic>> get _filteredVoices {
    final cat = _selectedCategory;
    if (cat == null) return const [];
    var list = _allVoices.where(cat.test).toList();
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((v) {
        final name = (v['name'] ?? '').toString().toLowerCase();
        final desc = (v['descriptive'] ?? '').toString().toLowerCase();
        return name.contains(q) || desc.contains(q);
      }).toList();
    }
    return list.take(60).toList();
  }

  String _formattedTotal() {
    final s = _total.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write('.');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  Future<void> _togglePreview(String voiceId, String previewUrl) async {
    if (previewUrl.isEmpty) return;
    if (_playingVoiceId == voiceId) {
      await _previewPlayer.stop();
      if (mounted) setState(() => _playingVoiceId = null);
      return;
    }
    try {
      await _previewPlayer.stop();
      setState(() => _playingVoiceId = voiceId);
      await _previewPlayer.play(UrlSource(previewUrl));
    } catch (e) {
      if (!mounted) return;
      setState(() => _playingVoiceId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memutar preview: $e')));
    }
  }

  Future<void> _copyVoiceId(String voiceId) async {
    await Clipboard.setData(ClipboardData(text: voiceId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice ID disalin')));
  }

  Future<void> _useVoice(Map<String, dynamic> voice) async {
    final voiceId = (voice['voice_id'] ?? '').toString();
    final name = (voice['name'] ?? 'Suara').toString();
    if (voiceId.isEmpty) return;
    setState(() => _saving = true);
    try {
      final settings = await SettingsService.loadFromPrefs();
      settings.selectedVoiceId = voiceId;
      settings.selectedVoiceName = name;
      await settings.save();
      if (!mounted) return;
      Navigator.of(context).pop(name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan pilihan: $e')));
    }
  }

  void _backOrExit() {
    if (_selectedCategory != null) {
      setState(() {
        _selectedCategory = null;
        _selectedVoice = null;
        _query = '';
        _searchController.clear();
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      appBar: AppBar(
        backgroundColor: JeonColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20, color: JeonColors.ink),
          tooltip: 'Kembali',
          onPressed: _backOrExit,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_selectedCategory?.label ?? 'Pilih Suara',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: JeonColors.ink)),
            if (_selectedCategory == null && !_loading && _error == null)
              Text('${_formattedTotal()} suara Indonesia',
                  style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
          ],
        ),
      ),
      body: _body(),
      bottomNavigationBar: _selectedCategory != null && _selectedVoice != null ? _useBar() : null,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: JeonColors.accent));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 32, color: JeonColors.inkFaint),
              const SizedBox(height: 10),
              Text('⚠️ $_error', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: JeonColors.inkFaint)),
              const SizedBox(height: 14),
              SizedBox(
                height: 40,
                child: OutlinedButton(
                  onPressed: _loadVoices,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: JeonColors.border),
                    foregroundColor: JeonColors.ink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  child: const Text('Coba Lagi', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _selectedCategory == null ? _categoryGrid() : _voiceList();
  }

  Widget _categoryGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.6,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, i) {
        final cat = _categories[i];
        final count = _allVoices.where(cat.test).length;
        return _categoryTile(cat, count);
      },
    );
  }

  Widget _categoryTile(_VoiceCategory cat, int count) {
    return InkWell(
      borderRadius: BorderRadius.circular(JeonRadius.card),
      onTap: () => setState(() => _selectedCategory = cat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: JeonColors.surface2,
          border: Border.all(color: JeonColors.borderSoft),
          borderRadius: BorderRadius.circular(JeonRadius.card),
        ),
        child: Row(
          children: [
            Text(cat.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(cat.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                  const SizedBox(height: 2),
                  Text('$count suara', style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceList() {
    final voices = _filteredVoices;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _searchField(),
        ),
        Expanded(
          child: voices.isEmpty
              ? Center(
                  child: Text(
                    _query.trim().isEmpty ? 'Belum ada suara di kategori ini.' : 'Tidak ditemukan.',
                    style: const TextStyle(fontSize: 12.5, color: JeonColors.inkFaint),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: voices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _voiceCard(voices[i]),
                ),
        ),
      ],
    );
  }

  Widget _searchField() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: JeonColors.ink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: JeonColors.inkFaint),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 13, color: JeonColors.ink),
              decoration: const InputDecoration(
                hintText: 'Cari nama atau gaya suara...',
                hintStyle: TextStyle(color: JeonColors.inkFaint),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_query.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: JeonColors.inkFaint),
              ),
            ),
        ],
      ),
    );
  }

  Widget _voiceCard(Map<String, dynamic> voice) {
    final voiceId = (voice['voice_id'] ?? '').toString();
    final name = (voice['name'] ?? 'Suara').toString();
    final gender = _lower(voice['gender']);
    final kelompok = (voice['kelompok'] ?? '').toString();
    final descriptive = (voice['descriptive'] ?? '').toString();
    final previewUrl = (voice['preview_url'] ?? '').toString();
    final isSelected = _selectedVoice != null && (_selectedVoice!['voice_id'] ?? '').toString() == voiceId;
    final isPlaying = _playingVoiceId == voiceId;

    return InkWell(
      borderRadius: BorderRadius.circular(JeonRadius.card),
      onTap: () => setState(() => _selectedVoice = voice),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: JeonColors.surface2,
          border: Border.all(color: isSelected ? JeonColors.accent : JeonColors.borderSoft, width: isSelected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(JeonRadius.card),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: JeonColors.surface3,
                border: Border.all(color: JeonColors.border),
              ),
              alignment: Alignment.center,
              child: Icon(_genderIcon(gender), size: 19, color: JeonColors.inkMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                      ),
                      if (kelompok.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _tag(kelompok),
                      ],
                    ],
                  ),
                  if (descriptive.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(descriptive,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: JeonColors.inkFaint, height: 1.3)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _iconAction(
                  icon: isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  onTap: previewUrl.isEmpty ? null : () => _togglePreview(voiceId, previewUrl),
                ),
                const SizedBox(height: 4),
                _iconAction(
                  icon: Icons.copy_rounded,
                  onTap: voiceId.isEmpty ? null : () => _copyVoiceId(voiceId),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _genderIcon(String gender) {
    if (gender == 'female') return Icons.woman_rounded;
    if (gender == 'male') return Icons.man_rounded;
    return Icons.person_rounded;
  }

  Widget _tag(String kelompok) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: JeonColors.accentGlow, borderRadius: BorderRadius.circular(6)),
        child: Text(kelompok, style: const TextStyle(fontSize: 9.5, color: JeonColors.accent, fontWeight: FontWeight.w600)),
      );

  Widget _iconAction({required IconData icon, required VoidCallback? onTap}) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: JeonColors.surface3),
          alignment: Alignment.center,
          child: Icon(icon, size: 15, color: onTap == null ? JeonColors.inkFaint.withValues(alpha: 0.4) : JeonColors.inkMuted),
        ),
      );

  Widget _useBar() {
    final voice = _selectedVoice!;
    final name = (voice['name'] ?? 'Suara').toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: JeonColors.bg,
        border: const Border(top: BorderSide(color: JeonColors.borderSoft)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: AnimatedScale(
          scale: _usePressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: GestureDetector(
            onTapDown: _saving ? null : (_) => setState(() => _usePressed = true),
            onTapUp: _saving ? null : (_) => setState(() => _usePressed = false),
            onTapCancel: () => setState(() => _usePressed = false),
            onTap: _saving ? null : () => _useVoice(voice),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: JeonColors.accent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              alignment: Alignment.center,
              child: _saving
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF04150A)))
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('✨ Gunakan "$name"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF04150A))),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
