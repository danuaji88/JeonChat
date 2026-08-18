import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/agent.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/chat_history_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/context_sheet.dart';
import '../widgets/sidebar_chatgpt.dart';
import '../widgets/upgrade_dialog.dart';

class ChatScreen extends StatefulWidget {
  final ApiService api;
  final ProfileService profile;

  const ChatScreen({super.key, required this.api, required this.profile});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _guestMessageCount = 0;
  bool _hasText = false;

  // ---- Sidebar ala ChatGPT + multi-conversation ----
  String? _conversationId;
  List<Map<String, dynamic>> _conversations = [];
  bool? _sidebarOpenOverride; // null = pakai default responsif (terbuka di web/desktop)

  // ---- Model selector ("Fast" / "High" / "Think") ----
  static const Map<String, String> _modelOptions = {
    'Fast': 'jeon-fast',
    'High': 'jeon-chat',
    'Think': 'jeon-strong',
  };
  String _selectedModelLabel = 'High';
  String get _selectedModel => _modelOptions[_selectedModelLabel] ?? 'jeon-chat';

  // ---- Mic dikte + mode suara (speech_to_text) ----
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  late final AnimationController _pulseController;

  // Deteksi file yang disebut agent (mis. "disimpan di /tmp/xxx.jpg") agar
  // bisa ditampilkan sebagai preview gambar/audio, bukan cuma teks path.
  static final _tmpFilePathRegex = RegExp(r'/tmp/[\w\-.]+\.\w+');
  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp'};
  static const _audioExtensions = {'.mp3', '.wav', '.ogg', '.m4a', '.aac'};

  ChatMessage _buildAgentMessage(String content) {
    final match = _tmpFilePathRegex.firstMatch(content);
    if (match == null) return ChatMessage(isUser: false, text: content);
    final path = match.group(0)!;
    final dot = path.lastIndexOf('.');
    final ext = dot == -1 ? '' : path.substring(dot).toLowerCase();
    final mediaUrl = '${widget.api.baseUrl}$path';
    if (_imageExtensions.contains(ext)) {
      return ChatMessage(isUser: false, text: content, imageUrl: mediaUrl);
    }
    if (_audioExtensions.contains(ext)) {
      return ChatMessage(isUser: false, text: content, audioUrl: mediaUrl);
    }
    return ChatMessage(isUser: false, text: content, filePath: path);
  }

  // ---- Quick replies (ala UI kit premium) ----
  static const List<String> _quickReplies = [
    'Buat konten gambar',
    'Buat konten suara',
    'Cek biaya',
  ];

  // ---- Demo data (mirrors /opt/data/jeonchat_ui_mockup.html) ----
  final List<Agent> _agents = const [
    Agent(name: 'AI Clipper', task: 'Memotong video_umkm_02.mp4', status: AgentStatus.running),
    Agent(name: 'Media Generator', task: 'Render 3 gambar produk', status: AgentStatus.running),
    Agent(name: 'Report Builder', task: 'Idle', status: AgentStatus.idle),
  ];

  final List<TaskItem> _tasks = const [
    TaskItem(text: 'Transkripsi video (large-v3)', sub: 'Selesai · 18.2s', done: true),
    TaskItem(text: 'Deteksi momen viral', sub: '5 momen ditemukan', done: true),
    TaskItem(text: 'Burn caption + filter', sub: 'Klip 3 dari 5', done: false),
    TaskItem(text: 'Generate thumbnail', sub: 'Menunggu antrian', done: false),
  ];

  final List<KpiItem> _kpis = const [
    KpiItem(value: 'Rp0', label: 'Sesi ini', accent: true),
    KpiItem(value: '5', label: 'Klip diproses'),
    KpiItem(value: '9.770', label: 'Kredit Kie.ai'),
    KpiItem(value: '39', label: 'Model tersedia'),
  ];

  final List<IntegrationStatus> _integrations = const [
    IntegrationStatus(name: 'Router jeon-9router', status: 'online', online: true),
    IntegrationStatus(name: 'Telegram Gateway', status: 'online', online: true),
    IntegrationStatus(name: 'ElevenLabs TTS', status: 'online', online: true),
    IntegrationStatus(name: 'fal.ai', status: 'no key', online: false),
  ];

