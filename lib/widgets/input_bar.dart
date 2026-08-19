import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/api_service.dart' show ModelOption;
import '../theme.dart';

/// Bottom input bar JeonChat — satu baris pill minimal:
/// [+] [Ask JeonChat...] [model ▾] [🎤] [kirim / mode-suara].
/// Semua interaksi murni-UI (dikte, popover "+", pilihan model, textfield)
/// hidup di sini; aksi yang perlu mengubah percakapan/panggil API dikirim
/// balik ke parent lewat callback. Fitur tambahan (upload dokumen, analisis
/// gambar, buat gambar/video/suara, cari web, riset, code interpreter,
/// skills) semuanya di menu "+" — tidak lagi jadi ikon terpisah di toolbar,
/// biar bar tetap satu baris & minimal.
class JeonChatInputBar extends StatefulWidget {
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

  /// Model buat dropdown — dari GET /models 'options' atau fallback (lihat
  /// ApiService.fallbackModelOptions), diambil parent supaya input_bar tetap
  /// murni UI (tidak panggil ApiService langsung).
  final List<ModelOption> modelOptions;

  /// Gambar dipilih & di-base64-encode di sini (dari menu "+" → "Analisis
  /// Gambar"), tapi panggilan API + mutasi pesan tetap tanggung jawab parent
  /// (lewat callback ini).
  final void Function(String base64Image, String mimeType) onAnalyzeImage;

  /// Dialog cari web di menu "+" → "Cari di Web" — hasil terstruktur
  /// (beda dari "Cari di Web" versi lama yang lewat agent).
  final ValueChanged<String> onWebSearch;

  /// "Upload Dokumen" di menu "+" — teks file sudah dibaca (UTF-8) di sini.
  final void Function(String name, String text) onUploadDoc;

  /// "Code Interpreter" di menu "+" — parent yang push route-nya, biar bisa
  /// lewat auth gate dulu kayak Library/Plugins.
  final VoidCallback? onOpenCodeInterpreter;

  /// "Skills" di menu "+" — buka halaman Custom Skills (parent yang push, auth gate).
  final VoidCallback? onOpenSkills;

  /// Rekaman mic (base64, format PCM16) dikirim ke parent buat ditranskrip
  /// lewat ApiService.speechToText() — hasilnya diisi balik ke text field.
  final Future<String> Function(String base64Audio) onSpeechToText;

  /// Toggle "Voice mode" (biru saat aktif) — state disimpan parent karena
  /// dipakai buat memutuskan apakah SETIAP balasan AI (bukan cuma dari mode
  /// dengar sekali via [onVoiceModeResult]) otomatis dibacakan lewat /tts.
  /// Redesign bar input jadi satu baris minimal tidak lagi punya tombol
  /// sendiri untuk ini — field dipertahankan biar parent (chat_screen.dart)
  /// tetap kompatibel tanpa perlu diubah.
  final bool voiceModeEnabled;
  final VoidCallback? onToggleVoiceMode;

  const JeonChatInputBar({
    super.key,
    required this.onSend,
    required this.onGenerateImage,
    required this.onSearchWeb,
    required this.onDeepResearch,
    required this.onGenerateAudio,
    required this.onGenerateVideo,
    required this.onVoiceModeResult,
    required this.modelOptions,
    required this.onAnalyzeImage,
    required this.onWebSearch,
    required this.onUploadDoc,
    required this.onSpeechToText,
    this.activePluginCount = 0,
    this.onOpenPlugins,
    this.onOpenCodeInterpreter,
    this.onOpenSkills,
    this.voiceModeEnabled = false,
    this.onToggleVoiceMode,
  });

  @override
  State<JeonChatInputBar> createState() => _JeonChatInputBarState();
}

class _JeonChatInputBarState extends State<JeonChatInputBar> {
  static const _selectedModelPrefsKey = 'selected_model';

  final _controller = TextEditingController();
  final _textFocusNode = FocusNode();
  bool _hasText = false;
  ModelOption? _selectedModel;
  String? _pendingSelectedValue;

  ModelOption get _selected =>
      _selectedModel ??
      widget.modelOptions.firstWhere((o) => o.label == 'High', orElse: () => widget.modelOptions.first);

