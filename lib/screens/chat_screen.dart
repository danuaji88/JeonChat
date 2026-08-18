import 'package:flutter/material.dart';

import '../models/agent.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/chat_history_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../widgets/agent_drawer.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/context_sheet.dart';
import '../widgets/typing_indicator.dart';
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
  int _guestMessageCount = 0;

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
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final saved = await ChatHistoryService.load();
    final savedSession = await ChatHistoryService.loadSession();
    if (saved.isNotEmpty) {
      setState(() {
        _messages = saved;
        _agentSession = savedSession;
      });
      _scrollToBottom();
    }
  }

  Future<void> _saveHistory() async {
    await ChatHistoryService.save(_messages, agentSession: _agentSession);
  }

  Future<void> _newChat() async {
    await ChatHistoryService.clear();
    setState(() {
      _messages = [];
      _agentSession = null;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller.dispose();
    _scrollController.dispose();
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
        model: 'jeon-chat',
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
            imageUrl: videoUrl, // pakai imageUrl dulu untuk preview (video player menyusul)
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
          model: 'jeon-chat',
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
          model: 'jeon-chat',
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
    return Scaffold(
      backgroundColor: JeonColors.bg,
      drawer: AgentDrawer(
        agents: _agents,
        api: widget.api,
        profile: widget.profile,
        onClearHistory: _newChat,
        onProfileChanged: () => setState(() {}),
      ),
      appBar: AppBar(
        titleSpacing: 8,
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
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: JeonColors.surface2,
              border: Border.all(color: JeonColors.border),
              borderRadius: BorderRadius.circular(JeonRadius.pill),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, size: 18, color: JeonColors.inkFaint),
                  onPressed: () {},
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
                    decoration: const InputDecoration(
                      hintText: 'Tanya JeonChat apa saja…',
                      hintStyle: TextStyle(color: JeonColors.inkFaint),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(color: JeonColors.accent, shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.send, size: 15, color: Color(0xFF04150A)),
                    onPressed: _send,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
