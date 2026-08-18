import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../theme.dart';

/// Bottom input bar JeonChat: [+] [Ketik pesan...] [model ▾] [🎤] [🔵].
/// Semua interaksi murni-UI (dikte, popover "+", pilihan model, textfield)
/// hidup di sini; aksi yang perlu mengubah percakapan/panggil API dikirim
/// balik ke parent lewat callback.
class JeonChatInputBar extends StatefulWidget {
  final List<String> quickReplies;
  final void Function(String text, String model) onSend;
  final ValueChanged<String> onGenerateImage;
  final ValueChanged<String> onSearchWeb;
  final ValueChanged<String> onDeepResearch;
  final ValueChanged<String> onGenerateAudio;
  final ValueChanged<String> onGenerateVideo;

  /// Hasil pengenalan suara dari mode Voice — parent yang urus kirim +
  /// balas via TTS, karena butuh akses ke daftar pesan & API.
  final ValueChanged<String> onVoiceModeResult;

  /// Jumlah plugin aktif — badge "✓N" cuma tampil kalau > 0. Tap badge
  /// buka Plugin Store (lewat [onOpenPlugins]).
  final int activePluginCount;
  final VoidCallback? onOpenPlugins;

  const JeonChatInputBar({
    super.key,
    required this.quickReplies,
    required this.onSend,
    required this.onGenerateImage,
    required this.onSearchWeb,
    required this.onDeepResearch,
    required this.onGenerateAudio,
    required this.onGenerateVideo,
    required this.onVoiceModeResult,
    this.activePluginCount = 0,
    this.onOpenPlugins,
  });

  @override
  State<JeonChatInputBar> createState() => _JeonChatInputBarState();
}

class _JeonChatInputBarState extends State<JeonChatInputBar> {
  static const Map<String, String> _modelOptions = {
    'Fast': 'jeon-fast',
    'High': 'jeon-chat',
    'Think': 'jeon-strong',
  };

