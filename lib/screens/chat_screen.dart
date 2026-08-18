import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../models/agent.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/chat_history_service.dart';
import '../services/plugin_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import 'auth_gate_screen.dart';
import 'library_screen.dart';
import 'plugins_screen.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/context_sheet.dart';
import '../widgets/input_bar.dart';
import '../widgets/sidebar_jeonchat.dart';
import '../widgets/upgrade_dialog.dart';

class JeonChatScreen extends StatefulWidget {
  final ApiService api;
  final ProfileService profile;

  const JeonChatScreen({super.key, required this.api, required this.profile});

  @override
  State<JeonChatScreen> createState() => _JeonChatScreenState();
}

class _JeonChatScreenState extends State<JeonChatScreen> {
  final _scrollController = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _guestMessageCount = 0;

  // ---- Sidebar JeonChat + multi-conversation ----
  String? _conversationId;
  List<Map<String, dynamic>> _conversations = [];
  bool? _sidebarOpenOverride; // null = pakai default responsif (terbuka di web/desktop)
  double _messagesOpacity = 1.0; // fade 150ms saat pindah conversation

  // ---- Projects ----
  List<Map<String, dynamic>> _projects = [];
  String? _activeProjectId;

  // ---- Plugin Store (area chat digantikan, sidebar tetap terlihat) ----
  bool _showPluginsStore = false;
  List<InstalledPlugin> _installedPlugins = [];

