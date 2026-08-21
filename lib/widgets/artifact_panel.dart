import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';

import '../models/message.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/file_download.dart';

/// Bahasa artifact → key bahasa yang dikenal package:highlight (lihat
/// package:highlight/languages/all.dart — TIDAK ada key 'html' literal,
/// html/xml pakai 'xml' sesuai konvensi highlight.js).
const _highlightLanguageMap = {
  'python': 'python',
  'py': 'python',
  'dart': 'dart',
  'javascript': 'javascript',
  'js': 'javascript',
  'jsx': 'javascript',
  'typescript': 'typescript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'html': 'xml',
  'xml': 'xml',
  'css': 'css',
  'scss': 'scss',
  'less': 'less',
  'java': 'java',
  'kotlin': 'kotlin',
  'kt': 'kotlin',
  'swift': 'swift',
  'go': 'go',
  'golang': 'go',
  'rust': 'rust',
  'rs': 'rust',
  'c': 'cpp',
  'cpp': 'cpp',
  'c++': 'cpp',
  'csharp': 'cs',
  'cs': 'cs',
  'php': 'php',
  'ruby': 'ruby',
  'rb': 'ruby',
  'sql': 'sql',
  'bash': 'bash',
  'shell': 'bash',
  'sh': 'bash',
  'json': 'json',
  'yaml': 'yaml',
  'yml': 'yaml',
  'markdown': 'markdown',
  'md': 'markdown',
};

/// Bahasa artifact → ekstensi file untuk Download (fase 3.1).
const _extByLanguage = {
  'python': 'py',
  'py': 'py',
  'dart': 'dart',
  'javascript': 'js',
  'js': 'js',
  'jsx': 'jsx',
  'typescript': 'ts',
  'ts': 'ts',
  'tsx': 'tsx',
  'html': 'html',
  'xml': 'xml',
  'css': 'css',
  'scss': 'scss',
  'less': 'less',
  'java': 'java',
  'kotlin': 'kt',
  'kt': 'kt',
  'swift': 'swift',
  'go': 'go',
  'golang': 'go',
  'rust': 'rs',
  'rs': 'rs',
  'c': 'c',
  'cpp': 'cpp',
  'c++': 'cpp',
  'csharp': 'cs',
  'cs': 'cs',
  'php': 'php',
  'ruby': 'rb',
  'rb': 'rb',
  'sql': 'sql',
  'bash': 'sh',
  'shell': 'sh',
  'sh': 'sh',
  'json': 'json',
  'yaml': 'yaml',
  'yml': 'yaml',
};

String _highlightLangOf(String language) => _highlightLanguageMap[language.trim().toLowerCase()] ?? 'plaintext';

String _fileExtOf(String language) => _extByLanguage[language.trim().toLowerCase()] ?? 'txt';

/// Panel artifact (fase 3.1, ala Claude Artifacts/ChatGPT Canvas) — isi
/// murni widget "konten panel"; TIDAK mengurus tampilan split-view vs modal
/// (itu tanggung jawab chat_screen.dart, lihat _openArtifact), supaya widget
/// ini bisa dipakai sama persis di kedua konteks.
class ArtifactPanel extends StatefulWidget {
  final ApiService api;
  final Artifact artifact;
  final VoidCallback onClose;

  /// True kalau dibuka dari tombol "▶ Jalankan" di kartu bubble (bukan
  /// "Buka Panel" biasa) — langsung eksekusi kode begitu panel tampil.
  final bool autoRun;

  const ArtifactPanel({
    super.key,
    required this.api,
    required this.artifact,
    required this.onClose,
    this.autoRun = false,
  });

  @override
  State<ArtifactPanel> createState() => _ArtifactPanelState();
}

class _ArtifactPanelState extends State<ArtifactPanel> {
  late final TextEditingController _controller;
  late String _liveContent;
  bool _editing = false;
  bool _running = false;
  String? _stdout;
  String? _stderr;

  bool get _isCode => widget.artifact.type == 'code';

  String get _title => widget.artifact.title.trim().isNotEmpty
      ? widget.artifact.title.trim()
      : (_isCode ? 'Artifact Kode' : 'Artifact Dokumen');

  int get _lineCount => _liveContent.isEmpty ? 0 : '\n'.allMatches(_liveContent).length + 1;