  final _controller = TextEditingController();
  bool _hasText = false;
  String _selectedModelLabel = 'High';

  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (!mounted) return;
      setState(() => _speechAvailable = available);
    } catch (_) {
      // Mic tidak tersedia/diizinkan — tombol mic otomatis nonaktif.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _speech.stop();
    super.dispose();
  }

  void _submit([String? preset]) {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;
    widget.onSend(text, _modelOptions[_selectedModelLabel] ?? 'jeon-chat');
    _controller.clear();
  }

  Future<void> _toggleMic() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mic tidak tersedia/diizinkan di browser ini')),
      );
      return;
    }
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _controller.text = result.recognizedWords;
          _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
        });
      },
    );
  }

  Future<void> _startVoiceMode() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mic tidak tersedia/diizinkan di browser ini')),
      );
      return;
    }
    if (_isListening) return;

    final completer = Completer<String>();
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(result.recognizedWords);
        }
      },
    );
    final recognized = await completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => '',
    );
    await _speech.stop();
    if (mounted) setState(() => _isListening = false);
    final spoken = recognized.trim();
    if (spoken.isEmpty) return;
    widget.onVoiceModeResult(spoken);
  }

  /// "Tambah foto & file" — genuinely membuka picker (image_picker), tapi
  /// backend tidak punya endpoint upload, jadi cuma bisa memilih, belum
  /// bisa mengirim isi filenya.
  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terpilih: ${picked.name} — upload file belum didukung backend saat ini')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka pemilih foto: $e')),
      );
    }
  }

  Future<void> _showPlusMenu() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: JeonColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: JeonColors.surface3, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 6),
            _plusMenuTile(Icons.add_photo_alternate_outlined, 'Tambah Foto & File', onTap: () {
              Navigator.of(sheetContext).pop();
              _pickPhoto();
            }),
            _plusMenuTile(Icons.image_outlined, 'Buat Gambar', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Buat Gambar', 'Gambar apa yang mau dibuat?', widget.onGenerateImage);
            }),
            _plusMenuTile(Icons.movie_creation_outlined, 'Buat Video', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Buat Video', 'Video apa yang mau dibuat?', widget.onGenerateVideo);
            }),
            _plusMenuTile(Icons.graphic_eq_rounded, 'Buat Suara', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Buat Suara', 'Teks yang mau dibacakan?', widget.onGenerateAudio);
            }),
            _plusMenuTile(Icons.travel_explore_outlined, 'Cari di Web', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Cari di Web', 'Mau cari apa?', widget.onSearchWeb);
            }),
            _plusMenuTile(Icons.science_outlined, 'Riset Mendalam', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Riset Mendalam', 'Topik riset apa?', widget.onDeepResearch);
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _plusMenuTile(IconData icon, String label, {required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 19, color: JeonColors.ink),
      title: Text(label, style: const TextStyle(fontSize: 13.6, color: JeonColors.ink)),
    );
  }

  Future<void> _promptFor(String title, String hint, ValueChanged<String> onSubmit) async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JeonColors.surface,
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
            Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: JeonColors.inkFaint),
                filled: true,
                fillColor: JeonColors.surface2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(JeonRadius.card),
                  borderSide: const BorderSide(color: JeonColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(JeonRadius.card),
                  borderSide: const BorderSide(color: JeonColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(JeonRadius.card),
                  borderSide: const BorderSide(color: JeonColors.accent),
                ),
              ),
              onSubmitted: (v) => Navigator.of(sheetContext).pop(v),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.of(sheetContext).pop(controller.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: JeonColors.accent,
                  foregroundColor: const Color(0xFF04150A),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
                ),
                child: const Text('Kirim', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    onSubmit(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
      child: Column(
        children: [
          if (widget.activePluginCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(alignment: Alignment.centerLeft, child: _pluginBadge()),
            ),
          if (widget.quickReplies.isNotEmpty)
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                itemCount: widget.quickReplies.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final q = widget.quickReplies[i];
                  return GestureDetector(
                    onTap: () => _submit(q),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: JeonColors.surface2,
                        border: Border.all(color: JeonColors.border),
                        borderRadius: BorderRadius.circular(JeonRadius.pill),
                      ),
                      child: Text(q, style: const TextStyle(fontSize: 12, color: JeonColors.inkMuted)),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 6, 4),
            decoration: BoxDecoration(
              color: JeonColors.surface2,
              border: Border.all(color: JeonColors.border),
              borderRadius: BorderRadius.circular(JeonRadius.pill),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.add, size: 20, color: JeonColors.inkMuted),
                  tooltip: 'Tambah',
                  onPressed: _showPlusMenu,
                ),
                Expanded(
                  child: Focus(
                    // Enter fisik selalu jadi newline di TextField multiline
                    // (tidak memicu onSubmitted) — intercept di sini: Enter
                    // polos = kirim, Shift+Enter = newline (default).
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                        if (!HardwareKeyboard.instance.isShiftPressed) {
                          _submit();
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
                      decoration: const InputDecoration(
                        hintText: 'Ask JeonChat...',
                        hintStyle: TextStyle(color: JeonColors.inkFaint),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                _modelDropdown(),
                const SizedBox(width: 4),
                if (_hasText)
                  Container(
                    decoration: const BoxDecoration(color: JeonColors.accent, shape: BoxShape.circle),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded, size: 17, color: Color(0xFF04150A)),
                      onPressed: () => _submit(),
                    ),
                  )
                else ...[
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none_rounded,
                      size: 19,
                      color: _isListening ? JeonColors.accent : JeonColors.inkFaint,
                    ),
                    tooltip: 'Dikte suara',
                    onPressed: _toggleMic,
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 2),
                    decoration: const BoxDecoration(color: JeonColors.accent, shape: BoxShape.circle),
                    child: IconButton(
                      icon: const Icon(Icons.graphic_eq_rounded, size: 17, color: Color(0xFF04150A)),
                      tooltip: 'Mode suara',
                      onPressed: _startVoiceMode,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pluginBadge() => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: widget.onOpenPlugins,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0x292ECC71),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFF2ECC71)),
          ),
          child: Text('✓${widget.activePluginCount}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2ECC71))),
        ),
      );

  Widget _modelDropdown() {
    return PopupMenuButton<String>(
      initialValue: _selectedModelLabel,
      color: JeonColors.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JeonRadius.small),
        side: const BorderSide(color: JeonColors.border),
      ),
      onSelected: (v) => setState(() => _selectedModelLabel = v),
      itemBuilder: (context) => _modelOptions.keys
          .map((k) => PopupMenuItem(
                value: k,
                child: Text(
                  k,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: k == _selectedModelLabel ? JeonColors.accent : JeonColors.ink,
                  ),
                ),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: JeonColors.surface3,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: JeonColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_selectedModelLabel,
                style: const TextStyle(fontSize: 11.5, color: JeonColors.inkMuted, fontWeight: FontWeight.w600)),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 14, color: JeonColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