  // ---- Voice mode (🔵) — tetap dikte on-device (speech_to_text), tidak diubah. ----
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  // ---- Tombol mic (dikte) — rekam via `record`, transkrip server-side
  // lewat ApiService.speechToText() (STEP 3). ----
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSub;
  final List<int> _recordedBytes = [];
  bool _recording = false;
  bool _sttLoading = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _initSpeech();
    _restoreSelectedModel();
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
      // Mic tidak tersedia/diizinkan — tombol voice mode otomatis nonaktif.
    }
  }

  Future<void> _restoreSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_selectedModelPrefsKey);
    if (saved == null || !mounted) return;
    _pendingSelectedValue = saved;
    _applyPendingSelectedModel();
  }

  void _applyPendingSelectedModel() {
    final pending = _pendingSelectedValue;
    if (pending == null) return;
    final match = widget.modelOptions.where((o) => o.value == pending);
    if (match.isNotEmpty) {
      setState(() {
        _selectedModel = match.first;
        _pendingSelectedValue = null;
      });
    }
  }

  @override
  void didUpdateWidget(covariant JeonChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // modelOptions kadang baru siap (fetch dari /models) setelah initState —
    // coba cocokkan lagi preferensi tersimpan begitu daftar model berubah.
    if (_pendingSelectedValue != null) _applyPendingSelectedModel();
  }

  @override
  void dispose() {
    _controller.dispose();
    _textFocusNode.dispose();
    _speech.stop();
    _recordSub?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _submit([String? preset]) {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;
    widget.onSend(text, _selected.value);
    _controller.clear();
  }

  /// Tap = mulai rekam, tap lagi = berhenti & transkrip via speechToText().
  Future<void> _toggleMic() async {
    if (_sttLoading) return;
    if (_recording) {
      await _stopRecordingAndTranscribe();
      return;
    }
    await _startRecording();
  }

  Future<void> _startRecording() async {
    try {
      if (!await _audioRecorder.hasPermission()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Izin microphone ditolak/tidak tersedia')),
        );
        return;
      }
      _recordedBytes.clear();
      final stream = await _audioRecorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
      );
      _recordSub = stream.listen((chunk) => _recordedBytes.addAll(chunk));
      if (!mounted) return;
      setState(() => _recording = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mulai rekam: $e')));
    }
  }

  Future<void> _stopRecordingAndTranscribe() async {
    try {
      await _audioRecorder.stop();
    } catch (_) {
      // Sudah berhenti/tidak sempat mulai — lanjut proses apa yang sudah terekam.
    }
    await _recordSub?.cancel();
    _recordSub = null;
    if (!mounted) return;
    setState(() => _recording = false);
    if (_recordedBytes.isEmpty) return;

    setState(() => _sttLoading = true);
    try {
      final base64Audio = base64Encode(_recordedBytes);
      final text = await widget.onSpeechToText(base64Audio);
      if (!mounted) return;
      if (text.trim().isNotEmpty) {
        _controller.text = text.trim();
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal transkrip suara: $e')));
    } finally {
      if (mounted) setState(() => _sttLoading = false);
    }
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

  /// "Analisis Gambar" di menu "+" — pilih gambar, baca sebagai base64,
  /// kirim ke parent buat ditampilkan sebagai bubble user + dianalisis
  /// lewat analyzeImage().
  Future<void> _pickAndAnalyzeImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final base64Image = base64Encode(bytes);
      widget.onAnalyzeImage(base64Image, _mimeFromName(picked.name));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memilih gambar: $e')),
      );
    }
  }

  String _mimeFromName(String name) {
    final ext = name.contains('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : 'jpg';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  /// "Upload Dokumen" — baca isi file sebagai teks UTF-8 lalu kirim ke
  /// parent buat di-upload via uploadDoc() (RAG).
  Future<void> _uploadDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak bisa membaca isi file ini')),
        );
        return;
      }
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File bukan teks (bukan UTF-8) — tidak bisa dibaca sebagai dokumen')),
        );
        return;
      }
      widget.onUploadDoc(file.name, text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal upload dokumen: $e')),
      );
    }
  }

  /// "Cari di Web" di menu "+" — dialog input query lalu diteruskan ke
  /// parent (webSearch(), hasil terstruktur).
  Future<void> _showWebSearchDialog() async {
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
            const Text('Cari di Web', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 1,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
              decoration: InputDecoration(
                hintText: 'Cari di web...',
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
                child: const Text('Cari', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
    final query = result?.trim();
    if (query == null || query.isEmpty) return;
    widget.onWebSearch(query);
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
            _plusMenuTile(Icons.upload_file_outlined, 'Upload Dokumen', onTap: () {
              Navigator.of(sheetContext).pop();
              _uploadDocument();
            }),
            _plusMenuTile(Icons.image_search_rounded, 'Analisis Gambar', onTap: () {
              Navigator.of(sheetContext).pop();
              _pickAndAnalyzeImage();
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
              _showWebSearchDialog();
            }),
            _plusMenuTile(Icons.science_outlined, 'Riset Mendalam', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Riset Mendalam', 'Topik riset apa?', widget.onDeepResearch);
            }),
            _plusMenuTile(Icons.code_rounded, 'Code Interpreter', onTap: () {
              Navigator.of(sheetContext).pop();
              widget.onOpenCodeInterpreter?.call();
            }),
            _plusMenuTile(Icons.auto_awesome_outlined, 'Skills', onTap: () {
              Navigator.of(sheetContext).pop();
              widget.onOpenSkills?.call();
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
          if (_recording)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _RecordingWaveform(),
                  const SizedBox(width: 8),
                  const Text('Mendengarkan...',
                      style: TextStyle(fontSize: 12, color: JeonColors.accent, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
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
                  // GestureDetector translucent (bukan opaque/AbsorbPointer) di
                  // sini HANYA menambah jaminan requestFocus() saat area ini
                  // ditap — tidak menelan/menghalangi gesture asli TextField
                  // sendiri (yang tetap menangani penempatan kursor normal).
                  // Fix bug "cursor tidak bisa muncul" di web mode mobile.
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _textFocusNode.requestFocus(),
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
                        focusNode: _textFocusNode,
                        autofocus: false,
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
                ),
                const SizedBox(width: 4),
                _modelDropdown(),
                const SizedBox(width: 2),
                IconButton(
                  icon: _sttLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: JeonColors.accent),
                        )
                      : Icon(
                          _recording ? Icons.mic : Icons.mic_none_rounded,
                          size: 19,
                          color: _recording ? JeonColors.accent : JeonColors.inkFaint,
                        ),
                  tooltip: _recording ? 'Berhenti rekam' : 'Dikte suara (rekam)',
                  onPressed: _sttLoading ? null : _toggleMic,
                ),
                const SizedBox(width: 2),
                if (_hasText)
                  Container(
                    decoration: const BoxDecoration(color: JeonColors.accent, shape: BoxShape.circle),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded, size: 17, color: Color(0xFF04150A)),
                      onPressed: () => _submit(),
                    ),
                  )
                else
                  Container(
                    decoration: const BoxDecoration(color: JeonColors.accent, shape: BoxShape.circle),
                    child: IconButton(
                      icon: const Icon(Icons.graphic_eq_rounded, size: 17, color: Color(0xFF04150A)),
                      tooltip: 'Mode suara',
                      onPressed: _startVoiceMode,
                    ),
                  ),
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

  /// Dropdown model tanpa kotak — cuma teks "label ▾" (+ emoji kecil kalau
  /// ada), biar bar input tetap terasa satu baris yang bersih.
  Widget _modelDropdown() {
    final selected = _selected;
    return PopupMenuButton<ModelOption>(
      initialValue: selected,
      color: JeonColors.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JeonRadius.small),
        side: const BorderSide(color: JeonColors.border),
      ),
      onSelected: (v) {
        setState(() => _selectedModel = v);
        SharedPreferences.getInstance().then((prefs) => prefs.setString(_selectedModelPrefsKey, v.value));
      },
      itemBuilder: (context) => widget.modelOptions
          .map((o) => PopupMenuItem(
                value: o,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (o.emoji.isNotEmpty) ...[
                      Text(o.emoji, style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      o.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: o.value == selected.value ? JeonColors.accent : JeonColors.ink,
                      ),
                    ),
                  ],
                ),
              ))
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected.emoji.isNotEmpty) ...[
              Text(selected.emoji, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 3),
            ],
            Text(selected.label,
                style: const TextStyle(fontSize: 12.5, color: JeonColors.inkMuted, fontWeight: FontWeight.w600)),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 14, color: JeonColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Waveform sederhana (4 bar animasi, tanpa dependency tambahan) — dipakai
/// sebagai indikator visual di samping teks "Mendengarkan..." saat rekaman
/// mic sedang berjalan.
class _RecordingWaveform extends StatefulWidget {
  const _RecordingWaveform();

  @override
  State<_RecordingWaveform> createState() => _RecordingWaveformState();
}

class _RecordingWaveformState extends State<_RecordingWaveform> with TickerProviderStateMixin {
  static const _barCount = 4;
  late final List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      _barCount,
      (_) => AnimationController(vsync: this, duration: const Duration(milliseconds: 450)),
    );
    for (var i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: 90 * i), () {
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_barCount, (i) {
        return AnimatedBuilder(
          animation: _controllers[i],
          builder: (context, child) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 3,
            height: 6 + _controllers[i].value * 10,
            decoration: BoxDecoration(color: JeonColors.accent, borderRadius: BorderRadius.circular(2)),
          ),
        );
      }),
    );
  }
}
