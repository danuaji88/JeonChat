import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../services/api_service.dart' show ModelOption;
import '../theme.dart';
import '../utils/clipboard_paste.dart';

/// Bottom input bar JeonChat — satu baris pill minimal:
/// [+] [Ask JeonChat...] [model ▾] [🎤] [kirim / mode-suara].
/// Semua interaksi murni-UI (dikte, popover "+", pilihan model, textfield)
/// hidup di sini; aksi yang perlu mengubah percakapan/panggil API dikirim
/// balik ke parent lewat callback. Fitur tambahan (upload dokumen, analisis
/// gambar, buat gambar/video/suara, cari web, riset, code interpreter,
/// skills) semuanya di menu "+" — tidak lagi jadi ikon terpisah di toolbar,
/// biar bar tetap satu baris & minimal.
class JeonChatInputBar extends StatefulWidget {
  /// [attachmentUrl]/[attachmentName]/[attachmentKind] terisi kalau user
  /// pasang lampiran lewat menu "+" (Upload Gambar/Upload File/Tambah dari
  /// Library) sebelum kirim — mirip preview attachment ala WhatsApp/Telegram
  /// (lihat _pendingAttachment & _attachmentPreview di bawah).
  final void Function(String text, String model,
      {String? attachmentUrl, String? attachmentName, String? attachmentKind}) onSend;

  /// Fitur "Stop Generation" — saat true, tombol kirim (panah) berganti jadi
  /// tombol Stop (kotak merah). [onStop] menggugurkan request /chat atau
  /// /agent yang sedang berjalan (lihat _stopGeneration di chat_screen.dart).
  final bool isGenerating;
  final VoidCallback? onStop;

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

  /// "Upload Gambar" & "Upload File/Dokumen" di menu "+" — nama+bytes file
  /// dibaca di sini, parent yang upload lewat ApiService.uploadFile() dan
  /// balikin respons server mentah ({name, url, size, status}).
  final Future<Map<String, dynamic>> Function(String name, List<int> bytes) onUploadAttachment;

  /// "Tambah dari Library" di menu "+" — parent yang panggil GET /library,
  /// balikin daftar item mentah ({name, url, kind, size, uploaded_at}).
  final Future<List<Map<String, dynamic>>> Function() onFetchLibrary;

  /// Kanal drag & drop (Fitur "Attach file di composer") — chat_screen.dart
  /// upload file yang di-drop di area chat lalu dorong hasilnya
  /// ({name, url, size}) ke sini lewat notifier ini, supaya jadi lampiran
  /// pending yang SAMA persis dengan hasil Upload Gambar/Dokumen manual
  /// (satu sumber kebenaran untuk preview+kirim, tidak duplikat UI).
  final ValueListenable<Map<String, dynamic>?>? externalAttachment;

  /// ID percakapan aktif — key SharedPreferences untuk antrean video
  /// terlampir (lihat _pendingVideos), supaya draft lampiran video per
  /// percakapan tidak hilang saat refresh halaman atau pindah chat. Null =
  /// percakapan baru yang belum tersimpan, pakai key draft terpisah.
  final String? conversationId;

  /// Kanal "Upload Video" dari menu "More" (sidebar) — chat_screen.dart
  /// increment nilainya untuk memicu _pickVideoAttachment() dari luar
  /// (tombolnya sendiri sudah dipindah dari menu "+" ke More, lihat
  /// _openMoreMenu di chat_screen.dart). Pola sama dengan
  /// externalPromptText/externalAttachment di atas.
  final ValueListenable<int>? triggerVideoUpload;

  /// Kanal "Coba Skill" (Plugins Store) — chat_screen.dart dorong prompt
  /// contoh ke sini, langsung diisikan ke _controller (kolom chat), bukan
  /// otomatis terkirim. Pola sama dengan [externalAttachment] di atas.
  final ValueListenable<String?>? externalPromptText;

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
    this.isGenerating = false,
    this.onStop,
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
    required this.onUploadAttachment,
    required this.onFetchLibrary,
    this.externalAttachment,
    this.conversationId,
    this.triggerVideoUpload,
    this.externalPromptText,
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
  static const _maxUploadBytes = 50 * 1024 * 1024;