  @override
  void initState() {
    super.initState();
    _liveContent = widget.artifact.content;
    _controller = TextEditingController(text: _liveContent);
    if (widget.autoRun && _isCode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEdit() => setState(() => _editing = true);

  void _saveEdit() => setState(() {
        _liveContent = _controller.text;
        _editing = false;
      });

  void _cancelEdit() => setState(() {
        _controller.text = _liveContent;
        _editing = false;
      });

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _liveContent));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Disalin ke clipboard'), duration: Duration(seconds: 1)));
  }

  Future<void> _download() async {
    final ext = _isCode ? _fileExtOf(widget.artifact.language) : 'md';
    final base = _title.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_').toLowerCase();
    final filename = '${base.isEmpty ? 'artifact' : base}.$ext';
    if (kIsWeb) {
      downloadTextFile(filename, _liveContent);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$filename terunduh'), duration: const Duration(seconds: 1)));
      return;
    }
    try {
      final bytes = Uint8List.fromList(utf8.encode(_liveContent));
      await Share.shareXFiles([XFile.fromData(bytes, name: filename, mimeType: 'text/plain')]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal download: $e')));
    }
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _stdout = null;
      _stderr = null;
    });
    try {
      // Pola pembacaan respons sama seperti code_screen.dart (Code
      // Interpreter) — backend kadang balas output/stdout/result dan
      // error/stderr, dibaca defensif supaya cocok keduanya.
      final result = await widget.api.runCode(_liveContent);
      if (!mounted) return;
      setState(() {
        final out = (result['output'] ?? result['stdout'] ?? result['result'] ?? '').toString();
        _stdout = out.isEmpty ? null : out;
        final err = result['error'] ?? result['stderr'];
        _stderr = (err == null || err.toString().isEmpty) ? null : err.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _stderr = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF171717),
      child: Column(
        children: [
          _header(),
          Expanded(child: _body()),
          if (_running || _stdout != null || _stderr != null) _outputBox(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
              ),
              _iconAction(Icons.copy_outlined, 'Copy', _copy),
              _iconAction(Icons.download_outlined, 'Download', _download),
              if (_editing) ...[
                _iconAction(Icons.undo_outlined, 'Batal', _cancelEdit),
                _iconAction(Icons.check_circle_outline, 'Simpan', _saveEdit),
              ] else
                _iconAction(Icons.edit_outlined, 'Edit', _startEdit),
              _iconAction(Icons.close, 'Tutup panel', widget.onClose),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: JeonColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_isCode ? 'CODE' : 'DOKUMEN',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: JeonColors.accent, letterSpacing: 0.5)),
              ),
              if (widget.artifact.languageLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(widget.artifact.languageLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: JeonColors.inkFaint)),
                ),
              ],
              const SizedBox(width: 8),
              Text('$_lineCount baris', style: const TextStyle(fontSize: 11.5, color: JeonColors.inkFaint)),
              const Spacer(),
              if (_isCode) _runButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconAction(IconData icon, String tooltip, VoidCallback? onTap) => IconButton(
        icon: Icon(icon, size: 18, color: JeonColors.inkMuted),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      );

  Widget _runButton() => GestureDetector(
        onTap: _running ? null : _run,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: JeonColors.accent, borderRadius: BorderRadius.circular(999)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_running)
                const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF04150A)))
              else
                const Icon(Icons.play_arrow_rounded, size: 14, color: Color(0xFF04150A)),
              const SizedBox(width: 5),
              const Text('Jalankan',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF04150A))),
            ],
          ),
        ),
      );

  Widget _body() {
    if (_editing) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: JeonColors.ink, height: 1.5),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF111418),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      );
    }
    if (_isCode) {
      return Container(
        width: double.infinity,
        color: const Color(0xFF111418),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width),
              child: HighlightView(
                _liveContent,
                language: _highlightLangOf(widget.artifact.language),
                theme: vs2015Theme,
                padding: const EdgeInsets.all(14),
                textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      color: const Color(0xFF111418),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MarkdownBody(
          data: _liveContent,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(fontSize: 13.5, color: JeonColors.ink, height: 1.7),
            h1: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: JeonColors.ink),
            h2: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: JeonColors.ink),
            h3: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: JeonColors.ink),
            strong: const TextStyle(fontWeight: FontWeight.w700, color: JeonColors.ink),
            code: const TextStyle(
                fontFamily: 'monospace', fontSize: 12.5, color: JeonColors.accent, backgroundColor: Color(0xFF1C2128)),
            codeblockDecoration:
                BoxDecoration(color: const Color(0xFF1C2128), borderRadius: BorderRadius.circular(8)),
            listBullet: const TextStyle(fontSize: 13.5, color: JeonColors.ink),
            blockquote: const TextStyle(fontSize: 13.5, color: JeonColors.inkFaint),
            blockquoteDecoration: const BoxDecoration(
              border: Border(left: BorderSide(color: JeonColors.border, width: 3)),
            ),
            a: const TextStyle(color: JeonColors.accent),
            horizontalRuleDecoration: const BoxDecoration(
              border: Border(top: BorderSide(color: JeonColors.border)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _outputBox() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0D10),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: SingleChildScrollView(
        child: _running
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: JeonColors.accent)),
                  SizedBox(width: 8),
                  Text('Menjalankan...', style: TextStyle(fontSize: 12, color: JeonColors.inkFaint)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_stdout != null)
                    SelectableText(_stdout!,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12.5, color: Color(0xFFDCDCDC), height: 1.5)),
                  if (_stderr != null)
                    Padding(
                      padding: EdgeInsets.only(top: _stdout != null ? 8 : 0),
                      child: SelectableText(_stderr!,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12.5, color: JeonColors.danger, height: 1.5)),
                    ),
                ],
              ),
      ),
    );
  }
}