  // ---- Fitur AI: model dropdown + dokumen RAG ----
  List<ModelOption> _modelOptions = ApiService.fallbackModelOptions;
  bool _hasActiveDocument = false;

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
    _loadConversations();
    _loadInstalledPlugins();
    _loadModelOptions();
  }

  /// GET /models sudah menyertakan 'options' — kalau gagal/tidak ada,
  /// _modelOptions tetap di fallback (sudah default sejak deklarasi field).
  Future<void> _loadModelOptions() async {
    try {
      final options = await widget.api.getModelOptions();
      if (!mounted || options.isEmpty) return;
      setState(() => _modelOptions = options);
    } catch (_) {
      // Fallback hardcode tetap dipakai.
    }
  }

  /// Dipanggil JeonChatInputBar setelah mode Voice selesai mendengarkan —
  /// kirim ucapan sebagai pesan biasa, lalu bacakan balasan AI-nya lewat
  /// TTS. Bukan percakapan realtime penuh (backend belum punya endpoint
  /// voice streaming), tapi alurnya (dengar → kirim → dengar balasan) jalan
  /// sungguhan.
  Future<void> _onVoiceModeResult(String spoken) async {
    await _send(spoken, 'jeon-chat');

    final lastReply = _messages.isNotEmpty && !_messages.last.isUser ? _messages.last.text : null;
    if (lastReply == null || lastReply.isEmpty || lastReply.startsWith('⚠️') || lastReply.startsWith('JeonAI Sedang')) {
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
  /// percakapan kosong kalau belum ada sama sekali. Sebelum ditampilkan,
  /// perbaiki dulu judul lama yang masih kepentok "Percakapan Baru" padahal
  /// sudah ada isi pesan (lihat ChatHistoryService.fixAllStaleTitles).
  Future<void> _loadConversations() async {
    await ChatHistoryService.fixAllStaleTitles();
    final projects = await ChatHistoryService.listProjects();
    final list = await ChatHistoryService.listConversations();
    if (!mounted) return;
    if (list.isEmpty) {
      final id = await ChatHistoryService.createConversation();
      final refreshed = await ChatHistoryService.listConversations();
      if (!mounted) return;
      setState(() {
        _projects = projects;
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
      _projects = projects;
      _conversations = list;
      _conversationId = activeId;
      _messages = _messagesFromConversation(active);
      _agentSession = active?['agentSession'] as String?;
    });
    _scrollToBottom();
  }

  Future<void> _refreshProjects() async {
    final projects = await ChatHistoryService.listProjects();
    if (!mounted) return;
    setState(() => _projects = projects);
  }

  Future<void> _createProject(String name, String color, String icon) async {
    await ChatHistoryService.createProject(name: name, color: color, icon: icon);
    await _refreshProjects();
  }

  Future<void> _renameProject(String id, String name) async {
    await ChatHistoryService.renameProject(id, name);
    await _refreshProjects();
  }

  Future<void> _updateProjectSettings(
    String id, {
    required String name,
    required String description,
    required String color,
    required String icon,
  }) async {
    await ChatHistoryService.updateProjectSettings(id, name: name, description: description, color: color, icon: icon);
    await _refreshProjects();
  }

  Future<void> _pinProject(String id, bool pinned) async {
    await ChatHistoryService.pinProject(id, pinned);
    await _refreshProjects();
  }

  Future<void> _archiveProject(String id, bool archived) async {
    await ChatHistoryService.archiveProject(id, archived);
    if (_activeProjectId == id) setState(() => _activeProjectId = null);
    await _refreshProjects();
  }

  Future<void> _deleteProject(String id) async {
    await ChatHistoryService.deleteProject(id);
    if (_activeProjectId == id) setState(() => _activeProjectId = null);
    await _refreshProjects();
    final list = await ChatHistoryService.listConversations();
    if (!mounted) return;
    setState(() => _conversations = list);
  }

  void _selectProject(String? id) => setState(() => _activeProjectId = id);

  Future<void> _moveToProject(String conversationId, String? projectId) async {
    await ChatHistoryService.setConversationProject(conversationId, projectId);
    final list = await ChatHistoryService.listConversations();
    if (!mounted) return;
    setState(() => _conversations = list);
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

  /// Balikin opacity list pesan ke 1 di frame berikutnya — dipicu tiap kali
  /// conversation aktif berganti, biar AnimatedOpacity fade-in 150ms.
  void _fadeInMessages() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _messagesOpacity = 1.0);
    });
  }

  Future<void> _newChat() async {
    final id = await ChatHistoryService.createConversation(projectId: _activeProjectId);
    final list = await ChatHistoryService.listConversations();
    if (!mounted) return;
    setState(() {
      _conversationId = id;
      _messages = [];
      _agentSession = null;
      _conversations = list;
      _messagesOpacity = 0.0;
      _showPluginsStore = false;
      _hasActiveDocument = false;
    });
    _fadeInMessages();
  }

  Future<void> _openChat(String id) async {
    if (id == _conversationId) {
      if (_showPluginsStore) setState(() => _showPluginsStore = false);
      return;
    }
    final conv = await ChatHistoryService.loadConversation(id);
    if (!mounted || conv == null) return;
    setState(() {
      _conversationId = id;
      _messages = _messagesFromConversation(conv);
      _agentSession = conv['agentSession'] as String?;
      _messagesOpacity = 0.0;
      _showPluginsStore = false;
      _hasActiveDocument = false;
    });
    _fadeInMessages();
    _scrollToBottom();
  }

  // ---- Plugin Store: install state dipersist via PluginService, dipakai
  // bareng oleh Plugin Store sendiri, "My Plugins" di sidebar, dan badge
  // di input bar. ----

  Future<void> _loadInstalledPlugins() async {
    final list = await PluginService.listInstalled();
    if (!mounted) return;
    setState(() => _installedPlugins = list);
  }

  Future<void> _togglePlugin(PluginItem item) async {
    final installed = _installedPlugins.any((p) => p.title == item.title);
    final updated = installed
        ? await PluginService.uninstall(item.title)
        : await PluginService.install(item.title, item.emoji);
    if (!mounted) return;
    setState(() => _installedPlugins = updated);
  }

  Future<void> _deactivatePlugin(String title) async {
    final updated = await PluginService.uninstall(title);
    if (!mounted) return;
    setState(() => _installedPlugins = updated);
  }

  void _openPluginsStore() => setState(() => _showPluginsStore = true);

  void _closePluginsStore() => setState(() => _showPluginsStore = false);

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

  Future<void> _toggleArchiveConversation(String id, bool archived) async {
    await ChatHistoryService.archiveConversation(id, archived);
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
        _messagesOpacity = 0.0;
      });
      _fadeInMessages();
    } else {
      final newId = await ChatHistoryService.createConversation();
      final refreshed = await ChatHistoryService.listConversations();
      if (!mounted) return;
      setState(() {
        _conversations = refreshed;
        _conversationId = newId;
        _messages = [];
        _agentSession = null;
        _messagesOpacity = 0.0;
      });
      _fadeInMessages();
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
    _scrollController.dispose();
    super.dispose();
  }

  /// Auth gate ala ChatGPT: Plugins/Library/Scheduled/More butuh login —
  /// mode tamu cuma boleh chat dasar. Token tersimpan (isLoggedIn) → langsung
  /// jalankan [onGranted]; belum → tampilkan AuthGateScreen dulu, baru
  /// jalankan [onGranted] kalau berhasil masuk (bukan sekadar Batal).
  Future<void> _requireAuth(VoidCallback onGranted) async {
    if (widget.api.isLoggedIn) {
      onGranted();
      return;
    }
    final granted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AuthGateScreen(api: widget.api)),
    );
    if (!mounted) return;
    if (granted == true) {
      setState(() {}); // refresh ikon gembok di sidebar
      onGranted();
    }
  }

  static const _thinkingText = 'JeonAI Sedang Berpikir Lalu Eksekusi Mohon Ditunggu';

  /// Ganti placeholder "Sedang berpikir" ([typing]) dengan balasan asli DI
  /// POSISI YANG SAMA — pakai identity check (bukan asumsi "typing selalu
  /// elemen terakhir"), supaya kalau user sempat kirim pesan lain sebelum
  /// balasan ini datang (dua request nyala bersamaan), yang dihapus/diganti
  /// selalu placeholder yang BENAR. Sebelumnya pakai
  /// `_messages.sublist(0, _messages.length - 1)` yang salah target begitu
  /// ada pesan lain menyusul di akhir list — itu penyebab loading nyangkut
  /// selamanya (Bug 1) dan balasan nongol di bubble/urutan yang salah (Bug 2).
  void _resolveTyping(ChatMessage typing, ChatMessage reply) {
    setState(() {
      final idx = _messages.indexWhere((m) => identical(m, typing));
      if (idx == -1) {
        _messages = [..._messages, reply];
      } else {
        _messages = [
          ..._messages.sublist(0, idx),
          reply,
          ..._messages.sublist(idx + 1),
        ];
      }
    });
  }

  /// Riwayat buat dikirim ke /chat — buang semua bubble placeholder "Sedang
  /// berpikir" (termasuk punya request lain yang mungkin masih nyala
  /// bersamaan) dan pesan error, supaya tidak ikut kekirim sebagai konteks.
  List<ChatMessage> _cleanHistory() =>
      _messages.where((m) => m.text != _thinkingText && !m.text.startsWith('⚠️')).toList();

  Future<void> _send(String text, String model) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final typing = ChatMessage(isUser: false, text: _thinkingText);
    setState(() {
      _messages = [..._messages, ChatMessage(isUser: true, text: trimmed), typing];
      _guestMessageCount++;
    });
    _saveHistory();
    _scrollToBottom();

    if (widget.api.isGuest && _guestMessageCount == 6 && mounted) {
      showUpgradeDialog(context, api: widget.api, profile: widget.profile);
    }

    // ── Deteksi media request → langsung pakai /media/* endpoint (cepat, gratis) ──
    final lower = trimmed.toLowerCase();
    final isImageRequest = lower.contains('buat gambar') || lower.contains('buat konten gambar') || lower.contains('generate gambar') || lower.contains('cari gambar');
    final isVideoRequest = lower.contains('buat video') || lower.contains('buat konten video') || lower.contains('cari video');
    final isAudioRequest = lower.contains('buat suara') || lower.contains('buat konten suara') || lower.contains('text to speech') || lower.contains('tts') || lower.contains('voice over');
    final isCostRequest = lower.contains('cek biaya') || lower.contains('cek cost') || lower.contains('biaya') || lower.contains('harga');
    // "cari gambar"/"cari video" sudah ditangani media pipeline di atas —
    // prefix "cari "/"search " generik baru dianggap web search kalau bukan itu.
    final isSearchRequest = !isImageRequest &&
        !isVideoRequest &&
        !isAudioRequest &&
        (lower.startsWith('cari ') || lower.startsWith('search '));

    if (isImageRequest || isVideoRequest || isAudioRequest) {
      await _handleMediaRequest(trimmed, isImageRequest, isVideoRequest, isAudioRequest, typing);
      return;
    }
    if (isSearchRequest) {
      final query = trimmed.replaceFirst(RegExp(r'^(cari|search)\s+', caseSensitive: false), '').trim();
      await _handleWebSearchRequest(query.isEmpty ? trimmed : query, typing);
      return;
    }
    if (isCostRequest) {
      await _handleCostRequest(model, typing);
      return;
    }
    if (_hasActiveDocument) {
      await _handleDocRequest(trimmed, typing);
      return;
    }

    // ── Normal: agent / chat ──
    await _handleChatRequest(trimmed, model, typing);
  }

  Future<void> _handleCostRequest(String model, ChatMessage typing) async {
    try {
      final reply = await widget.api.sendChat(history: _cleanHistory(), model: model);
      _resolveTyping(typing, ChatMessage(isUser: false, text: reply));
    } catch (e) {
      _resolveTyping(typing, ChatMessage(isUser: false, text: '⚠️ Gagal cek biaya: $e'));
    }
    _saveHistory();
  }

  Future<void> _handleMediaRequest(String text, bool isImg, bool isVid, bool isAudio, ChatMessage typing) async {
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
        _resolveTyping(typing, ChatMessage(
          isUser: false,
          text: '✅ Gambar siap! 📸\nPrompt: $prompt',
          imageUrl: imageUrl,
        ));
        _saveHistory();
      } else if (isVid) {
        final videoUrl = await widget.api.generateMediaVideo(prompt);
        _resolveTyping(typing, ChatMessage(
          isUser: false,
          text: '✅ Video siap! 🎬\nPrompt: $prompt',
          videoUrl: videoUrl,
        ));
        _saveHistory();
      } else if (isAudio) {
        final audioUrl = await widget.api.generateTTS(prompt);
        _resolveTyping(typing, ChatMessage(
          isUser: false,
          text: '✅ Audio siap! 🔊\nTeks: $prompt',
          audioUrl: audioUrl,
        ));
        _saveHistory();
      }
    } catch (e) {
      // Fallback ke agent kalau media endpoint gagal — placeholder "Sedang
      // berpikir" TETAP dipakai (diteruskan apa adanya), bukan diganti pesan
      // sementara dulu baru dibuat placeholder baru lagi — biar loading
      // indicator tidak sempat hilang-lalu-muncul-lagi.
      await _handleChatRequest(text, 'jeon-chat', typing);
    } finally {
      _scrollToBottom();
    }
  }

  Future<void> _handleChatRequest(String text, String model, ChatMessage typing) async {
    try {
      final result = await widget.api.sendAgentPrompt(
        prompt: text,
        model: model,
        agentSession: _agentSession,
      );
      if (result.agentSession != null) {
        _agentSession = result.agentSession;
      }
      _resolveTyping(typing, _buildAgentMessage(result.content));
      _saveHistory();
    } on AgentTimeoutException {
      // Agent timeout — auto-fallback ke /chat
      try {
        final reply = await widget.api.sendChat(history: _cleanHistory(), model: model);
        _resolveTyping(typing, ChatMessage(isUser: false, text: reply));
        _saveHistory();
      } catch (e2) {
        _resolveTyping(typing, ChatMessage(isUser: false, text: 'Maaf, koneksi lambat. Coba ulangi ya Appa 🙏'));
        _saveHistory();
      }
    } catch (e) {
      // Fallback ke /chat kalau /agent gagal
      try {
        final reply = await widget.api.sendChat(history: _cleanHistory(), model: model);
        _resolveTyping(typing, ChatMessage(isUser: false, text: reply));
        _saveHistory();
      } catch (e2) {
        _resolveTyping(typing, ChatMessage(isUser: false, text: '⚠️ ${e2.toString()}'));
        _saveHistory();
      }
    } finally {
      _scrollToBottom();
    }
  }

  Future<void> _handleWebSearchRequest(String query, ChatMessage typing) async {
    try {
      final raw = await widget.api.webSearch(query);
      final results = raw
          .map((r) => {
                'title': (r['title'] ?? r['name'] ?? '').toString(),
                'url': (r['url'] ?? r['link'] ?? '').toString(),
                'snippet': (r['snippet'] ?? r['description'] ?? r['content'] ?? '').toString(),
              })
          .toList();
      _resolveTyping(
        typing,
        ChatMessage(
          isUser: false,
          text: results.isEmpty ? 'Tidak ada hasil untuk "$query".' : 'Hasil pencarian untuk "$query":',
          searchResults: results,
        ),
      );
    } catch (e) {
      _resolveTyping(typing, ChatMessage(isUser: false, text: '⚠️ Web search gagal: $e'));
    }
    _saveHistory();
  }

  Future<void> _handleDocRequest(String query, ChatMessage typing) async {
    try {
      final answer = await widget.api.askDoc(query);
      _resolveTyping(typing, ChatMessage(isUser: false, text: answer));
    } catch (e) {
      _resolveTyping(typing, ChatMessage(isUser: false, text: '⚠️ Gagal menjawab dari dokumen: $e'));
    }
    _saveHistory();
  }

  /// Tombol ikon foto di input bar — gambar sudah dibaca+base64 di sana,
  /// di sini tinggal tampilkan sebagai bubble user lalu panggil analyzeImage().
  Future<void> _analyzeImage(String base64Image, String mimeType) async {
    final dataUri = 'data:$mimeType;base64,$base64Image';
    final typing = ChatMessage(isUser: false, text: _thinkingText);
    setState(() {
      _messages = [
        ..._messages,
        ChatMessage(isUser: true, text: 'Analisis gambar ini', imageUrl: dataUri),
        typing,
      ];
    });
    _saveHistory();
    _scrollToBottom();
    try {
      final result = await widget.api.analyzeImage(base64Image, prompt: 'Jelaskan gambar ini');
      _resolveTyping(typing, ChatMessage(isUser: false, text: result, isAnalysis: true));
    } catch (e) {
      _resolveTyping(typing, ChatMessage(isUser: false, text: '⚠️ Gagal menganalisis gambar: $e'));
    }
    _saveHistory();
    _scrollToBottom();
  }

  /// "Upload Dokumen" di menu "+" input bar — teks sudah dibaca (UTF-8) di
  /// sana; di sini upload ke backend (RAG) lalu tandai dokumen aktif supaya
  /// pertanyaan berikutnya dijawab lewat askDoc() (lihat _send()).
  Future<void> _uploadDoc(String name, String text) async {
    final typing = ChatMessage(isUser: false, text: _thinkingText);
    setState(() {
      _messages = [..._messages, ChatMessage(isUser: true, text: 'Upload dokumen: $name'), typing];
    });
    _saveHistory();
    _scrollToBottom();
    try {
      await widget.api.uploadDoc(name, text);
      _hasActiveDocument = true;
      _resolveTyping(
        typing,
        ChatMessage(
          isUser: false,
          text: "Dokumen '$name' berhasil diupload (${text.length} karakter). Tanyakan apa saja isinya!",
        ),
      );
    } catch (e) {
      _resolveTyping(typing, ChatMessage(isUser: false, text: '⚠️ Gagal upload dokumen: $e'));
    }
    _saveHistory();
    _scrollToBottom();
  }

  // ---- Aksi popover "+" JeonChatInputBar: tiap callback benar-benar panggil backend ----

  Future<void> _generateImageDirect(String prompt) async {
    final typing = ChatMessage(isUser: false, text: _thinkingText);
    setState(() {
      _messages = [..._messages, ChatMessage(isUser: true, text: 'Buat gambar: $prompt'), typing];
    });
    _saveHistory();
    _scrollToBottom();
    try {
      final url = await widget.api.generateImage(prompt);
      _resolveTyping(typing, ChatMessage(isUser: false, text: '✅ Gambar siap!', imageUrl: url));
    } catch (e) {
      _resolveTyping(typing, ChatMessage(isUser: false, text: '⚠️ Gagal membuat gambar: $e'));
    }
    _saveHistory();
    _scrollToBottom();
  }

  Future<void> _generateAudioDirect(String text) async {
    final typing = ChatMessage(isUser: false, text: _thinkingText);
    setState(() {
      _messages = [..._messages, ChatMessage(isUser: true, text: 'Buat suara: $text'), typing];
    });
    _saveHistory();
    _scrollToBottom();
    try {
      final url = await widget.api.generateTTS(text);
      _resolveTyping(typing, ChatMessage(isUser: false, text: '✅ Audio siap!', audioUrl: url));
    } catch (e) {
      _resolveTyping(typing, ChatMessage(isUser: false, text: '⚠️ Gagal membuat suara: $e'));
    }
    _saveHistory();
    _scrollToBottom();
  }

  Future<void> _generateVideoDirect(String prompt) async {
    final typing = ChatMessage(isUser: false, text: _thinkingText);
    setState(() {
      _messages = [..._messages, ChatMessage(isUser: true, text: 'Buat video: $prompt'), typing];
    });
    _saveHistory();
    _scrollToBottom();
    try {
      final url = await widget.api.generateVideo(prompt);
      _resolveTyping(typing, ChatMessage(isUser: false, text: '✅ Video siap!', videoUrl: url));
    } catch (e) {
      _resolveTyping(typing, ChatMessage(isUser: false, text: '⚠️ Gagal membuat video: $e'));
    }
    _saveHistory();
    _scrollToBottom();
  }

  // Tidak ada endpoint /search khusus di backend — dikirim lewat /agent
  // (endpoint tools-lengkap) dengan instruksi eksplisit, bukan sekadar UI.
  Future<void> _searchWeb(String query) => _send('Cari di internet: $query', 'jeon-chat');

  Future<void> _deepResearch(String topic) => _send('Lakukan riset mendalam tentang: $topic', 'jeon-chat');

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;
    final sidebarOpen = _sidebarOpenOverride ?? true;

    final sidebar = JeonChatSidebar(
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
      onToggleArchive: _toggleArchiveConversation,
      onDeleteConversation: _deleteConversationById,
      onMoveToProject: _moveToProject,
      onClose: () {
        if (isWide) {
          setState(() => _sidebarOpenOverride = false);
        } else {
          Navigator.of(context).maybePop();
        }
      },
      projects: _projects,
      activeProjectId: _activeProjectId,
      onSelectProject: _selectProject,
      onCreateProject: _createProject,
      onRenameProject: _renameProject,
      onUpdateProjectSettings: _updateProjectSettings,
      onPinProject: _pinProject,
      onArchiveProject: _archiveProject,
      onDeleteProject: _deleteProject,
      onClearHistory: _clearAllHistory,
      onProfileChanged: () => setState(() {}),
      onOpenLibrary: () {
        if (!isWide) Navigator.of(context).maybePop();
        _requireAuth(() {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LibraryScreen()));
        });
      },
      onOpenPlugins: () {
        if (!isWide) Navigator.of(context).maybePop();
        _requireAuth(_openPluginsStore);
      },
      onOpenScheduled: () {
        if (!isWide) Navigator.of(context).maybePop();
        _requireAuth(() {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scheduled segera hadir'), duration: Duration(seconds: 1)),
          );
        });
      },
      onOpenMore: () {
        if (!isWide) Navigator.of(context).maybePop();
        _requireAuth(() {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fitur ini segera hadir'), duration: Duration(seconds: 1)),
          );
        });
      },
      installedPlugins: _installedPlugins,
      onSelectPlugin: (title) {
        if (!isWide) Navigator.of(context).maybePop();
        _closePluginsStore();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title aktif'), duration: const Duration(seconds: 1)),
        );
      },
      onDeactivatePlugin: _deactivatePlugin,
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
                const Text('JEON Chat', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: JeonColors.accent),
                    ),
                    const SizedBox(width: 5),
                    const Text('Online',
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
            child: AnimatedOpacity(
              opacity: _messagesOpacity,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: _messages.isEmpty
                  ? _welcomeScreen()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                      itemCount: _messages.length,
                      scrollCacheExtent: const ScrollCacheExtent.pixels(500),
                      itemBuilder: (context, i) => ChatBubble(message: _messages[i]),
                    ),
            ),
          ),
          JeonChatInputBar(
            quickReplies: _quickReplies,
            onSend: _send,
            onGenerateImage: _generateImageDirect,
            onSearchWeb: _searchWeb,
            onDeepResearch: _deepResearch,
            onGenerateAudio: _generateAudioDirect,
            onGenerateVideo: _generateVideoDirect,
            onVoiceModeResult: _onVoiceModeResult,
            activePluginCount: _installedPlugins.length,
            onOpenPlugins: () => _requireAuth(_openPluginsStore),
            modelOptions: _modelOptions,
            onAnalyzeImage: _analyzeImage,
            onWebSearch: (query) async {
              final typing = ChatMessage(isUser: false, text: _thinkingText);
              setState(() {
                _messages = [..._messages, ChatMessage(isUser: true, text: 'Cari: $query'), typing];
              });
              _saveHistory();
              _scrollToBottom();
              await _handleWebSearchRequest(query, typing);
              _scrollToBottom();
            },
            onUploadDoc: _uploadDoc,
          ),
        ],
      ),
    );

    final pluginsStoreScaffold = Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: PluginsStoreView(
          installedTitles: _installedPlugins.map((p) => p.title).toSet(),
          onTogglePlugin: _togglePlugin,
          onBack: _closePluginsStore,
        ),
      ),
    );

    final mainContent = _showPluginsStore ? pluginsStoreScaffold : chatScaffold;

    if (!isWide) return mainContent;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          if (sidebarOpen) SizedBox(width: 260, child: SafeArea(child: sidebar)),
          Expanded(child: mainContent),
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

}
