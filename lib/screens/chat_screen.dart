import 'package:flutter/material.dart';

import '../models/agent.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/agent_drawer.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/context_sheet.dart';

class ChatScreen extends StatefulWidget {
  final ApiService api;

  const ChatScreen({super.key, required this.api});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  late final AnimationController _pulseController;

  // ---- Quick replies (ala UI kit premium) ----
  static const List<String> _quickReplies = [
    'Buat konten video',
    'Analisis video',
    'Buat laporan',
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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int get _runningCount => _agents.where((a) => a.status == AgentStatus.running).length;

  String? _agentSession;

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages = [..._messages, ChatMessage(isUser: true, text: text)];
      _sending = true;
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final result = await widget.api.sendAgentPrompt(
        prompt: text,
        agentSession: _agentSession,
      );
      if (result.agentSession != null) {
        _agentSession = result.agentSession;
      }
      setState(() {
        _messages = [..._messages, ChatMessage(isUser: false, text: result.content)];
      });
    } on AgentTimeoutException catch (e) {
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(isUser: false, text: '⏳ ${e.toString()}'),
        ];
      });
    } catch (e) {
      // Fallback ke /chat kalau /agent gagal
      try {
        final reply = await widget.api.sendChat(
          history: _messages,
          model: 'jeon-chat',
        );
        setState(() {
          _messages = [..._messages, ChatMessage(isUser: false, text: reply)];
        });
      } catch (e2) {
        setState(() {
          _messages = [
            ..._messages,
            ChatMessage(isUser: false, text: '⚠️ ${e2.toString()}'),
          ];
        });
      }
    } finally {
      setState(() => _sending = false);
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
      drawer: AgentDrawer(agents: _agents),
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: JeonColors.accentGlow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: JeonColors.accent.withOpacity(0.25)),
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
            child: ListView.builder(
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
                    maxLines: 4,
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
                    icon: _sending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF04150A)),
                          )
                        : const Icon(Icons.send, size: 15, color: Color(0xFF04150A)),
                    onPressed: _sending ? null : _send,
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
