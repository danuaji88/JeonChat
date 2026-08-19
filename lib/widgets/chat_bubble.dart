import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../models/message.dart';
import '../theme.dart';
import 'audio_message_player.dart';
import 'tool_card.dart';

const _thinkingPlaceholder = 'JeonAI Sedang Berpikir Lalu Eksekusi Mohon Ditunggu';
const _analysisGreen = Color(0xFF2ECC71);

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  /// Tombol "Lihat" di banner AutoLearn — buka SkillListScreen. Null kalau
  /// pemanggil tidak menyediakan (banner tetap tampil, tombolnya disembunyikan).
  final VoidCallback? onViewAutoLearnSkill;

  const ChatBubble({super.key, required this.message, this.onViewAutoLearnSkill});

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
    if (isThinking) {
      return const _PremiumTypingBubble();
    }
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isUser
              ? JeonColors.accent.withValues(alpha: 0.15)
              : message.isAnalysis
                  ? _analysisGreen.withValues(alpha: 0.14)
                  : JeonColors.surface2,
          border: Border.all(
            color: isUser
                ? JeonColors.accent.withValues(alpha: 0.3)
                : message.isAnalysis
                    ? _analysisGreen.withValues(alpha: 0.4)
                    : JeonColors.borderSoft,
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
            if (message.docSource != null) _docSourceBadge(message.docSource!),
            if (media != null)
              media.isVideo ? _videoUrlPlaceholder(media.url) : _markdownImagePreview(media.url),
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
            if (message.searchResults != null && message.searchResults!.isNotEmpty)
              _searchResultsList(message.searchResults!),
            if (message.codeResult != null) _codeResultCard(message.codeResult!),
            if (message.pluginsUsed.isNotEmpty) _pluginsUsedBadge(message.pluginsUsed),
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
          if (message.autoLearnSkill != null) _autoLearnBanner(message.autoLearnSkill!),
        ],
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

  Widget _videoUrlPlaceholder(String url) => _videoCard(url);

  Widget _docSourceBadge(String docName) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: JeonColors.accentGlow,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('Dari dokumen: $docName',
              style: const TextStyle(fontSize: 10.5, color: JeonColors.accent, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _imagePreview(String url) => RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(JeonRadius.small),
      ),
      child: InkWell(
        onTap: () => _openUrl(url),
        borderRadius: BorderRadius.circular(JeonRadius.small),
        child: Container(
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
                    const Text('Ketuk untuk buka & putar video',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: JeonColors.inkFaint)),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 14, color: JeonColors.inkMuted),
            ],
          ),
        ),
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

  Widget _searchResultsList(List<Map<String, String>> results) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: results.map(_searchResultTile).toList(),
        ),
      );

  Widget _searchResultTile(Map<String, String> r) {
    final title = (r['title'] ?? '').trim().isNotEmpty ? r['title']! : (r['url'] ?? 'Hasil');
    final url = r['url'] ?? '';
    final snippet = r['snippet'] ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: url.isEmpty ? null : () => _openUrl(url),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    color: JeonColors.ink,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w600)),
          ),
          if (snippet.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(snippet, style: const TextStyle(fontSize: 11.5, color: JeonColors.inkMuted, height: 1.3)),
          ],
          if (url.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: _analysisGreen)),
          ],
        ],
      ),
    );
  }

  Widget _codeResultCard(Map<String, String> result) {
    final code = result['code'] ?? '';
    final output = result['output'] ?? '';
    final error = result['error'] ?? '';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border.all(color: JeonColors.borderSoft),
        borderRadius: BorderRadius.circular(JeonRadius.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (code.isNotEmpty)
            SelectableText(code,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: JeonColors.ink, height: 1.4)),
          if (output.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 2),
              child: Text('Output', style: TextStyle(fontSize: 10, color: JeonColors.inkFaint, fontWeight: FontWeight.w600)),
            ),
            SelectableText(output,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: _analysisGreen, height: 1.4)),
          ],
          if (error.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 2),
              child: Text('Error', style: TextStyle(fontSize: 10, color: JeonColors.danger, fontWeight: FontWeight.w600)),
            ),
            SelectableText(error,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: JeonColors.danger, height: 1.4)),
          ],
        ],
      ),
    );
  }

  Widget _autoLearnBanner(String skillName) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF123524),
          border: Border.all(color: _analysisGreen),
          borderRadius: BorderRadius.circular(JeonRadius.small),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text("🧠 AutoLearn: Skill baru disimpan — '$skillName'",
                  style: const TextStyle(
                      fontSize: 11.5, color: _analysisGreen, fontWeight: FontWeight.w600, height: 1.3)),
            ),
            if (onViewAutoLearnSkill != null) ...[
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onViewAutoLearnSkill,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: _analysisGreen),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('Lihat',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _analysisGreen)),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _pluginsUsedBadge(List<String> ids) => Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension_outlined, size: 11, color: JeonColors.inkFaint),
            const SizedBox(width: 4),
            Flexible(
              child: Text('via ${ids.map(_prettifyPluginId).join(', ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: JeonColors.inkFaint, fontStyle: FontStyle.italic)),
            ),
          ],
        ),
      );

  String _prettifyPluginId(String id) =>
      id.split('_').where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

  Future<void> _openUrl(String url) async {
    try {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Link rusak/tidak bisa dibuka — biarkan, teks URL tetap terlihat.
    }
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

/// Typing indicator premium — avatar "J" hijau + bubble abu-abu dengan 3
/// titik bouncing (delay 0.2s antar titik) dan label kecil di bawahnya.
/// Widget sendiri (bukan bagian dalam ChatBubble) biar animasinya tidak
/// memicu rebuild bubble-bubble lain, dan responsive lebar mobile/desktop.
class _PremiumTypingBubble extends StatefulWidget {
  const _PremiumTypingBubble();

  @override
  State<_PremiumTypingBubble> createState() => _PremiumTypingBubbleState();
}

class _PremiumTypingBubbleState extends State<_PremiumTypingBubble> with TickerProviderStateMixin {
  static const _dotCount = 3;
  static const _bounceHeight = 5.0;

  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _bounces;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      _dotCount,
      (_) => AnimationController(vsync: this, duration: const Duration(milliseconds: 600)),
    );
    _bounces = _controllers
        .map((c) => Tween<double>(begin: 0, end: -_bounceHeight)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)))
        .toList();
    for (var i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: 200 * i), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final horizontalPadding = isMobile ? 12.0 : 16.0;

    final avatar = Container(
      width: 28,
      height: 28,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [JeonColors.accent, JeonColors.accentDim],
        ),
        boxShadow: [BoxShadow(color: JeonColors.accentGlow, blurRadius: 8)],
      ),
      alignment: Alignment.center,
      child: const Text('J',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF04150A))),
    );

    final bubble = Flexible(
      child: Container(
        constraints: BoxConstraints(maxWidth: isMobile ? screenWidth * 0.85 : 520),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: horizontalPadding * 0.7),
        decoration: BoxDecoration(
          color: JeonColors.surface2,
          border: Border.all(color: JeonColors.borderSoft),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(JeonRadius.bubble),
            topRight: Radius.circular(JeonRadius.bubble),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(JeonRadius.bubble),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_dotCount, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: AnimatedBuilder(
                    animation: _bounces[i],
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, _bounces[i].value),
                      child: child,
                    ),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: JeonColors.accent),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 6),
            const Text('Sedang berpikir & mengeksekusi...',
                style: TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [avatar, const SizedBox(width: 10), bubble],
      ),
    );
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
