import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../theme.dart';

/// Layar edit gambar ala ChatGPT/Gemini (AI generative image editing).
///
/// Alur:
///   1. Gambar tampil penuh sebagai latar (dengan dark overlay biar input
///      kontras & gampang dibaca).
///   2. Kolom input melayang "Jelaskan editan" + ikon mic + tombol kirim.
///   3. Kirim → panggil backend /image/edit (Kie Seedream i2i, ~$0.03).
///   4. Hasil editan tampil menggantikan gambar.
///
/// [imageUrl] = URL gambar yang mau diedit (dari bubble chat / generate).
/// [api] = fungsi editImage sudah terpasang di ApiService; screen ini hanya
/// perlu kirim gambar base64 + prompt, lalu terima URL hasil.
class ImageEditScreen extends StatefulWidget {
  final String imageUrl;
  final Future<String> Function(String base64Image, String prompt) onEdit;

  const ImageEditScreen({
    super.key,
    required this.imageUrl,
    required this.onEdit,
  });

  @override
  State<ImageEditScreen> createState() => _ImageEditScreenState();
}

class _ImageEditScreenState extends State<ImageEditScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _editing = false;
  String? _currentUrl; // URL gambar yang sedang tampil (asli / hasil edit)
  String? _error;
  String? _lastPrompt;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.imageUrl;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Download gambar (URL) jadi base64, lalu kirim ke backend edit.
  Future<void> _submitEdit() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || _editing) return;

    setState(() {
      _editing = true;
      _error = null;
      _lastPrompt = prompt;
    });

    try {
      final bytes = await _downloadImage(_currentUrl ?? widget.imageUrl);
      final base64 = base64Encode(bytes);
      final resultUrl = await widget.onEdit(base64, prompt);
      if (resultUrl.isEmpty) {
        throw Exception('Backend tidak mengembalikan URL hasil.');
      }
      setState(() {
        _currentUrl = resultUrl;
        _controller.clear();
      });
    } catch (e) {
      setState(() => _error = 'Gagal edit: $e');
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<Uint8List> _downloadImage(String url) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      throw Exception('Gagal mengunduh gambar (${res.statusCode}).');
    }
    return res.bodyBytes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Gambar penuh sebagai latar ──────────────────────────
          Positioned.fill(
            child: Image.network(
              _currentUrl ?? widget.imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              },
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Text('Gambar gagal dimuat', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
          // Dark overlay biar input kontras (ala referensi)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
          ),

          // ── Header: tombol tutup (X) kiri atas ──────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _CircleButton(
                      icon: Icons.close,
                      onTap: () => Navigator.of(context).pop(_currentUrl),
                    ),
                    const Spacer(),
                    if (_error == null)
                      Text(
                        _editing
                            ? 'Mengedit...'
                            : (_lastPrompt == null ? 'Jelaskan editan' : 'Diedit: $_lastPrompt'),
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Error banner ─────────────────────────────────────────
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              top: 70,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                ),
              ),
            ),

          // ── Input melayang "Jelaskan editan" ─────────────────────
          Positioned(
            left: 12,
            right: 12,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xE61C2128), // frosted dark
                    borderRadius: BorderRadius.circular(JeonRadius.pill),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: true,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Jelaskan editan',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                          ),
                          onSubmitted: (_) => _submitEdit(),
                        ),
                      ),
                      // Ikon mic (visual, dikte on-device bisa ditambah di sini)
                      IconButton(
                        icon: const Icon(Icons.mic_none, color: Colors.white70, size: 22),
                        onPressed: () {
                          // Dikte belum terpasang di screen ini — hint ringan.
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Dikte suara tersedia di input bar chat utama.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      // Tombol kirim
                      _editing
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.arrow_upward, color: Colors.black),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white,
                                disabledBackgroundColor: Colors.white38,
                              ),
                              onPressed: _submitEdit,
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
