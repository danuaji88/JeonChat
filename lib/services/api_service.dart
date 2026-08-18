import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';

/// Thin client for the shared JEON backend API (chat.jeonlive.com).
///
/// Endpoints actually verified against the live server:
///   GET  /models
///   POST /chat   body: {messages: [{role, content}], model, session_id} → {content, ...}
///   POST /agent  body: {prompt, session_id?} → {content, agent_session, ...}
/// Note: there is no working /chat/history endpoint on this backend (confirmed
/// 404) — conversation lists are managed locally via ChatHistoryService.
class ApiService {
  String baseUrl;
  String apiKey;
  String? sessionToken;
  bool isGuest;

  ApiService({
    required this.baseUrl,
    required this.apiKey,
    this.sessionToken,
    this.isGuest = false,
  });

  static const _prefsBaseUrlKey = 'jeonchat_base_url';
  static const _prefsApiKeyKey = 'jeonchat_api_key';
  static const _prefsSessionTokenKey = 'jeonchat_session_token';
  static const _prefsGuestKey = 'jeonchat_guest_mode';

  static const String defaultBaseUrl = 'https://chat.jeonlive.com';

  bool get isLoggedIn => sessionToken != null && sessionToken!.isNotEmpty;

  /// True once the user has either logged in or chosen "Coba Gratis".
  bool get isAuthenticated => isLoggedIn || isGuest;

