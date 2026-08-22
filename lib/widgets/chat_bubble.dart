import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../models/message.dart';
import '../theme.dart';
import 'audio_message_player.dart';
import 'tool_card.dart';
import 'video_message_player.dart';

const _thinkingPlaceholder = 'JeonAI Sedang Berpikir Lalu Eksekusi Mohon Ditunggu';
const _analysisGreen = Color(0xFF2ECC71);
const _feedbackUpGreen = Color(0xFF2EA043);

/// Label mentah yang disisipkan backend saat sebuah skill otonom (Skill &
/// Plugin Orchestrator) ikut menyusun balasan ini — dideteksi lalu
/// dilucuti dari teks yang ditampilkan, diganti badge visual (lihat
/// _autonomousSkillBadge).
const _autonomousSkillMarker = '[SKILL OTOMATIS TERDETEKSI]';

class ChatBubble extends StatefulWidget {
  final ChatMessage message;

  /// Tombol "Lihat" di banner AutoLearn — buka SkillListScreen. Null kalau
  /// pemanggil tidak menyediakan (banner tetap tampil, tombolnya disembunyikan).
  final VoidCallback? onViewAutoLearnSkill;

  /// Buka layar edit gambar (AI image editing) untuk [url]. Null kalau tidak
  /// disediakan (tombol "Edit" di fullscreen disembunyikan).
  final void Function(String url)? onEditImage;

  /// Edit pesan USER + kirim ulang (Fitur "Edit pesan") — dipanggil dengan
  /// pesan asli & teks baru; parent (chat_screen.dart) yang motong history
  /// dari titik itu lalu kirim ulang sebagai pesan baru. Null = tombol edit
  /// disembunyikan.
  final void Function(ChatMessage message, String newText)? onEditUserMessage;

  /// Regenerate jawaban AI (Fitur "Regenerate") — dipanggil dengan bubble AI
  /// yang mau digenerate ulang; parent yang hapus dari history & kirim ulang
  /// pertanyaan sebelumnya. Null = tombol regenerate disembunyikan.
  final void Function(ChatMessage message)? onRegenerateAiMessage;

  /// Tombol "Buka Panel" di kartu artifact (fase 3.1) — buka ArtifactPanel
  /// TANPA auto-run. Null = kartu artifact tidak dirender sama sekali.
  final void Function(Artifact artifact)? onOpenArtifact;

  /// Tombol "▶ Jalankan" di kartu artifact (khusus type=code) — buka
  /// ArtifactPanel & langsung eksekusi. Null = tombol Jalankan disembunyikan
  /// (kartu tetap tampil kalau [onOpenArtifact] tersedia).
  final void Function(Artifact artifact)? onRunArtifact;

  /// Rating feedback (👍/👎) untuk balasan AI ini saat ini — 'up'/'down'/null
  /// (belum dinilai). Dikelola parent lewat _feedbackRatings (fase 4.1),
  /// null kalau belum ada rating untuk pesan ini.
  final String? feedbackRating;

  /// Kirim/hapus rating (fase 4.1) — dipanggil dengan bubble AI yang dinilai
  /// & rating baru: 'up'/'down' = kirim rating (ganti kalau beda dari
  /// sebelumnya), null = hapus rating yang sudah ada (toggle-off). Parent
  /// yang panggil ApiService.sendFeedback/deleteFeedback lalu update state.
  /// Null = tombol thumbs disembunyikan.
  final void Function(ChatMessage message, String? rating)? onFeedback;

  /// Branching (fase 4.3) — buat percabangan percakapan mulai dari bubble AI
  /// ini (copy riwayat sampai pesan ini ke percakapan baru). Null = tombol
  /// 🌿 disembunyikan.
  final void Function(ChatMessage message)? onBranchMessage;

  const ChatBubble({
    super.key,
    required this.message,
    this.onViewAutoLearnSkill,
    this.onEditImage,
    this.onEditUserMessage,
    this.onRegenerateAiMessage,
    this.onOpenArtifact,
    this.onRunArtifact,
    this.feedbackRating,
    this.onFeedback,
    this.onBranchMessage,
  });

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  // Deteksi URL media (gambar/video) yang disisipkan AI langsung di teks
  // balasan — baik lewat sintaks markdown image maupun URL polos.
  static final _markdownImageRegex = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');
  static final _directImageUrlRegex =
      RegExp(r'https?://[^\s\)\]]+\.(jpg|jpeg|png|gif|webp|bmp)(\?[^\s]*)?', caseSensitive: false);
  static final _directVideoUrlRegex =
      RegExp(r'https?://[^\s\)\]]+\.(mp4|mov|avi|mkv|webm)(\?[^\s]*)?', caseSensitive: false);