  late List<ChatMessage> _messages = [];
  String? _agentSession;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    _initSpeech();
    _loadConversations();
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
      // Mic/speech recognition tidak tersedia di browser ini — tombol mic
      // akan otomatis nonaktif, sisa fitur chat tetap jalan normal.
    }
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

  /// "Mode suara" — dengar satu ucapan, kirim sebagai pesan, lalu bacakan
  /// balasan AI-nya lewat TTS. Bukan percakapan realtime penuh (backend
  /// belum punya endpoint voice streaming), tapi tiap tombolnya benar-benar
  /// jalan: dengar → kirim → dengar balasannya.
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

    await _send(spoken);

    final lastReply = _messages.isNotEmpty && !_messages.last.isUser ? _messages.last.text : null;
    if (lastReply == null || lastReply.isEmpty || lastReply.startsWith('⚠️') || lastReply.startsWith('⏳')) {
      return;
    }
    try {
      final audioUrl = await widget.api.generateTTS(lastReply);
      if (audioUrl.isEmpty) return;
      final player = AudioPlayer();
      await player.play(UrlSource(audioUrl));
    } catch (_) {
      // Balasan tetap tampil di chat walau pembacaan suara gagal.
    }
  }

  List<ChatMessage> _messagesFromConversation(Map<String, dynamic>? conv) {
    final raw = conv?['messages'];
    if (raw is! List) return [];
    return raw.whereType<Map<String, dynamic>>().map(ChatMessage.fromJson).toList();
  }

  /// Load daftar semua percakapan lalu buka yang paling baru — bikin satu
  /// percakapan kosong kalau belum ada sama sekali.
  Future<void> _loadConversations() async {
    final list = await ChatHistoryService.listConversations();
    if (!mounted) return;
    if (list.isEmpty) {
      final id = await ChatHistoryService.createConversation();
      final refreshed = await ChatHistoryService.listConversations();
      if (!mounted) return;
      setState(() {
        _conversations = refreshed;
        _conversationId = id;
        _messages = [];
        _agentSession = null;
      });
      return;
    }
    final activeId = list.first['id'] as String;
    final active = await ChatHistoryService.loadConversation(activeId);
    if (!mounted) return;
    setState(() {
      _conversations = list;
      _conversationId = activeId;
      _messages = _messagesFromConversation(active);
      _agentSession = active?['agentSession'] as String?;
    });
    _scrollToBottom();
  }

  /// Dipanggil di setiap titik yang tadinya panggil "_saveHistory()" —
  /// simpan pesan-pesan ke percakapan aktif lalu segarkan daftar sidebar.
  Future<void> _saveHistory() async {
    final id = _conversationId;
    if (id == null) return;
    await ChatHistoryService.saveConversation(id, _messages, agentSession: _agentSession);
    final list = await ChatHistoryService.listConversations();
    if (!mounted) return;
    setState(() => _conversations = list);
  }

  Future<void> _newChat() async {
    final id = await ChatHistoryService.createConversation();
    final list = await ChatHistoryService.listConversations();
    if (!mounted) return;
    setState(() {
      _conversationId = id;
      _messages = [];
      _agentSession = null;
      _conversations = list;
    });
  }

  Future<void> _openChat(String id) async {
    if (id == _conversationId) return;
    final conv = await ChatHistoryService.loadConversation(id);
    if (!mounted || conv == null) return;
    setState(() {
      _conversationId = id;
      _messages = _messagesFromConversation(conv);
      _agentSession = conv['agentSession'] as String?;
    });
    _scrollToBottom();
  }

  Future<void> _renameConversation(String id, String title) async {
    await ChatHistoryService.renameConversation(id, title);
    final list = await ChatHistoryService.listConversations();
    if (!mounted) return;
    setState(() => _conversations = list);
  }

  Future<void> _togglePinConversation(String id, bool pinned) async {
    await ChatHistoryService.pinConversation(id, pinned);
    final list = await ChatHistoryService.listConversations();
    if (!mounted) return;
    setState(() => _conversations = list);
  }

  Future<void> _deleteConversationById(String id) async {
    await ChatHistoryService.deleteConversation(id);
    final list = await ChatHistoryService.listConversations();
    if (!mounted) return;
    if (id != _conversationId) {
      setState(() => _conversations = list);
      return;
    }
    if (list.isNotEmpty) {
      final nextId = list.first['id'] as String;
      final conv = await ChatHistoryService.loadConversation(nextId);
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _conversationId = nextId;
        _messages = _messagesFromConversation(conv);
        _agentSession = conv?['agentSession'] as String?;
      });
    } else {
      final newId = await ChatHistoryService.createConversation();
      final refreshed = await ChatHistoryService.listConversations();
      if (!mounted) return;
      setState(() {
        _conversations = refreshed;
        _conversationId = newId;
        _messages = [];
        _agentSession = null;
      });
    }
  }

  /// Hapus SEMUA percakapan (dipakai tombol "Hapus semua riwayat chat" di
  /// Settings) — beda dari _newChat() yang cuma bikin satu chat kosong baru
  /// tanpa menyentuh percakapan lain.
  Future<void> _clearAllHistory() async {
    for (final c in List<Map<String, dynamic>>.from(_conversations)) {
      await ChatHistoryService.deleteConversation(c['id'] as String);
    }
    final newId = await ChatHistoryService.createConversation();
    final refreshed = await ChatHistoryService.listConversations();
    if (!mounted) return;
    setState(() {
      _conversations = refreshed;
      _conversationId = newId;
      _messages = [];
      _agentSession = null;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  int get _runningCount => _agents.where((a) => a.status == AgentStatus.running).length;

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;
    setState(() {
      _messages = [..._messages, ChatMessage(isUser: true, text: text)];
      _guestMessageCount++;
      // Typing indicator — selalu tampil untuk setiap pesan baru
      _messages = [..._messages, ChatMessage(isUser: false, text: '⏳ AI sedang bekerja...')];
    });
    _controller.clear();
    _saveHistory();
    _scrollToBottom();

    if (widget.api.isGuest && _guestMessageCount == 6 && mounted) {
      showUpgradeDialog(context, api: widget.api, profile: widget.profile);
    }

    // ── Deteksi media request → langsung pakai /media/* endpoint (cepat, gratis) ──
    final lower = text.toLowerCase();
    final isImageRequest = lower.contains('buat gambar') || lower.contains('buat konten gambar') || lower.contains('generate gambar') || lower.contains('cari gambar');
    final isVideoRequest = lower.contains('buat video') || lower.contains('buat konten video') || lower.contains('cari video');
    final isAudioRequest = lower.contains('buat suara') || lower.contains('buat konten suara') || lower.contains('text to speech') || lower.contains('tts') || lower.contains('voice over');
    final isCostRequest = lower.contains('cek biaya') || lower.contains('cek cost') || lower.contains('biaya') || lower.contains('harga');

    if (isImageRequest || isVideoRequest || isAudioRequest) {
      await _handleMediaRequest(text, isImageRequest, isVideoRequest, isAudioRequest);
      return;
    }
    if (isCostRequest) {
      await _handleCostRequest();
      return;
    }

    // ── Normal: agent / chat ──
    await _handleChatRequest(text);
  }

  Future<void> _handleCostRequest() async {
    try {
      final reply = await widget.api.sendChat(
        history: _messages.where((m) => !m.text.startsWith('⏳')).toList(),
        model: _selectedModel,
      );
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1); // hapus typing
        _messages = [..._messages, ChatMessage(isUser: false, text: reply)];
      });
      _saveHistory();
    } catch (e) {
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1);
        _messages = [..._messages, ChatMessage(isUser: false, text: '⚠️ Gagal cek biaya: $e')];
      });
      _saveHistory();
    }
  }

  Future<void> _handleMediaRequest(String text, bool isImg, bool isVid, bool isAudio) async {
    try {
      // Ekstrak prompt bersih dari teks user
      String prompt = text;
      for (final w in ['buat gambar', 'buat konten gambar', 'generate gambar', 'cari gambar',
                        'buat video', 'buat konten video', 'cari video',
                        'buat suara', 'buat konten suara', 'text to speech', 'tts', 'voice over',
                        'yang gratis', 'gratis']) {
        prompt = prompt.replaceAll(w, '');
      }
      prompt = prompt.trim();
      if (prompt.isEmpty) prompt = text; // fallback ke teks asli

      if (isImg) {
        final imageUrl = await widget.api.generateMediaImage(prompt);
        // Coba download ke lokal dulu via Image.network dari server kita (no CORS)
        setState(() {
          _messages = _messages.sublist(0, _messages.length - 1); // hapus typing
          _messages = [..._messages, ChatMessage(
            isUser: false,
            text: '✅ Gambar siap! 📸\nPrompt: $prompt',
            imageUrl: imageUrl,
          )];
        });
        _saveHistory();
      } else if (isVid) {
        final videoUrl = await widget.api.generateMediaVideo(prompt);
        setState(() {
          _messages = _messages.sublist(0, _messages.length - 1);
          _messages = [..._messages, ChatMessage(
            isUser: false,
            text: '✅ Video siap! 🎬\nPrompt: $prompt',
            videoUrl: videoUrl,
          )];
        });
        _saveHistory();
      } else if (isAudio) {
        final audioUrl = await widget.api.generateTTS(prompt);
        setState(() {
          _messages = _messages.sublist(0, _messages.length - 1);
          _messages = [..._messages, ChatMessage(
            isUser: false,
            text: '✅ Audio siap! 🔊\nTeks: $prompt',
            audioUrl: audioUrl,
          )];
        });
        _saveHistory();
      }
    } catch (e) {
      // Fallback ke agent kalau media endpoint gagal
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1);
        _messages = [..._messages, ChatMessage(isUser: false, text: '⚠️ Media gagal: $e\nMencoba via agent...')];
      });
      _saveHistory();
      await _handleChatRequest(text);
    } finally {
      _scrollToBottom();
    }
  }

  Future<void> _handleChatRequest(String text) async {
    try {
      final result = await widget.api.sendAgentPrompt(
        prompt: text,
        agentSession: _agentSession,
      );
      if (result.agentSession != null) {
        _agentSession = result.agentSession;
      }
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1); // hapus typing
        _messages = [..._messages, _buildAgentMessage(result.content)];
      });
      _saveHistory();
    } on AgentTimeoutException catch (e) {
      // Agent timeout — auto-fallback ke /chat
      try {
        final reply = await widget.api.sendChat(
          history: _messages.where((m) => !m.text.startsWith('⏳')).toList(),
          model: _selectedModel,
        );
        setState(() {
          _messages = _messages.sublist(0, _messages.length - 1);
          _messages = [..._messages, ChatMessage(isUser: false, text: reply)];
        });
        _saveHistory();
      } catch (e2) {
        setState(() {
          _messages = _messages.sublist(0, _messages.length - 1);
          _messages = [
            ..._messages,
            ChatMessage(isUser: false, text: '⏳ ${e.toString()}'),
          ];
        });
        _saveHistory();
      }
    } catch (e) {
      // Fallback ke /chat kalau /agent gagal
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1);
      });
      try {
        final reply = await widget.api.sendChat(
          history: _messages,
          model: _selectedModel,
        );
        setState(() {
          _messages = [..._messages, ChatMessage(isUser: false, text: reply)];
        });
        _saveHistory();
      } catch (e2) {
        setState(() {
          _messages = [
            ..._messages,
            ChatMessage(isUser: false, text: '⚠️ ${e2.toString()}'),
          ];
        });
        _saveHistory();
      }
    } finally {
      _scrollToBottom();
    }
  }

  // ---- Aksi popover "+": tiap tombol benar-benar panggil backend ----

  Future<void> _pickFileAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.isEmpty || !mounted) return;
      final name = result.files.first.name;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terpilih: $name — upload file belum didukung backend saat ini')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka file picker: $e')),
      );
    }
  }

  Future<void> _generateImageDirect(String prompt) async {
    setState(() {
      _messages = [..._messages, ChatMessage(isUser: true, text: 'Buat gambar: $prompt')];
      _messages = [..._messages, ChatMessage(isUser: false, text: '⏳ AI sedang bekerja...')];
    });
    _saveHistory();
    _scrollToBottom();
    try {
      final url = await widget.api.generateImage(prompt);
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1);
        _messages = [..._messages, ChatMessage(isUser: false, text: '✅ Gambar siap!', imageUrl: url)];
      });
    } catch (e) {
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1);
        _messages = [..._messages, ChatMessage(isUser: false, text: '⚠️ Gagal membuat gambar: $e')];
      });
    }
    _saveHistory();
    _scrollToBottom();
  }

  Future<void> _generateAudioDirect(String text) async {
    setState(() {
      _messages = [..._messages, ChatMessage(isUser: true, text: 'Buat suara: $text')];
      _messages = [..._messages, ChatMessage(isUser: false, text: '⏳ AI sedang bekerja...')];
    });
    _saveHistory();
    _scrollToBottom();
    try {
      final url = await widget.api.generateTTS(text);
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1);
        _messages = [..._messages, ChatMessage(isUser: false, text: '✅ Audio siap!', audioUrl: url)];
      });
    } catch (e) {
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1);
        _messages = [..._messages, ChatMessage(isUser: false, text: '⚠️ Gagal membuat suara: $e')];
      });
    }
    _saveHistory();
    _scrollToBottom();
  }

  Future<void> _generateVideoDirect(String prompt) async {
    setState(() {
      _messages = [..._messages, ChatMessage(isUser: true, text: 'Buat video: $prompt')];
      _messages = [..._messages, ChatMessage(isUser: false, text: '⏳ AI sedang bekerja...')];
    });
    _saveHistory();
    _scrollToBottom();
    try {
      final url = await widget.api.generateVideo(prompt);
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1);
        _messages = [..._messages, ChatMessage(isUser: false, text: '✅ Video siap!', videoUrl: url)];
      });
    } catch (e) {
      setState(() {
        _messages = _messages.sublist(0, _messages.length - 1);
        _messages = [..._messages, ChatMessage(isUser: false, text: '⚠️ Gagal membuat video: $e')];
      });
    }
    _saveHistory();
    _scrollToBottom();
  }

  // Tidak ada endpoint /search khusus di backend — dikirim lewat /agent
  // (endpoint tools-lengkap) dengan instruksi eksplisit, bukan sekadar UI.
  Future<void> _searchWeb(String query) => _send('Cari di internet: $query');

  Future<void> _deepResearch(String topic) => _send('Lakukan riset mendalam tentang: $topic');

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
            _plusMenuTile(Icons.add_photo_alternate_outlined, 'Tambah foto & file', onTap: () {
              Navigator.of(sheetContext).pop();
              _pickFileAttachment();
            }),
            _plusMenuTile(Icons.image_outlined, 'Buat gambar', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Buat gambar', 'Gambar apa yang mau dibuat?', _generateImageDirect);
            }),
            _plusMenuTile(Icons.travel_explore_outlined, 'Cari di web', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Cari di web', 'Mau cari apa?', _searchWeb);
            }),
            _plusMenuTile(Icons.science_outlined, 'Riset mendalam', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Riset mendalam', 'Topik riset apa?', _deepResearch);
            }),
            _plusMenuTile(Icons.graphic_eq_rounded, 'Buat suara', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Buat suara', 'Teks yang mau dibacakan?', _generateAudioDirect);
            }),
            _plusMenuTile(Icons.movie_creation_outlined, 'Buat video', onTap: () {
              Navigator.of(sheetContext).pop();
              _promptFor('Buat video', 'Video apa yang mau dibuat?', _generateVideoDirect);
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

  /// Bottom sheet input pendek dipakai semua aksi popover "+" — ambil satu
  /// baris teks lalu jalankan [handler] dengannya.
  Future<void> _promptFor(String title, String hint, Future<void> Function(String) handler) async {
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
    await handler(trimmed);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final sidebarOpen = _sidebarOpenOverride ?? true;

    final sidebar = SidebarChatGPT(
      api: widget.api,
      profile: widget.profile,
      conversations: _conversations,
      activeConversationId: _conversationId,
      onNewChat: () {
        _newChat();
        if (!isWide) Navigator.of(context).maybePop();
      },
      onSelectConversation: (id) {
        _openChat(id);
        if (!isWide) Navigator.of(context).maybePop();
      },
      onRenameConversation: _renameConversation,
      onTogglePin: _togglePinConversation,
      onDeleteConversation: _deleteConversationById,
      onClose: () {
        if (isWide) {
          setState(() => _sidebarOpenOverride = false);
        } else {
          Navigator.of(context).maybePop();
        }
      },
      onClearHistory: _clearAllHistory,
      onProfileChanged: () => setState(() {}),
    );

    final chatScaffold = Scaffold(
      key: _scaffoldKey,
      backgroundColor: JeonColors.bg,
      drawer: isWide
          ? null
          : Drawer(
              backgroundColor: Colors.black,
              width: 260,
              child: SafeArea(child: sidebar),
            ),
      appBar: AppBar(
        titleSpacing: 8,
        leading: IconButton(
          icon: const Icon(Icons.menu, size: 20, color: JeonColors.inkMuted),
          tooltip: 'Sidebar',
          onPressed: () {
            if (isWide) {
              setState(() => _sidebarOpenOverride = !sidebarOpen);
            } else {
              _scaffoldKey.currentState?.openDrawer();
            }
          },
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [JeonColors.accent, JeonColors.accentDim],
                ),
                boxShadow: [BoxShadow(color: JeonColors.accentGlow, blurRadius: 10)],
              ),
              alignment: Alignment.center,
              child: const Text('J',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF04150A))),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('JeonChat', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: JeonColors.accent),
                    ),
                    const SizedBox(width: 5),
                    const Text('online · deepseek-v4-flash',
                        style: TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 20, color: JeonColors.inkMuted),
            tooltip: 'Chat Baru',
            onPressed: () {
              _newChat();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Chat baru dimulai'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: JeonColors.accentGlow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: JeonColors.accent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _pulseController,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: JeonColors.accent),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('$_runningCount agent bekerja',
                        style: const TextStyle(fontSize: 11.5, color: JeonColors.accent)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: JeonColors.surface2,
        foregroundColor: JeonColors.accent,
        elevation: 0,
        onPressed: () => ContextSheet.show(
          context,
          tasks: _tasks,
          kpis: _kpis,
          integrations: _integrations,
        ),
        child: const Icon(Icons.dashboard_customize_outlined),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _welcomeScreen()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) => ChatBubble(message: _messages[i]),
                  ),
          ),
          _composer(),
        ],
      ),
    );

    if (!isWide) return chatScaffold;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          if (sidebarOpen) SizedBox(width: 260, child: SafeArea(child: sidebar)),
          Expanded(child: chatScaffold),
        ],
      ),
    );
  }

  Widget _welcomeScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [JeonColors.accent, JeonColors.accentDim],
              ),
              boxShadow: [BoxShadow(color: JeonColors.accentGlow, blurRadius: 20)],
            ),
            alignment: Alignment.center,
            child: const Text('J',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                    color: Color(0xFF04150A))),
          ),
          const SizedBox(height: 16),
          const Text('Ada yang bisa saya bantu hari ini?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: JeonColors.ink)),
          const SizedBox(height: 8),
          const Text('Ketik pesan atau pilih saran di bawah',
              style: TextStyle(fontSize: 12.5, color: JeonColors.inkFaint)),
        ],
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
      child: Column(
        children: [
          // Quick reply chips (ala UI kit premium)
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemCount: _quickReplies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final q = _quickReplies[i];
                return GestureDetector(
                  onTap: () => _send(q),
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.add, size: 20, color: JeonColors.inkMuted),
                  tooltip: 'Tambah',
                  onPressed: _showPlusMenu,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
                    decoration: const InputDecoration(
                      hintText: 'Ask JeonChat...',
                      hintStyle: TextStyle(color: JeonColors.inkFaint),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                _modelDropdown(),
                const SizedBox(width: 4),
                if (_hasText)
                  Container(
                    decoration: const BoxDecoration(color: JeonColors.accent, shape: BoxShape.circle),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded, size: 17, color: Color(0xFF04150A)),
                      onPressed: _send,
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