  static Future<ApiService> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return ApiService(
      baseUrl: prefs.getString(_prefsBaseUrlKey) ?? defaultBaseUrl,
      apiKey: prefs.getString(_prefsApiKeyKey) ?? 'jeongpt-demo',
      sessionToken: _decodeToken(prefs.getString(_prefsSessionTokenKey)),
      isGuest: prefs.getBool(_prefsGuestKey) ?? false,
    );
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBaseUrlKey, baseUrl);
    await prefs.setString(_prefsApiKeyKey, apiKey);
    await prefs.setBool(_prefsGuestKey, isGuest);
    if (sessionToken != null && sessionToken!.isNotEmpty) {
      await prefs.setString(_prefsSessionTokenKey, _encodeToken(sessionToken!));
    } else {
      await prefs.remove(_prefsSessionTokenKey);
    }
  }

  // Bukan enkripsi sungguhan (SharedPreferences di web = localStorage, tetap
  // bisa dibaca lewat devtools) — cuma memastikan token tidak nangkring
  // sebagai string plain text di storage, sesuai permintaan.
  static String _encodeToken(String token) => base64Encode(utf8.encode(token));

  static String? _decodeToken(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return null; // Data lama sebelum encoding ini ada — anggap belum login.
    }
  }

  /// Skips credentials entirely — "Coba Gratis" on the login screen.
  Future<void> continueAsGuest() async {
    isGuest = true;
    await saveToPrefs();
  }

  Future<String> login({required String email, required String password}) async {
    if (!isConfigured) {
      throw ApiException('Base URL belum diatur.');
    }
    final res = await http
        .post(
          _uri('/auth/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_shortTimeout, onTimeout: () => throw ApiException(
            'Timeout: server tidak merespons.'));
    if (res.statusCode != 200) {
      throw ApiException('Login gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body);
    final token = (data is Map<String, dynamic>)
        ? (data['token'] ?? data['session_token'] ?? data['access_token'])?.toString()
        : null;
    if (token == null || token.isEmpty) {
      throw ApiException('Login gagal: token tidak ditemukan pada respons server.');
    }
    sessionToken = token;
    await saveToPrefs();
    return token;
  }

  /// Login langsung pakai token JeonChat (didapat dari alur /register) —
  /// diverifikasi ke /quota dulu sebelum disimpan sebagai sessionToken.
  Future<void> loginWithToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw ApiException('Token tidak boleh kosong.');
    }
    if (!isConfigured) {
      throw ApiException('Base URL belum diatur.');
    }
    final res = await http
        .get(_uri('/quota'), headers: {'Authorization': 'Bearer $trimmed'})
        .timeout(_shortTimeout, onTimeout: () => throw ApiException('Timeout: server tidak merespons.'));
    if (res.statusCode == 401) {
      throw ApiException('Token tidak valid atau sudah kedaluwarsa.');
    }
    if (res.statusCode != 200) {
      throw ApiException('Verifikasi token gagal (${res.statusCode}).');
    }
    sessionToken = trimmed;
    isGuest = false;
    await saveToPrefs();
  }

  Future<String> register({required String name, required String email, required String password}) async {
    if (!isConfigured) {
      throw ApiException('Base URL belum diatur.');
    }
    final res = await http
        .post(
          _uri('/auth/register'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'name': name, 'email': email, 'password': password}),
        )
        .timeout(_shortTimeout, onTimeout: () => throw ApiException('Timeout: server tidak merespons.'));
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw ApiException('Daftar gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body);
    final token = (data is Map<String, dynamic>)
        ? (data['token'] ?? data['session_token'] ?? data['access_token'])?.toString()
        : null;
    if (token == null || token.isEmpty) {
      throw ApiException('Daftar berhasil, tapi token tidak ditemukan pada respons server. Silakan masuk manual.');
    }
    sessionToken = token;
    isGuest = false;
    await saveToPrefs();
    return token;
  }

  Future<void> logout() async {
    sessionToken = null;
    isGuest = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsSessionTokenKey);
    await prefs.remove(_prefsGuestKey);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${sessionToken ?? apiKey}',
      };

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  static const _shortTimeout = Duration(seconds: 15);
  static const _chatTimeout = Duration(seconds: 90);

  bool get isConfigured => baseUrl.isNotEmpty;

  // Sama dengan system prompt versi Telegram — dikirim sebagai pesan
  // pertama (role "system") di setiap request /chat, sebelum riwayat user.
  static const _systemPrompt = "Kamu adalah JEON Chat, asisten AI untuk owner JEON (M Joko Lukito). "
      "Panggil owner 'Appa Jeon'. "
      "Kamu punya tools: video editor, AI clipper, image generator, TTS, sound effects, "
      "filter foto/video, laporan multi-format, dan 103 skill. "
      "Jawab dalam bahasa Indonesia, gaya natural, bantu end-to-end. "
      "Kalau diminta buat video/gambar/suara, bilang kamu bisa bantu via tools JEON. "
      "Tidak perlu bilang 'aku tidak bisa' — bilang 'aku bisa bantu lewat tools JEON'.";

  Future<List<String>> getModels() async {
    if (!isConfigured) throw ApiException('Base URL belum diatur di Settings.');
    final res = await http
        .get(_uri('/models'), headers: _headers)
        .timeout(_shortTimeout, onTimeout: () => throw ApiException(
            'Timeout: server tidak merespons.'));
    if (res.statusCode != 200) {
      throw ApiException('Gagal memuat model (${res.statusCode})');
    }
    final data = jsonDecode(res.body);
    final list = (data is List) ? data : (data['models'] as List? ?? []);
    return list.map((e) => e.toString()).toList();
  }

  /// Daftar model buat dropdown input bar ({label, value, emoji}) — GET
  /// /models sudah menyertakan field 'options'. Kalau field itu tidak ada
  /// atau requestnya gagal, caller pakai [fallbackModelOptions].
  Future<List<ModelOption>> getModelOptions() async {
    if (!isConfigured) throw ApiException('Base URL belum diatur di Settings.');
    final res = await http
        .get(_uri('/models'), headers: _headers)
        .timeout(_shortTimeout, onTimeout: () => throw ApiException('Timeout: server tidak merespons.'));
    if (res.statusCode != 200) {
      throw ApiException('Gagal memuat model (${res.statusCode})');
    }
    final data = jsonDecode(res.body);
    final rawOptions = (data is Map<String, dynamic>) ? data['options'] : null;
    if (rawOptions is! List || rawOptions.isEmpty) {
      throw ApiException('Model options tidak ditemukan pada respons /models');
    }
    final options = rawOptions
        .whereType<Map>()
        .map((o) => ModelOption(
              label: (o['label'] ?? o['name'] ?? '').toString(),
              value: (o['value'] ?? o['id'] ?? o['model'] ?? '').toString(),
              emoji: (o['emoji'] ?? '').toString(),
            ))
        .where((o) => o.value.isNotEmpty)
        .toList();
    if (options.isEmpty) {
      throw ApiException('Model options tidak ditemukan pada respons /models');
    }
    return options;
  }

  /// Dipakai kalau /models tidak menyertakan 'options' atau request gagal.
  static const List<ModelOption> fallbackModelOptions = [
    ModelOption(label: 'Fast', value: 'jeon-fast', emoji: '⚡️'),
    ModelOption(label: 'High', value: 'jeon-chat', emoji: '🎯'),
    ModelOption(label: 'Think', value: 'ds/deepseek-reasoner', emoji: '🧠'),
    ModelOption(label: 'Vision', value: 'gemini/gemini-3.6-flash', emoji: '👁'),
    ModelOption(label: 'Opus', value: 'anthropic/claude-opus-5', emoji: '💎'),
  ];

  /// Analisis gambar via /analyze — [base64Image] tanpa prefix data URI.
  Future<String> analyzeImage(String base64Image, {String prompt = 'Jelaskan gambar ini'}) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/analyze'), headers: _headers,
            body: jsonEncode({'image_base64': base64Image, 'prompt': prompt}))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw ApiException('Analisis gambar gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) {
      return (data['content'] ?? data['result'] ?? data['answer'] ?? '').toString();
    }
    return data.toString();
  }

  /// Memory user via /memory — action get/add/remove sesuai kebutuhan
  /// caller (kind+text untuk add, index untuk remove).
  Future<Map<String, dynamic>> getMemory({
    String action = 'get',
    String? kind,
    String? text,
    int? index,
  }) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final body = {
      'action': action,
      if (kind != null) 'kind': kind,
      if (text != null) 'text': text,
      if (index != null) 'index': index,
    };
    final res = await http
        .post(_uri('/memory'), headers: _headers, body: jsonEncode(body))
        .timeout(_shortTimeout);
    if (res.statusCode != 200) {
      throw ApiException('Memory gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : {'data': data};
  }

  /// Web search via /websearch.
  Future<List<Map<String, dynamic>>> webSearch(String query) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/websearch'), headers: _headers,
            body: jsonEncode({'query': query, 'max_results': 5}))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw ApiException('Web search gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body);
    final list = (data is List)
        ? data
        : (data is Map<String, dynamic> ? (data['results'] ?? data['data'] ?? []) : []);
    return (list as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Upload dokumen buat RAG via /upload — return doc_id.
  Future<String> uploadDoc(String name, String text) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/upload'), headers: _headers, body: jsonEncode({'name': name, 'text': text}))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw ApiException('Upload dokumen gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['doc_id'] ?? data['id'] ?? '').toString();
  }

  /// Tanya isi dokumen yang sudah di-upload via /ask.
  Future<String> askDoc(String query) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/ask'), headers: _headers, body: jsonEncode({'query': query}))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw ApiException('Tanya dokumen gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['answer'] ?? data['content'] ?? '').toString();
  }

  Future<String> sendChat({
    required List<ChatMessage> history,
    required String model,
    String? sessionId,
  }) async {
    if (!isConfigured) {
      throw ApiException('Base URL belum diatur. Buka Settings untuk isi URL backend.');
    }
    final body = {
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        ...history.map((m) => m.toApiJson()),
      ],
      'model': model,
      if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
    };
    final res = await http
        .post(_uri('/chat'), headers: _headers, body: jsonEncode(body))
        .timeout(_chatTimeout, onTimeout: () => throw ApiException(
            'Timeout: AI tidak merespons dalam 90 detik.'));
    if (res.statusCode != 200) {
      throw ApiException('Chat gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) {
      return (data['content'] ?? data['reply'] ?? data['response'] ?? '').toString();
    }
    return data.toString();
  }

  /// Level 3: Hermes Agent penuh (semua tools & skills).
  /// Pakai pola submit + poll untuk hindari timeout Cloudflare. [model]
  /// dikirim ke backend supaya pilihan Fast/High/Think/Vision/Opus di input
  /// bar juga berlaku untuk request yang lewat /agent, bukan cuma fallback
  /// /chat.
  Future<AgentResult> sendAgentPrompt({
    required String prompt,
    required String model,
    String? agentSession,
  }) async {
    if (!isConfigured) {
      throw ApiException('Base URL belum diatur. Buka Settings untuk isi URL backend.');
    }

    // Strategi: coba sync dulu (untuk request cepat <90s).
    // Kalau timeout, fallback ke async submit+poll.
    try {
      final body = {
        'prompt': prompt,
        'model': model,
        if (agentSession != null) 'session_id': agentSession,
      };
      final res = await http
          .post(_uri('/agent'), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 95), onTimeout: () => throw AgentTimeoutException());

      if (res.statusCode == 504) {
        // Timeout sync → fallback ke async
        return await _agentSubmitPoll(prompt, model, agentSession);
      }
      if (res.statusCode != 200) {
        throw ApiException('Agent gagal (${res.statusCode}): ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final fileUrls = (data['file_urls'] as List?)?.cast<String>() ?? [];
      return AgentResult(
        content: (data['content'] ?? '').toString(),
        agentSession: data['agent_session']?.toString(),
        fileUrls: fileUrls,
        model: data['model']?.toString(),
      );
    } on AgentTimeoutException {
      // Sync timeout → fallback ke async submit+poll
      return await _agentSubmitPoll(prompt, model, agentSession);
    }
  }

  Future<AgentResult> _agentSubmitPoll(String prompt, String model, String? agentSession) async {
    // Submit task
    final submitBody = {
      'prompt': prompt,
      'model': model,
      if (agentSession != null) 'session_id': agentSession,
    };
    final submitRes = await http
        .post(_uri('/agent/submit'), headers: _headers, body: jsonEncode(submitBody))
        .timeout(_shortTimeout);

    if (submitRes.statusCode != 200) {
      throw ApiException('Agent submit gagal (${submitRes.statusCode})');
    }
    final submitData = jsonDecode(submitRes.body) as Map<String, dynamic>;
    final taskId = submitData['task_id']?.toString();
    if (taskId == null) {
      throw ApiException('Agent submit: task_id tidak ditemukan');
    }

    // Poll setiap 5 detik, max 180 detik (agent berat butuh waktu)
    for (int i = 0; i < 36; i++) {
      await Future.delayed(const Duration(seconds: 5));
      final pollRes = await http
          .post(_uri('/agent/poll'), headers: _headers, body: jsonEncode({'task_id': taskId}))
          .timeout(_shortTimeout);
      if (pollRes.statusCode != 200) continue;
      final pollData = jsonDecode(pollRes.body) as Map<String, dynamic>;
      final status = pollData['status']?.toString();
      if (status == 'done') {
        final fileUrls = (pollData['file_urls'] as List?)?.cast<String>() ?? [];
        return AgentResult(
          content: (pollData['content'] ?? '').toString(),
          agentSession: pollData['agent_session']?.toString(),
          fileUrls: fileUrls,
          model: pollData['model']?.toString(),
        );
      }
      if (status == 'error') {
        throw ApiException('Agent error: ${pollData['error']}');
      }
      // status == 'running' → keep polling
    }
    throw AgentTimeoutException();
  }

  /// Generate image via /image endpoint (gratis: Pollinations)
  Future<String> generateImage(String promptText, {bool allowAi = true}) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/image'),
            headers: _headers, body: jsonEncode({'prompt': promptText, 'allow_ai': allowAi}))
        .timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) {
      throw ApiException('Image gagal (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['image_url'] ?? data['url'] ?? data['imageUrl'])?.toString() ?? '';
  }

  /// Media pipeline cepat — gambar via /media/image (gratis dulu: library/Openverse/Wikimedia/Pollinations)
  Future<String> generateMediaImage(String promptText, {bool allowAi = false}) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/media/image'), headers: _headers,
            body: jsonEncode({'prompt': promptText, 'allow_ai': allowAi}))
        .timeout(const Duration(seconds: 120));
    if (res.statusCode != 200) {
      throw ApiException('Gambar gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['image_url']?.toString() ?? '';
  }

  /// Media pipeline cepat — video via /media/video (gratis dulu: library/Openverse/Wikimedia)
  Future<String> generateMediaVideo(String promptText, {bool allowAi = false}) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/media/video'), headers: _headers,
            body: jsonEncode({'prompt': promptText, 'allow_ai': allowAi}))
        .timeout(const Duration(seconds: 180));
    if (res.statusCode != 200) {
      throw ApiException('Video gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['video_url']?.toString() ?? '';
  }

  /// Generate video via /video endpoint.
  Future<String> generateVideo(String promptText) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/video'), headers: _headers, body: jsonEncode({'prompt': promptText}))
        .timeout(const Duration(seconds: 180));
    if (res.statusCode != 200) {
      throw ApiException('Video gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['video_url'] ?? data['url'] ?? data['videoUrl'])?.toString() ?? '';
  }

  /// Generate TTS via /tts endpoint (gratis: Edge Ardi)
  Future<String> generateTTS(String text) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/tts'), headers: _headers, body: jsonEncode({'text': text}))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw ApiException('TTS gagal (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['audio_url'] ?? data['url'] ?? data['audioUrl'])?.toString() ?? '';
  }
}

/// Satu opsi di dropdown model input bar — dari GET /models 'options' atau
/// [ApiService.fallbackModelOptions].
class ModelOption {
  final String label;
  final String value;
  final String emoji;
  const ModelOption({required this.label, required this.value, this.emoji = ''});
}

class AgentResult {
  final String content;
  final String? agentSession;
  final List<String> fileUrls;
  final String? model;
  AgentResult({required this.content, this.agentSession, this.fileUrls = const [], this.model});
}

class AgentTimeoutException implements Exception {
  final String message;
  AgentTimeoutException([this.message = 'Agent sedang bekerja, mohon tunggu... (request berat, butuh waktu lebih lama)']);
  @override
  String toString() => message;
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
