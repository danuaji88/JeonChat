import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';

/// Thin client for the shared JeonGPT/JeonChat backend API.
///
/// Endpoints (same backend as JeonGPT — /opt/data/jeongpt_api.py):
///   GET  /models
///   POST /chat          body: {messages, model, session_id}
///   POST /chat/history  body: {session_id}
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
      sessionToken: prefs.getString(_prefsSessionTokenKey),
      isGuest: prefs.getBool(_prefsGuestKey) ?? false,
    );
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBaseUrlKey, baseUrl);
    await prefs.setString(_prefsApiKeyKey, apiKey);
    await prefs.setBool(_prefsGuestKey, isGuest);
    if (sessionToken != null && sessionToken!.isNotEmpty) {
      await prefs.setString(_prefsSessionTokenKey, sessionToken!);
    } else {
      await prefs.remove(_prefsSessionTokenKey);
    }
  }

  /// Skips credentials entirely — "Coba Gratis" on the login screen.
  Future<void> continueAsGuest() async {
    isGuest = true;
    await saveToPrefs();
  }

  Future<String> login({required String email, required String password}) async {
    if (!isConfigured) {
      throw ApiException('Base URL belum diatur. Isi Server URL untuk login.');
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
  /// Pakai pola submit + poll untuk hindari timeout Cloudflare.
  Future<AgentResult> sendAgentPrompt({
    required String prompt,
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
        if (agentSession != null) 'session_id': agentSession,
      };
      final res = await http
          .post(_uri('/agent'), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 95), onTimeout: () => throw AgentTimeoutException());

      if (res.statusCode == 504) {
        // Timeout sync → fallback ke async
        return await _agentSubmitPoll(prompt, agentSession);
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
      );
    } on AgentTimeoutException {
      // Sync timeout → fallback ke async submit+poll
      return await _agentSubmitPoll(prompt, agentSession);
    }
  }

  Future<AgentResult> _agentSubmitPoll(String prompt, String? agentSession) async {
    // Submit task
    final submitBody = {
      'prompt': prompt,
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

    // Poll setiap 5 detik, max 60 detik
    for (int i = 0; i < 12; i++) {
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
  Future<String> generateImage(String promptText) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/image'), headers: _headers, body: jsonEncode({'prompt': promptText}))
        .timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) {
      throw ApiException('Image gagal (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['image_url'] ?? data['url'] ?? data['imageUrl'])?.toString() ?? '';
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

class AgentResult {
  final String content;
  final String? agentSession;
  final List<String> fileUrls;
  AgentResult({required this.content, this.agentSession, this.fileUrls = const []});
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