  final _controller = TextEditingController();
  final _textFocusNode = FocusNode();
  bool _hasText = false;
  ModelOption? _selectedModel;
  String? _pendingSelectedValue;

  // ---- Lampiran (Upload Gambar/Upload File/Tambah dari Library) — pending
  // sampai user kirim pesan berikutnya, mirip preview attachment ala
  // WhatsApp/Telegram. ----
  _PendingAttachment? _pendingAttachment;
  bool _attachmentBusy = false;

  // ---- Multi-upload video (maks 5 per pesan) — antrean terpisah dari
  // _pendingAttachment (yang cuma satu slot) karena video sengaja boleh
  // lebih dari satu. Dipersist per conversationId (lihat _loadPendingVideos/
  // _savePendingVideos) supaya tidak hilang saat refresh/pindah chat. ----
  static const _maxPendingVideos = 5;
  static const _pendingVideosPrefsPrefix = 'jeon_pending_videos_';
  List<_PendingAttachment> _pendingVideos = [];
  double? _uploadProgress; // null = tidak sedang upload video
  int _uploadDone = 0;
  int _uploadTotal = 0;

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
    _loadPendingVideos();
    // Paste gambar (Ctrl+V) — no-op di non-web (lihat clipboard_paste_stub.dart).
    listenForImagePaste((name, bytes) => _uploadBytesAndAttach(name, bytes));
    widget.externalAttachment?.addListener(_onExternalAttachment);
    widget.externalPromptText?.addListener(_onExternalPromptText);
    widget.triggerVideoUpload?.addListener(_onTriggerVideoUpload);
  }

  /// "Upload Video" dari menu "More" (lihat widget.triggerVideoUpload) —
  /// memicu file picker video yang sama dengan tombol "+" lama.
  void _onTriggerVideoUpload() => _pickVideoAttachment();

  /// "Coba Skill" dari Plugins Store (lihat widget.externalPromptText) —
  /// prompt contoh diisikan ke kolom chat, TIDAK otomatis terkirim, supaya
  /// user masih bisa review/edit dulu sebelum kirim.
  void _onExternalPromptText() {
    final text = widget.externalPromptText?.value;
    if (text == null || text.isEmpty) return;
    setState(() {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    });
    _textFocusNode.requestFocus();
  }

  /// Drag & drop dari chat_screen.dart (lihat widget.externalAttachment) —
  /// file sudah diupload di sana, di sini cuma dijadikan lampiran pending
  /// yang sama seperti hasil Upload Gambar/Dokumen manual.
  void _onExternalAttachment() {
    final data = widget.externalAttachment?.value;
    if (data == null) return;
    final url = (data['url'] ?? '').toString();
    if (url.isEmpty) return;
    final name = (data['name'] ?? 'File').toString();
    final sizeRaw = data['size'];
    setState(() {
      _pendingAttachment = _PendingAttachment(
        name: name,
        url: url,
        kind: _inferAttachmentKind(name),
        sizeLabel: sizeRaw is num ? _formatAttachmentSize(sizeRaw.toInt()) : null,
      );
    });
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
    // Pindah percakapan — muat ulang antrean video draft milik percakapan
    // yang baru aktif (masing-masing conversationId punya draft sendiri).
    if (oldWidget.conversationId != widget.conversationId) {
      _loadPendingVideos();
    }
  }

  @override
  void dispose() {
    stopListeningForImagePaste();
    widget.externalAttachment?.removeListener(_onExternalAttachment);
    widget.externalPromptText?.removeListener(_onExternalPromptText);
    widget.triggerVideoUpload?.removeListener(_onTriggerVideoUpload);
    _controller.dispose();
    _textFocusNode.dispose();
    _speech.stop();
    _recordSub?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  void _submit([String? preset]) {
    if (widget.isGenerating) return; // Tombol sudah jadi Stop — Enter tidak boleh menembus.
    final text = (preset ?? _controller.text).trim();
    final attachment = _pendingAttachment;
    final videos = _pendingVideos;
    // Boleh kirim lampiran tanpa teks (ala WhatsApp/Telegram), tapi tidak
    // boleh semuanya kosong.
    if (text.isEmpty && attachment == null && videos.isEmpty) return;

    // Tiap video jadi pesan terpisah (reuse pipeline lampiran tunggal yang
    // sudah ada di onSend/chat_screen.dart, bukan bikin jalur baru) — caption
    // cuma nempel di lampiran PERTAMA (attachment gambar/dok kalau ada,
    // kalau tidak video pertama) biar tidak spam teks yang sama berkali-kali.
    var captionUsed = false;
    if (attachment != null) {
      widget.onSend(
        text,
        _selected.value,
        attachmentUrl: attachment.url,
        attachmentName: attachment.name,
        attachmentKind: attachment.kind,
      );
      captionUsed = true;
    }
    for (final video in videos) {
      widget.onSend(
        captionUsed ? '' : text,
        _selected.value,
        attachmentUrl: video.url,
        attachmentName: video.name,
        attachmentKind: video.kind,
      );
      captionUsed = true;
    }
    if (!captionUsed && text.isNotEmpty) {
      widget.onSend(text, _selected.value);
    }

    _controller.clear();
    if (attachment != null) setState(() => _pendingAttachment = null);
    if (videos.isNotEmpty) {
      setState(() => _pendingVideos = []);
      _savePendingVideos();
    }
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
      if (kIsWeb) {
        // Web: startStream() cuma dukung AudioEncoder.pcm16bits (raw PCM
        // tanpa header/container apa pun) — backend /stt gagal decode
        // ("Invalid data found when processing input", pesan khas
        // ffmpeg/ffprobe untuk data tanpa signature format yang dikenali).
        // Pakai start()/stop() dengan AudioEncoder.wav supaya hasil rekaman
        // dibungkus header WAV/RIFF yang valid (lihat _stopRecordingAndTranscribe
        // untuk cara ambil bytes-nya dari blob URL hasil stop()).
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
          path: '',
        );
      } else {
        final stream = await _audioRecorder.startStream(
          const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
        );
        _recordSub = stream.listen((chunk) => _recordedBytes.addAll(chunk));
      }
      if (!mounted) return;
      setState(() => _recording = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mulai rekam: $e')));
    }
  }

  Future<void> _stopRecordingAndTranscribe() async {
    String? blobUrl;
    try {
      blobUrl = await _audioRecorder.stop();
    } catch (_) {
      // Sudah berhenti/tidak sempat mulai — lanjut proses apa yang sudah terekam.
    }
    await _recordSub?.cancel();
    _recordSub = null;
    if (!mounted) return;
    setState(() => _recording = false);

    if (kIsWeb && blobUrl != null && blobUrl.isNotEmpty) {
      // record_web.stop() balikin blob: URL (bukan bytes langsung) —
      // Blob-nya sudah berisi WAV lengkap (header + PCM) dari AudioEncoder.
      // wav yang dipakai di _startRecording, tinggal di-fetch isinya.
      try {
        final res = await http.get(Uri.parse(blobUrl));
        _recordedBytes
          ..clear()
          ..addAll(res.bodyBytes);
      } catch (_) {
        // Gagal ambil isi blob — _recordedBytes tetap kosong, ditangani
        // guard "isEmpty" di bawah (tidak kirim data kosong ke /stt).
      }
    }
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

  /// "Upload Dokumen / File" — lampiran nyata (bebas tipe file), lewat
  /// jalur upload/attach yang sama dengan Upload Gambar/Video (preview di
  /// atas input bar, lalu terkirim bareng pesan berikutnya).
  Future<void> _pickDocumentAttachment() async {
    if (_attachmentBusy) return;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (result == null || result.files.isEmpty) return;
      await _uploadPlatformFile(result.files.first);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memilih dokumen: $e')),
      );
    }
  }

  /// "Upload Video (Semua Format)" — FileType.video (bawaan file_picker),
  /// multi-select sampai [_maxPendingVideos] video sekaligus, diupload satu
  /// per satu (progress per-file, lihat _uploadProgress/_uploadDone/
  /// _uploadTotal). Hasilnya masuk antrean _pendingVideos (beda dari
  /// _pendingAttachment yang cuma satu slot) — semua dikirim sebagai pesan
  /// terpisah saat user tekan kirim (lihat _submit), dan dipersist per
  /// percakapan (lihat _savePendingVideos) supaya tidak hilang saat
  /// refresh/pindah chat.
  Future<void> _pickVideoAttachment() async {
    if (_attachmentBusy) return;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: true, withData: true);
      if (result == null || result.files.isEmpty) return;

      final remainingSlots = _maxPendingVideos - _pendingVideos.length;
      if (remainingSlots <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maksimal 5 video per pesan — hapus salah satu dulu.')),
        );
        return;
      }
      var files = result.files;
      final truncated = files.length > remainingSlots;
      if (truncated) files = files.sublist(0, remainingSlots);

      setState(() {
        _attachmentBusy = true;
        _uploadTotal = files.length;
        _uploadDone = 0;
        _uploadProgress = 0.0;
      });
      for (final file in files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Video "${file.name}" gagal dibaca — dilewati.')),
            );
          }
        } else if (bytes.length > _maxUploadBytes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Video "${file.name}" terlalu besar (maks 50MB) — dilewati.')),
            );
          }
        } else {
          try {
            final up = await widget.onUploadAttachment(file.name, bytes);
            final url = (up['url'] ?? '').toString();
            if (url.isNotEmpty && mounted) {
              setState(() {
                _pendingVideos = [
                  ..._pendingVideos,
                  _PendingAttachment(
                    name: (up['name'] ?? file.name).toString(),
                    url: url,
                    kind: 'video',
                    sizeLabel: _formatAttachmentSize(bytes.length),
                  ),
                ];
              });
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Video "${file.name}" gagal diupload: $e')),
              );
            }
          }
        }
        if (!mounted) return;
        setState(() {
          _uploadDone++;
          _uploadProgress = _uploadTotal == 0 ? 1.0 : _uploadDone / _uploadTotal;
        });
      }
      await _savePendingVideos();
      if (truncated && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sebagian video tidak ditambahkan — maksimal 5 video per pesan.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memilih video: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _attachmentBusy = false;
          _uploadProgress = null;
        });
      }
    }
  }

  String get _pendingVideosPrefsKey => '$_pendingVideosPrefsPrefix${widget.conversationId ?? '_draft'}';

  /// Muat draft video terlampir milik percakapan aktif — dipanggil di
  /// initState dan tiap kali widget.conversationId berganti (lihat
  /// didUpdateWidget), supaya draft video ikut pindah/tetap ada per chat.
  Future<void> _loadPendingVideos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingVideosPrefsKey);
    var loaded = <_PendingAttachment>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        loaded = decoded
            .whereType<Map>()
            .map((m) => _PendingAttachment(
                  name: (m['name'] ?? '').toString(),
                  url: (m['url'] ?? '').toString(),
                  kind: (m['kind'] ?? 'video').toString(),
                  sizeLabel: m['sizeLabel']?.toString(),
                ))
            .where((a) => a.url.isNotEmpty)
            .toList();
      } catch (_) {
        // Data draft lama rusak/format tidak dikenal — mulai dari kosong.
      }
    }
    if (!mounted) return;
    setState(() => _pendingVideos = loaded);
  }

  /// Simpan (atau hapus kalau kosong) draft video terlampir milik
  /// percakapan aktif.
  Future<void> _savePendingVideos() async {
    final prefs = await SharedPreferences.getInstance();
    if (_pendingVideos.isEmpty) {
      await prefs.remove(_pendingVideosPrefsKey);
      return;
    }
    final encoded = jsonEncode(_pendingVideos
        .map((a) => {'name': a.name, 'url': a.url, 'kind': a.kind, 'sizeLabel': a.sizeLabel})
        .toList());
    await prefs.setString(_pendingVideosPrefsKey, encoded);
  }

  void _removePendingVideo(_PendingAttachment video) {
    setState(() => _pendingVideos = _pendingVideos.where((v) => v.url != video.url).toList());
    _savePendingVideos();
  }

  Future<void> _uploadPlatformFile(PlatformFile file) async {
    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak bisa membaca isi file ini')),
      );
      return;
    }
    await _uploadBytesAndAttach(file.name, bytes);
  }

  /// Upload file (bytes mentah) ke server (POST /upload/file lewat parent)
  /// lalu jadikan lampiran pending — dipakai bareng oleh Upload Gambar,
  /// Upload File/Dokumen, paste gambar dari clipboard (_onImagePasted), dan
  /// drag & drop (lewat widget.externalAttachment dari chat_screen.dart,
  /// yang uploadnya dilakukan di sana lalu didorong masuk sebagai attachment
  /// jadi — lihat _onExternalAttachment).
  Future<void> _uploadBytesAndAttach(String name, List<int> bytes) async {
    if (bytes.length > _maxUploadBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File terlalu besar (maks 50MB)')),
      );
      return;
    }
    setState(() => _attachmentBusy = true);
    try {
      final up = await widget.onUploadAttachment(name, bytes);
      final url = (up['url'] ?? '').toString();
      if (url.isEmpty) {
        throw Exception('Server tidak mengembalikan URL file');
      }
      if (!mounted) return;
      setState(() {
        _pendingAttachment = _PendingAttachment(
          name: (up['name'] ?? name).toString(),
          url: url,
          kind: _inferAttachmentKind(name),
          sizeLabel: _formatAttachmentSize(bytes.length),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload gagal: $e')),
      );
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  /// "Tambah dari Library" — ambil daftar file yang pernah diupload
  /// (GET /library lewat parent), tampilkan sebagai bottom sheet, item yang
  /// dipilih jadi lampiran pending sama seperti file yang baru diupload.
  Future<void> _openLibraryPicker() async {
    if (_attachmentBusy) return;
    setState(() => _attachmentBusy = true);
    List<Map<String, dynamic>> items;
    try {
      items = await widget.onFetchLibrary();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal ambil Library: $e')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JeonColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => _libraryPickerSheet(items),
    );
    if (selected == null || !mounted) return;
    final url = (selected['url'] ?? '').toString();
    if (url.isEmpty) return;
    final name = (selected['name'] ?? 'File').toString();
    final kind = (selected['kind'] ?? '').toString();
    final sizeRaw = selected['size'];
    setState(() {
      _pendingAttachment = _PendingAttachment(
        name: name,
        url: url,
        kind: kind.isNotEmpty ? kind : _inferAttachmentKind(name),
        sizeLabel: sizeRaw is num ? _formatAttachmentSize(sizeRaw.toInt()) : null,
      );
    });
  }

  Widget _libraryPickerSheet(List<Map<String, dynamic>> items) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: JeonColors.surface3, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Tambah dari Library',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 30),
                      child: Text('Belum ada file yang pernah diupload',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: JeonColors.inkFaint)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _libraryTile(items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _libraryTile(Map<String, dynamic> item) {
    final name = (item['name'] ?? 'File').toString();
    final url = (item['url'] ?? '').toString();
    final kind = (item['kind'] ?? '').toString();
    final sizeRaw = item['size'];
    final sizeLabel = sizeRaw is num ? _formatAttachmentSize(sizeRaw.toInt()) : '';
    final uploadedAt = (item['uploaded_at'] ?? '').toString();
    return ListTile(
      onTap: () => Navigator.of(context).pop(item),
      leading: kind == 'image' && url.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _kindIcon(kind),
              ),
            )
          : _kindIcon(kind),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.4, color: JeonColors.ink)),
      subtitle: Text([sizeLabel, uploadedAt].where((s) => s.isNotEmpty).join(' · '),
          style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
    );
  }

  Widget _kindIcon(String kind) {
    IconData icon;
    switch (kind) {
      case 'image':
        icon = Icons.image_outlined;
        break;
      case 'audio':
        icon = Icons.audiotrack_outlined;
        break;
      case 'video':
        icon = Icons.movie_creation_outlined;
        break;
      default:
        icon = Icons.insert_drive_file_outlined;
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: JeonColors.surface3, borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: JeonColors.inkMuted),
    );
  }

  String _inferAttachmentKind(String name) {
    final ext = name.contains('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';
    const imageExt = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'};
    const audioExt = {'mp3', 'wav', 'm4a', 'ogg', 'flac', 'aac'};
    const videoExt = {'mp4', 'mov', 'webm', 'mkv', 'avi'};
    if (imageExt.contains(ext)) return 'image';
    if (audioExt.contains(ext)) return 'audio';
    if (videoExt.contains(ext)) return 'video';
    return 'document';
  }

  String _formatAttachmentSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
            _plusMenuTile(Icons.insert_drive_file, 'Upload Dokumen / File', onTap: () {
              Navigator.of(sheetContext).pop();
              _pickDocumentAttachment();
            }),
            _plusMenuTile(Icons.folder_open_outlined, 'Tambah dari Library', onTap: () {
              Navigator.of(sheetContext).pop();
              _openLibraryPicker();
            }),
            _plusMenuTile(Icons.science_outlined, 'Riset Mendalam', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Riset Mendalam', 'Topik riset apa?', widget.onDeepResearch);
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
                      style: TextStyle(fontSize: 12, color: JeonColors.danger, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          if (_uploadProgress != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
              child: _uploadProgressBar(),
            )
          else if (_attachmentBusy)
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: JeonColors.accent)),
                  SizedBox(width: 8),
                  Text('Meng-upload file...',
                      style: TextStyle(fontSize: 12, color: JeonColors.accent, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          if (_pendingAttachment != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(alignment: Alignment.centerLeft, child: _attachmentPreview()),
            ),
          if (_pendingVideos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _pendingVideos.map(_videoAttachmentChip).toList(),
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
                          color: _recording ? JeonColors.danger : JeonColors.inkFaint,
                        ),
                  tooltip: _recording ? 'Berhenti rekam' : 'Dikte suara (rekam)',
                  onPressed: _sttLoading ? null : _toggleMic,
                ),
                const SizedBox(width: 2),
                if (widget.isGenerating)
                  Container(
                    decoration: const BoxDecoration(color: JeonColors.danger, shape: BoxShape.circle),
                    child: IconButton(
                      icon: const Icon(Icons.stop_rounded, size: 17, color: Colors.white),
                      tooltip: 'Hentikan',
                      onPressed: widget.onStop,
                    ),
                  )
                else if (_hasText || _pendingAttachment != null || _pendingVideos.isNotEmpty)
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

  /// Chip preview lampiran pending di atas input bar — ala WhatsApp/Telegram
  /// (thumbnail utk gambar, ikon jenis utk file lain), bisa dibatalkan (✕)
  /// sebelum dikirim.
  Widget _attachmentPreview() {
    final att = _pendingAttachment!;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: JeonColors.surface2,
        border: Border.all(color: JeonColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          att.kind == 'image'
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    att.url,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _kindIcon(att.kind),
                  ),
                )
              : _kindIcon(att.kind),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(att.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                if (att.sizeLabel != null)
                  Text(att.sizeLabel!, style: const TextStyle(fontSize: 10, color: JeonColors.inkFaint)),
              ],
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => setState(() => _pendingAttachment = null),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 16, color: JeonColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }

  /// Progress bar + status upload video (0%-100%, per-file — lihat catatan
  /// di _pickVideoAttachment soal kenapa progress dihitung per-file, bukan
  /// per-byte dalam satu file).
  Widget _uploadProgressBar() {
    final progress = _uploadProgress ?? 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Meng-upload video... ($_uploadDone/$_uploadTotal)',
                style: const TextStyle(fontSize: 12, color: JeonColors.accent, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${(progress * 100).round()}%',
                style: const TextStyle(fontSize: 12, color: JeonColors.accent, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: JeonColors.surface3,
            valueColor: const AlwaysStoppedAnimation(JeonColors.accent),
          ),
        ),
      ],
    );
  }

  /// Satu chip video di antrean _pendingVideos (maks 5) — nama+ukuran, tap
  /// tombol X untuk hapus dari antrean sebelum dikirim.
  Widget _videoAttachmentChip(_PendingAttachment video) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: JeonColors.surface2,
          border: Border.all(color: JeonColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _kindIcon('video'),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(video.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                  if (video.sizeLabel != null)
                    Text(video.sizeLabel!, style: const TextStyle(fontSize: 10, color: JeonColors.inkFaint)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _removePendingVideo(video),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: JeonColors.inkMuted),
              ),
            ),
          ],
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
            decoration: BoxDecoration(color: JeonColors.danger, borderRadius: BorderRadius.circular(2)),
          ),
        );
      }),
    );
  }
}

/// Lampiran pending (belum terkirim) di input bar — hasil dari Upload
/// Gambar/Upload File/Dokumen (baru diupload ke server) atau Tambah dari
/// Library (dipilih dari file lama). [kind] = image|document|audio|video.
class _PendingAttachment {
  final String name;
  final String url;
  final String kind;
  final String? sizeLabel;

  const _PendingAttachment({
    required this.name,
    required this.url,
    required this.kind,
    this.sizeLabel,
  });
}
