import 'dart:async';

import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme.dart';
import 'audio_message_player.dart';
import 'tool_card.dart';

const _thinkingPlaceholder = '⏳ AI sedang bekerja...';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  // Deteksi URL media (gambar/video) yang disisipkan AI langsung di teks
  // balasan — baik lewat sintaks markdown image maupun URL polos.
  static final _markdownImageRegex = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');
  static final _directImageUrlRegex =
      RegExp(r'https?://[^\s\)\]]+\.(jpg|jpeg|png|gif|webp)(\?[^\s]*)?', caseSensitive: false);
  static final _directVideoUrlRegex =
      RegExp(r'https?://[^\s\)\]]+\.(mp4|webm)(\?[^\s]*)?', caseSensitive: false);

  ({String url, bool isVideo})? _extractMediaUrl(String text) {
    final mdMatch = _markdownImageRegex.firstMatch(text);
    if (mdMatch != null) {
      final url = mdMatch.group(1)!.trim();
      return (url: url, isVideo: _directVideoUrlRegex.hasMatch(url));
    }
    final imgMatch = _directImageUrlRegex.firstMatch(text);
    if (imgMatch != null) {
      return (url: imgMatch.group(0)!, isVideo: false);
    }
    final videoMatch = _directVideoUrlRegex.firstMatch(text);
    if (videoMatch != null) {
      return (url: videoMatch.group(0)!, isVideo: true);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final isThinking = !isUser && message.text == _thinkingPlaceholder;
    final media = isUser ? null : _extractMediaUrl(message.text);
    // Kalau ada media, jangan tampilkan markdown/URL mentahnya lagi di teks —
    // gambarnya sudah dirender di atas, teks mentah cuma bikin duplikat.
    String cleanText = message.text;
    if (media != null) {
      cleanText = message.text.replaceAll(_markdownImageRegex, '').trim();
      cleanText = cleanText.replaceAll(_directImageUrlRegex, '').trim();
    }

    final avatar = Container(
      width: 28,
      height: 28,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isUser ? JeonColors.surface3 : null,
        border: isUser ? Border.all(color: JeonColors.border) : null,
        gradient: isUser
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [JeonColors.accent, JeonColors.accentDim],
              ),
        boxShadow: isUser
            ? null
            : [
                BoxShadow(
                  color: JeonColors.accentGlow,
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ],
      ),
      alignment: Alignment.center,
      child: Text(
        isUser ? 'AJ' : 'J',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isUser ? JeonColors.inkMuted : const Color(0xFF04150A),
        ),
      ),
    );

    final bubble = Flexible(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isUser ? JeonColors.accent.withValues(alpha: 0.15) : JeonColors.surface2,
          border: Border.all(
            color: isUser ? JeonColors.accent.withValues(alpha: 0.3) : JeonColors.borderSoft,
          ),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(JeonRadius.bubble),
            topRight: const Radius.circular(JeonRadius.bubble),
            bottomLeft: Radius.circular(isUser ? JeonRadius.bubble : 4),
            bottomRight: Radius.circular(isUser ? 4 : JeonRadius.bubble),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (media != null)
              media.isVideo ? _videoUrlPlaceholder(media.url) : _markdownImagePreview(media.url),
            if (isThinking)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('⏳ AI sedang bekerja', style: TextStyle(fontSize: 13.4, color: JeonColors.ink, height: 1.4)),
                  _ThinkingDots(),
                ],
              )
            else
              SelectableText(
                cleanText,
                style: TextStyle(
                  fontSize: 13.4,
                  color: isUser ? JeonColors.ink : JeonColors.ink,
                  height: 1.4,
                ),
                toolbarOptions: const ToolbarOptions(
                  copy: true,
                  selectAll: true,
                ),
              ),
            if (message.toolCall != null) ToolCardWidget(toolCall: message.toolCall!),
            if (message.imageUrl != null) _imagePreview(message.imageUrl!),
            if (message.audioUrl != null) AudioMessagePlayer(url: message.audioUrl!),
            if (message.videoUrl != null) _videoCard(message.videoUrl!),
            if (message.filePath != null) _fileCard(message.filePath!),
            if (message.costChip != null || message.timeChip != null)
              Container(
                margin: const EdgeInsets.only(top: 9),
                padding: const EdgeInsets.only(top: 9),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: JeonColors.borderSoft)),
                ),
                child: Row(
                  children: [
                    if (message.costChip != null) _chip(message.costChip!),
                    if (message.costChip != null && message.timeChip != null)
                      const SizedBox(width: 6),
                    if (message.timeChip != null) _chip(message.timeChip!),
                    const Spacer(),
                    Icon(Icons.copy, size: 14, color: JeonColors.inkFaint),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: isUser
              ? [bubble, const SizedBox(width: 10), avatar]
              : [avatar, const SizedBox(width: 10), bubble],
        ),
      ),
    );
  }

  Widget _markdownImagePreview(String url) => RepaintBoundary(
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              width: double.infinity,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const _ShimmerBox(height: 180);
              },
              errorBuilder: (context, error, stackTrace) => Container(
                padding: const EdgeInsets.all(10),
                alignment: Alignment.center,
                color: JeonColors.surface3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined, color: JeonColors.inkFaint, size: 24),
                    const SizedBox(height: 6),
                    Text(url,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: JeonColors.inkMuted)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _videoUrlPlaceholder(String url) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(url, style: const TextStyle(fontSize: 11, color: JeonColors.inkMuted)),
      );

  Widget _imagePreview(String url) => RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(JeonRadius.small),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: Image.network(
                url,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const _ShimmerBox(height: 180);
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 120,
                  alignment: Alignment.center,
                  color: JeonColors.surface3,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined, color: JeonColors.inkFaint, size: 24),
                      SizedBox(height: 6),
                      Text('Gambar gagal dimuat', style: TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _videoCard(String url) {
    final name = url.contains('/') ? url.substring(url.lastIndexOf('/') + 1) : url;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: JeonColors.surface3,
        border: Border.all(color: JeonColors.borderSoft),
        borderRadius: BorderRadius.circular(JeonRadius.small),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration:
                BoxDecoration(color: JeonColors.accentGlow, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: const Icon(Icons.play_circle_outline, size: 18, color: JeonColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                const Text('Video siap — player inline menyusul, buka link untuk tonton',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: JeonColors.inkFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileCard(String path) {
    final name = path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: JeonColors.surface3,
        border: Border.all(color: JeonColors.borderSoft),
        borderRadius: BorderRadius.circular(JeonRadius.small),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration:
                BoxDecoration(color: JeonColors.accentGlow, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: const Icon(Icons.insert_drive_file_outlined, size: 16, color: JeonColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                Text('File dibuat oleh agent di server · $path',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: JeonColors.inkFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: JeonColors.surface,
          border: Border.all(color: JeonColors.borderSoft),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10.5,
            color: JeonColors.inkFaint,
          ),
        ),
      );
}

/// Titik "..." yang berputar (".", "..", "...") tiap 500ms di belakang
/// "AI sedang bekerja" — widget kecil sendiri biar animasinya tidak memicu
/// rebuild seluruh ChatBubble.
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> {
  static const _frames = ['.', '..', '...'];
  int _frame = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % _frames.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_frames[_frame], style: const TextStyle(fontSize: 13.4, color: JeonColors.ink, height: 1.4));
  }
}

/// Shimmer placeholder sederhana (tanpa dependency tambahan) buat slot
/// gambar yang masih loading — sapuan gradient abu-abu bergerak.
class _ShimmerBox extends StatefulWidget {
  final double height;
  const _ShimmerBox({this.height = 180});

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: const [JeonColors.surface3, JeonColors.surface2, JeonColors.surface3],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment(-1 + 3 * t, 0),
            end: Alignment(1 + 3 * t, 0),
          ).createShader(bounds),
          child: Container(height: widget.height, color: Colors.white),
        );
      },
    );
  }
}