  // ---- Edit pesan user (lihat _startEdit/_cancelEdit/_confirmEdit) ----
  bool _editing = false;
  TextEditingController? _editController;

  @override
  void dispose() {
    _editController?.dispose();
    super.dispose();
  }

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

  void _startEdit() {
    setState(() {
      _editing = true;
      _editController = TextEditingController(text: widget.message.text);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _editController?.dispose();
      _editController = null;
    });
  }

  void _confirmEdit() {
    final text = _editController?.text.trim() ?? '';
    if (text.isEmpty) return;
    widget.onEditUserMessage?.call(widget.message, text);
    setState(() {
      _editing = false;
      _editController?.dispose();
      _editController = null;
    });
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disalin ke clipboard'), duration: Duration(seconds: 1)),
    );
  }

  /// Tap thumbs up/down (fase 4.1) — tap ulang tombol yang sudah aktif =
  /// toggle-off (hapus rating), tap tombol lain/pertama kali = set rating.
  void _handleFeedback(String rating) {
    final next = widget.feedbackRating == rating ? null : rating;
    widget.onFeedback?.call(widget.message, next);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isUser = message.isUser;
    final isThinking = !isUser && message.text == _thinkingPlaceholder;
    if (isThinking) {
      return const _PremiumTypingBubble();
    }
    final media = isUser ? null : _extractMediaUrl(message.text);
    // Kalau ada media, jangan tampilkan markdown/URL mentahnya lagi di teks —
    // gambar/videonya sudah dirender di atas, teks mentah cuma bikin duplikat
    // (video sebelumnya kelewat di sini — URL .mp4 mentah tetap kelihatan
    // dobel di bawah player-nya).
    String cleanText = message.text;
    if (media != null) {
      cleanText = message.text.replaceAll(_markdownImageRegex, '').trim();
      cleanText = cleanText.replaceAll(_directImageUrlRegex, '').trim();
      cleanText = cleanText.replaceAll(_directVideoUrlRegex, '').trim();
    }
    // Skill & Plugin Orchestrator — backend menyisipkan label mentah ini
    // kalau balasan disusun lewat skill otonom; dilucuti dari teks, diganti
    // badge visual di atas bubble (lihat _autonomousSkillBadge).
    final hasAutonomousSkill = !isUser && cleanText.contains(_autonomousSkillMarker);
    if (hasAutonomousSkill) {
      cleanText = cleanText.replaceAll(_autonomousSkillMarker, '').trim();
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
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: isUser ? 11 : 13),
        decoration: BoxDecoration(
          color: isUser
              ? JeonColors.accent.withValues(alpha: 0.22)
              : message.isAnalysis
                  ? _analysisGreen.withValues(alpha: 0.14)
                  : JeonColors.surface3,
          border: Border.all(
            color: isUser
                ? JeonColors.accent.withValues(alpha: 0.4)
                : message.isAnalysis
                    ? _analysisGreen.withValues(alpha: 0.4)
                    : JeonColors.borderSoft,
          ),
          borderRadius: isUser
              ? const BorderRadius.only(
                  topLeft: Radius.circular(JeonRadius.bubble),
                  topRight: Radius.circular(JeonRadius.bubble),
                  bottomLeft: Radius.circular(JeonRadius.bubble),
                  bottomRight: Radius.circular(4),
                )
              : const BorderRadius.all(Radius.circular(JeonRadius.bubble)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasAutonomousSkill)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _autonomousSkillBadge(),
              ),
            if (!isUser)
              const Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Text(
                  'JEON Chat',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: JeonColors.inkMuted,
                  ),
                ),
              ),
            if (message.docSource != null) _docSourceBadge(message.docSource!),
            if (media != null)
              media.isVideo ? _videoUrlPlaceholder(media.url) : _markdownImagePreview(context, media.url),
            if (isUser && _editing)
              _editField()
            else if (cleanText.isNotEmpty)
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
            if (message.artifacts.isNotEmpty && widget.onOpenArtifact != null)
              ...message.artifacts.map(_artifactCard),
            if (message.toolCall != null) ToolCardWidget(toolCall: message.toolCall!),
            if (message.imageUrl != null) _imagePreview(context, message.imageUrl!),
            if (message.audioUrl != null) AudioMessagePlayer(url: message.audioUrl!),
            if (message.videoUrl != null) _videoCard(message.videoUrl!),
            if (message.filePath != null) _fileCard(message.filePath!),
            if (message.attachmentUrl != null)
              _attachmentCard(message.attachmentUrl!, message.attachmentName ?? 'File'),
            if (message.searchResults != null && message.searchResults!.isNotEmpty)
              _searchResultsList(message.searchResults!),
            if (message.researchSources != null && message.researchSources!.isNotEmpty)
              _researchSourcesList(message.researchSources!),
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
                  ],
                ),
              ),
          ],
        ),
          ),
          if (!_editing) _actionRow(isUser),
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

  /// Bubble user berubah jadi ini saat _editing — TextField isi pesan asli +
  /// tombol Batal (X)/Kirim Ulang (✓).
  Widget _editField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _editController,
          autofocus: true,
          maxLines: null,
          style: const TextStyle(fontSize: 13.4, color: JeonColors.ink, height: 1.4),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onSubmitted: (_) => _confirmEdit(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _cancelEdit,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close_rounded, size: 18, color: JeonColors.inkFaint),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: _confirmEdit,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: JeonColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 18, color: Color(0xFF04150A)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Baris ikon kecil di bawah bubble: pensil-edit (user) atau copy+regenerate
  /// (AI) — selalu terlihat (bukan hover-only) supaya konsisten di
  /// touch & desktop, tidak butuh state hover terpisah.
  Widget _actionRow(bool isUser) {
    if (isUser) {
      if (widget.onEditUserMessage == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 3, right: 2),
        child: Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: _startEdit,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.edit_outlined, size: 14, color: JeonColors.inkFaint),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 3, left: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _copyToClipboard(widget.message.text),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.copy_outlined, size: 14, color: JeonColors.inkFaint),
            ),
          ),
          if (widget.onRegenerateAiMessage != null)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => widget.onRegenerateAiMessage!(widget.message),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.refresh_rounded, size: 14, color: JeonColors.inkFaint),
              ),
            ),
          if (widget.onBranchMessage != null)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => widget.onBranchMessage!(widget.message),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.account_tree_outlined,
                  size: 14,
                  color: JeonColors.inkFaint,
                ),
              ),
            ),
          if (widget.onFeedback != null) ...[
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _handleFeedback('up'),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  widget.feedbackRating == 'up' ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                  size: 14,
                  color: widget.feedbackRating == 'up' ? _feedbackUpGreen : JeonColors.inkFaint,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _handleFeedback('down'),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  widget.feedbackRating == 'down' ? Icons.thumb_down_rounded : Icons.thumb_down_outlined,
                  size: 14,
                  color: widget.feedbackRating == 'down' ? JeonColors.danger : JeonColors.inkFaint,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _markdownImagePreview(BuildContext context, String url) => RepaintBoundary(
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
              onTap: () => _openFullscreenImage(context, url),
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

  /// Balasan disusun lewat Skill & Plugin Orchestrator (backend sisipkan
  /// [_autonomousSkillMarker]) — badge hijau/biru neon khas JEON, robot icon.
  Widget _autonomousSkillBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_analysisGreen.withValues(alpha: 0.22), JeonColors.accent.withValues(alpha: 0.22)],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _analysisGreen.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_toy_rounded, size: 12, color: _analysisGreen),
            const SizedBox(width: 4),
            Text('Autonomous Skill Active',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _analysisGreen.withValues(alpha: 0.95))),
          ],
        ),
      );

  Widget _imagePreview(BuildContext context, String url) => RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GestureDetector(
              onTap: () => _openFullscreenImage(context, url),
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
        ),
      );

  /// Buka gambar fullscreen (zoom pinch/scroll + tombol unduh). Dipanggil saat
  /// user mengetuk thumbnail gambar hasil generate/markdown di bubble chat.
  void _openFullscreenImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (dialogContext) => Stack(
        children: [
          // Area tappable untuk menutup dialog
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 5.0,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    width: 120,
                    height: 120,
                    child: Center(child: CircularProgressIndicator(color: Colors.white)),
                  );
                },
                errorBuilder: (context, error, stackTrace) => const Text(
                  'Gambar gagal dimuat',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          // Tombol tutup (kiri atas)
          Positioned(
            top: 40,
            left: 16,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ),
          // Tombol unduh (kanan atas)
          Positioned(
            top: 40,
            right: 16,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.download, color: Colors.white, size: 26),
                onPressed: () => _openUrl(url),
              ),
            ),
          ),
          // Toolbar bawah ala referensi: Edit + Hapus (hapus = buka gambar asli)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.onEditImage != null)
                      _viewerToolButton(
                        icon: Icons.brush_outlined,
                        label: 'Edit',
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          widget.onEditImage!(url);
                        },
                      ),
                    const SizedBox(width: 28),
                    _viewerToolButton(
                      icon: Icons.open_in_new,
                      label: 'Buka',
                      onTap: () => _openUrl(url),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewerToolButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Colors.white12,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _videoCard(String url) {
    return VideoMessagePlayer(url: url);
  }

  /// Kartu artifact (fase 3.1, kode/dokumen panjang) — isi lengkapnya cuma
  /// dibuka lewat ArtifactPanel (widget.onOpenArtifact), bukan ditampilkan
  /// mentah di bubble (raw ``` fence sudah dibuang di chat_screen.dart).
  Widget _artifactCard(Artifact artifact) {
    final isCode = artifact.type == 'code';
    final lineCount = artifact.content.isEmpty ? 0 : '\n'.allMatches(artifact.content).length + 1;
    final title = artifact.title.trim().isNotEmpty ? artifact.title.trim() : (isCode ? 'Kode' : 'Dokumen');
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JeonColors.surface3,
        border: Border.all(color: JeonColors.borderSoft),
        borderRadius: BorderRadius.circular(JeonRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: JeonColors.accentGlow, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: isCode
                ? const Icon(Icons.code, size: 18, color: JeonColors.accent)
                : const Text('📄', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                const SizedBox(height: 2),
                Text(
                  [
                    if (artifact.languageLabel.isNotEmpty) artifact.languageLabel,
                    '$lineCount baris',
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (isCode && widget.onRunArtifact != null)
                      _artifactButton('▶ Jalankan', onTap: () => widget.onRunArtifact!(artifact)),
                    _artifactButton('Buka Panel', onTap: () => widget.onOpenArtifact!(artifact)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _artifactButton(String label, {required VoidCallback onTap}) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: JeonColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: JeonColors.accent)),
        ),
      );

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

  /// Lampiran yang DIUPLOAD USER sendiri (menu "+" → Upload File/Dokumen
  /// atau Tambah dari Library) — beda dari [_fileCard] yang khusus file
  /// buatan agent, jadi wordingnya "lampiran dari kamu", bukan "dibuat agent".
  /// Bisa diketuk buat buka filenya di tab baru.
  Widget _attachmentCard(String url, String name) {
    return InkWell(
      borderRadius: BorderRadius.circular(JeonRadius.small),
      onTap: () => launchUrlString(url, mode: LaunchMode.externalApplication),
      child: Container(
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
              child: const Icon(Icons.attach_file_rounded, size: 16, color: JeonColors.accent),
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
                  const Text('Lampiran · ketuk untuk buka',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: JeonColors.inkFaint)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchResultsList(List<Map<String, String>> results) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sourceCountBadge(results.length),
            const SizedBox(height: 6),
            ...results.map(_searchResultTile),
          ],
        ),
      );

  /// Daftar sumber riset mendalam (dari /research) — kartu "Sumber [n]"
  /// dengan judul, snippet, dan link clickable, konsisten dengan gaya
  /// [._searchResultTile] namun dengan nomor urut di depan.
  Widget _researchSourcesList(List<Map<String, String>> sources) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sourceCountBadge(sources.length),
            const SizedBox(height: 6),
            ...List.generate(sources.length, (i) => _researchSourceTile(i + 1, sources[i])),
          ],
        ),
      );

  /// Indikator "diverifikasi dari N sumber" — dipakai bareng oleh hasil
  /// "Cari di Web" (searchResults) dan "Riset Mendalam" (researchSources),
  /// biar user langsung lihat jawabannya ditopang berapa referensi tanpa
  /// perlu menghitung kartu sumber satu-satu.
  Widget _sourceCountBadge(int count) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_outlined, size: 13, color: JeonColors.accent),
          const SizedBox(width: 4),
          Text(
            count == 1 ? 'Diverifikasi dari 1 sumber' : 'Diverifikasi dari $count sumber',
            style: const TextStyle(fontSize: 11, color: JeonColors.inkMuted, fontWeight: FontWeight.w700),
          ),
        ],
      );

  Widget _researchSourceTile(int n, Map<String, String> r) {
    final title = (r['title'] ?? '').trim().isNotEmpty ? r['title']! : (r['url'] ?? 'Sumber $n');
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 1, right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: JeonColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('[$n]',
                      style: const TextStyle(fontSize: 11, color: JeonColors.accent, fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 13,
                          color: JeonColors.ink,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
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
            if (widget.onViewAutoLearnSkill != null) ...[
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: widget.onViewAutoLearnSkill,
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
