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

  /// Login sosial via /auth/social — [provider] = 'google'|'tiktok'|'facebook'|
  /// 'github'|'instagram', [token] = ID/access token dari SDK/flow provider terkait.
  Future<Map<String, dynamic>> socialLogin({required String provider, required String token, String name = ''}) async {
    final res = await _post('/auth/social', {'provider': provider, 'token': token, 'name': name});
    final sessionTok = (res['token'] ?? '').toString();
    if (sessionTok.isEmpty) {
      throw ApiException('Login gagal: token tidak ditemukan pada respons server.');
    }
    sessionToken = sessionTok;
    isGuest = false;
    await saveToPrefs();
    return res;
  }

  /// Simpan token dari redirect OAuth (fragment #token=... di URL setelah
  /// backend tukar code → token → redirect ke .../app/#token=..., lihat
  /// SplashScreen._init()) — validasi dulu ke POST /auth/me (body
  /// {"token": ...}, bukan header Authorization — endpoint ini di server
  /// cuma terdaftar sebagai POST) sebelum dipakai sebagai sesi aktif.
  Future<Map<String, dynamic>> restoreSocialSession(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) throw ApiException('Token kosong.');
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/auth/me'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'token': trimmed}))
        .timeout(_shortTimeout, onTimeout: () => throw ApiException('Timeout: server tidak merespons.'));
    if (res.statusCode == 401) {
      throw ApiException('Sesi tidak valid atau sudah kedaluwarsa.');
    }
    if (res.statusCode != 200) {
      throw ApiException('Verifikasi sesi gagal (${res.statusCode}).');
    }
    sessionToken = trimmed;
    isGuest = false;
    await saveToPrefs();
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : {'data': data};
  }

  /// Konfigurasi publik login sosial (tanpa secret) — dipakai tombol OAuth
  /// (TikTok, dsb) untuk mengambil client_key & redirect_uri.
  Future<Map<String, dynamic>> fetchSocialConfig() async {
    final res = await http
        .get(_uri('/auth/social/config'), headers: const {'Content-Type': 'application/json'})
        .timeout(_shortTimeout, onTimeout: () => throw ApiException('Timeout: server tidak merespons.'));
    if (res.statusCode != 200) {
      throw ApiException('Gagal ambil konfigurasi sosial (${res.statusCode}).');
    }
    final data = jsonDecode(res.body);
    return (data is Map<String, dynamic> && data['providers'] is Map<String, dynamic>)
        ? data['providers'] as Map<String, dynamic>
        : <String, dynamic>{};
  }

  /// Upload file biner nyata ke server → /upload/file. [name] = nama file,
  /// [bytes] = isi mentah. Mengembalikan {name, url, size, status}.
  Future<Map<String, dynamic>> uploadFile({required String name, required List<int> bytes}) async {
    final res = await http
        .post(
          _uri('/upload/file'),
          headers: _headers,
          body: jsonEncode({'name': name, 'data_base64': base64Encode(bytes)}),
        )
        .timeout(const Duration(seconds: 60), onTimeout: () => throw ApiException('Timeout: upload melebihi 60 detik.'));
    if (res.statusCode != 200) {
      throw ApiException('Upload gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body);
    return (data is Map<String, dynamic>) ? data : <String, dynamic>{};
  }

  /// Daftar file yang pernah diupload user (maks 50 item terbaru) via
  /// /library — dipakai menu "+" → "Tambah dari Library" di input bar.
  /// {items: [{name, url, kind, size, uploaded_at}], total}.
  Future<Map<String, dynamic>> getLibrary() => _get('/library', timeout: const Duration(seconds: 30));

  // ---- Instruksi Kustom (Fitur #4) via /instructions — backend sudah live,
  // action get/save/clear. {email, about_me, response_style, enabled,
  // updated_at}. ----

  Future<Map<String, dynamic>> getInstructions() => _post('/instructions', {'action': 'get'});

  Future<Map<String, dynamic>> saveInstructions({
    required String aboutMe,
    required String responseStyle,
    required bool enabled,
  }) =>
      _post('/instructions', {
        'action': 'save',
        'about_me': aboutMe,
        'response_style': responseStyle,
        'enabled': enabled,
      });

  Future<Map<String, dynamic>> clearInstructions() => _post('/instructions', {'action': 'clear'});

  /// Langkah 1 login WhatsApp/HP — minta OTP dikirim ke [phone]. Respons:
  /// {ok, message, dev_hint, expires_in} — dev_hint = OTP sementara selama
  /// belum ada gateway SMS/WA asli.
  Future<Map<String, dynamic>> phoneRequestOtp(String phone) => _post('/auth/phone', {'phone': phone});

  /// Langkah 2 — verifikasi OTP, sukses = sesi login tersimpan sama seperti
  /// login sosial lain.
  Future<Map<String, dynamic>> phoneVerifyOtp(String phone, String otp) async {
    final res = await _post('/auth/phone/verify', {'phone': phone, 'otp': otp});
    final sessionTok = (res['token'] ?? '').toString();
    if (sessionTok.isEmpty) {
      throw ApiException('Verifikasi OTP gagal: token tidak ditemukan pada respons server.');
    }
    sessionToken = sessionTok;
    isGuest = false;
    await saveToPrefs();
    return res;
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
    final data = await _get('/models');
    final rawOptions = data['options'];
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

  /// Helper POST generik — decode JSON balasan jadi Map, lempar ApiException
  /// kalau gagal/timeout. Dipakai method-method fitur AI di bawah supaya
  /// tidak mengulang boilerplate headers/timeout/status-check.
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {Duration? timeout}) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(timeout ?? _shortTimeout, onTimeout: () => throw ApiException('Timeout: server tidak merespons.'));
    if (res.statusCode != 200) {
      throw ApiException('$path gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : {'data': data};
  }

  /// Helper GET generik — sama seperti [_post] tapi tanpa body.
  Future<Map<String, dynamic>> _get(String path, {Duration? timeout}) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .get(_uri(path), headers: _headers)
        .timeout(timeout ?? _shortTimeout, onTimeout: () => throw ApiException('Timeout: server tidak merespons.'));
    if (res.statusCode != 200) {
      throw ApiException('$path gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : {'data': data};
  }

  /// Analisis gambar via /analyze — [base64Image] tanpa prefix data URI.
  Future<String> analyzeImage(
    String base64Image, {
    String prompt = 'Jelaskan gambar ini secara detail dalam bahasa Indonesia.',
  }) async {
    final res = await _post('/analyze', {'image_base64': base64Image, 'prompt': prompt},
        timeout: const Duration(seconds: 60));
    return (res['content'] ?? 'Error: tidak ada respons').toString();
  }

  /// Edit gambar via AI (image-to-image) — /image/edit. Kirim gambar sebagai
  /// base64 ATAU URL + prompt instruksi editan (contoh: "hapus botol di meja").
  /// Respons: {image_url, image_path, prompt, provider}. Biaya ~$0.03 (Kie).
  Future<String> editImage({
    required String imageBase64,
    required String prompt,
  }) async {
    final res = await _post('/image/edit', {
      'image_base64': imageBase64,
      'prompt': prompt,
    }, timeout: const Duration(seconds: 250));
    return (res['image_url'] ?? '').toString();
  }

  /// Crop gambar ke rasio (gratis/lokal) — /image/crop.
  /// [ratio] = "1:1", "5:4", "4:3", "16:9", "9:16", "21:9".
  Future<String> cropImage({
    required String imageBase64,
    required String ratio,
  }) async {
    final res = await _post('/image/crop', {
      'image_base64': imageBase64,
      'ratio': ratio,
    }, timeout: const Duration(seconds: 120));
    return (res['image_url'] ?? '').toString();
  }

  /// Overlay teks di gambar (gratis/lokal) — /image/text.
  Future<String> addTextToImage({
    required String imageBase64,
    required String text,
    String position = 'bottom',
    String color = '#FFFFFF',
  }) async {
    final res = await _post('/image/text', {
      'image_base64': imageBase64,
      'text': text,
      'position': position,
      'color': color,
    }, timeout: const Duration(seconds: 120));
    return (res['image_url'] ?? '').toString();
  }

  // ---- Memory: get semua, tambah, hapus per index (dikelompokkan per
  // [kind]), dan pencarian semantik via /memory. ----

  Future<Map<String, dynamic>> getMemory() => _post('/memory', {'action': 'get'});

  Future<void> addMemory(String kind, String text) =>
      _post('/memory', {'action': 'add', 'kind': kind, 'text': text});

  Future<void> removeMemory(String kind, int index) =>
      _post('/memory', {'action': 'remove', 'kind': kind, 'index': index});

  Future<Map<String, dynamic>> clearMemory() => _post('/memory', {'action': 'clear'});

  Future<List<dynamic>> searchMemory(String query) async {
    final res = await _post('/memory', {'action': 'search', 'query': query});
    return (res['results'] as List?) ?? [];
  }

  // ---- Projects/Workspaces (fase 2.2) — grup chat+file+instruksi khusus
  // per project via /projects (action list/create/get/update/delete/
  // add_file/remove_file/add_conversation/remove_conversation). Entity ini
  // BEDA dari project lokal punya ChatHistoryService (warna/ikon/pin/arsip,
  // cuma buat filter sidebar, tidak dikenal backend) — dua-duanya dipakai
  // bareng: ChatHistoryService.createProject dkk. sekarang memanggil method
  // di bawah ini juga supaya id project lokal = id project backend, dan
  // instruksinya bisa disuntikkan AI lewat project_id di /chat & /agent. ----

  Future<List<Map<String, dynamic>>> listProjects() async {
    final res = await _post('/projects', {'action': 'list'});
    final raw = res['projects'] as List?;
    return raw?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
  }

  Future<Map<String, dynamic>> createProject({required String name, String instructions = ''}) async {
    final res = await _post('/projects', {'action': 'create', 'name': name, 'instructions': instructions});
    final project = res['project'];
    return project is Map ? Map<String, dynamic>.from(project) : {};
  }

  Future<Map<String, dynamic>?> getProject(String id) async {
    final res = await _post('/projects', {'action': 'get', 'id': id});
    final project = res['project'];
    return project is Map ? Map<String, dynamic>.from(project) : null;
  }

  Future<Map<String, dynamic>> updateProject(String id, {String? name, String? instructions}) async {
    final res = await _post('/projects', {
      'action': 'update',
      'id': id,
      if (name != null) 'name': name,
      if (instructions != null) 'instructions': instructions,
    });
    final project = res['project'];
    return project is Map ? Map<String, dynamic>.from(project) : {};
  }

  Future<void> deleteProject(String id) => _post('/projects', {'action': 'delete', 'id': id});

  Future<Map<String, dynamic>> addFileToProject(String id, Map<String, dynamic> file) async {
    final res = await _post('/projects', {'action': 'add_file', 'id': id, 'file': file});
    final f = res['file'];
    return f is Map ? Map<String, dynamic>.from(f) : file;
  }

  Future<void> removeFileFromProject(String id, String fileId) =>
      _post('/projects', {'action': 'remove_file', 'id': id, 'file_id': fileId});

  Future<void> addConversationToProject(String id, String conversationId) =>
      _post('/projects', {'action': 'add_conversation', 'id': id, 'conversation_id': conversationId});

  Future<void> removeConversationFromProject(String id, String conversationId) =>
      _post('/projects', {'action': 'remove_conversation', 'id': id, 'conversation_id': conversationId});

  /// Web search via /websearch.
  Future<List<dynamic>> webSearch(String query) async {
    final res = await _post('/websearch', {'query': query, 'max_results': 5}, timeout: const Duration(seconds: 30));
    return (res['results'] as List?) ?? [];
  }

  /// Riset mendalam ala Perplexity via /research — jawaban AI + sitasi [n]
  /// + daftar sumber {title, url, snippet}. Dipakai tombol "Riset Mendalam".
  Future<Map<String, dynamic>> research(String query,
      {int maxSources = 6, String lang = 'id'}) async {
    final res = await _post('/research',
        {'query': query, 'max_sources': maxSources, 'lang': lang},
        timeout: const Duration(seconds: 90));
    return {
      'answer': (res['answer'] ?? '').toString(),
      'sources': (res['sources'] as List?) ?? [],
      'model': (res['model'] ?? '').toString(),
      'source_type': (res['source_type'] ?? '').toString(),
    };
  }

  /// Upload dokumen buat RAG via /upload.
  Future<Map<String, dynamic>> uploadDoc(String name, String text) =>
      _post('/upload', {'name': name, 'text': text}, timeout: const Duration(seconds: 60));

  /// Tanya isi dokumen yang sudah di-upload via /ask.
  Future<Map<String, dynamic>> askDoc(String query) =>
      _post('/ask', {'query': query}, timeout: const Duration(seconds: 60));

  /// Speech-to-text server-side via /stt — pelengkap dikte on-device
  /// (speech_to_text package, sudah dipakai input bar); disiapkan untuk alur
  /// yang kirim rekaman audio langsung, belum ada perekam audio di app ini.
  Future<String> speechToText(String base64Audio) async {
    final res = await _post('/stt', {'audio_base64': base64Audio}, timeout: const Duration(seconds: 30));
    return (res['text'] ?? '').toString();
  }

  /// Kredit/kuota user via /quota — {plan, credits: {total, used, remaining,
  /// cost_per_feature: {...}}}.
  Future<Map<String, dynamic>> getQuota() => _get('/quota');

  /// Ambil history chat dari server (per user, via /history) — dipakai
  /// ChatHistoryService buat sinkronisasi lintas perangkat/incognito.
  /// Null kalau gagal/belum login (bukan error keras, caller anggap
  /// "belum ada data server" dan tetap pakai localStorage).
  Future<Map<String, dynamic>?> getHistory() async {
    try {
      return await _get('/history');
    } catch (_) {
      return null;
    }
  }

  /// Simpan history chat ke server (per user, via /history).
  Future<bool> saveHistory({
    required List<Map<String, dynamic>> conversations,
    required List<Map<String, dynamic>> projects,
  }) async {
    try {
      await _post('/history', {
        'conversations': conversations,
        'projects': projects,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Code Interpreter via /code.
  Future<Map<String, dynamic>> runCode(String code) =>
      _post('/code', {'code': code}, timeout: const Duration(seconds: 60));

  // ---- "Skill Saya" (pengetahuan/instruksi personal user) via /skill —
  // beda dari Custom Skills /skills di bawah (skill workflow yang dijalankan
  // manual lewat runSkill()). Skill di sini TIDAK dipilih manual — backend
  // /agent otomatis menyuntikkannya ke setiap request untuk user itu. ----

  Future<List<Map<String, dynamic>>> listUserSkills() async {
    final res = await _post('/skill', {'action': 'list'});
    final raw = res['skills'] ?? res['items'] ?? res['data'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// {name, slug, content, path} — respons GET action=get bungkus isinya
  /// di bawah key 'skill'.
  Future<Map<String, dynamic>> getUserSkill(String name) async {
    final res = await _post('/skill', {'action': 'get', 'name': name});
    final skill = res['skill'];
    return skill is Map ? Map<String, dynamic>.from(skill) : res;
  }

  Future<void> saveUserSkill(String name, String content) =>
      _post('/skill', {'action': 'save', 'name': name, 'content': content});

  Future<void> deleteUserSkill(String name) => _post('/skill', {'action': 'delete', 'name': name});

  // ---- Custom Skills (CRUD) via /skills. ----

  Future<List<dynamic>> listSkills() async {
    final res = await _post('/skills', {'action': 'list'});
    return (res['skills'] as List?) ?? [];
  }

  Future<Map<String, dynamic>> createSkill(String name, String desc, String instruction) => _post(
      '/skills', {'action': 'create', 'name': name, 'description': desc, 'instruction': instruction});

  Future<void> deleteSkill(String skillId) => _post('/skills', {'action': 'delete', 'skill_id': skillId});

  Future<String> runSkill(String skillId, String input) async {
    final res = await _post('/skills', {'action': 'run', 'skill_id': skillId, 'input': input},
        timeout: const Duration(seconds: 60));
    return (res['content'] ?? 'Error').toString();
  }

  /// [cancelToken] — lihat [CancelToken], dipakai fitur "Stop Generation" di
  /// chat_screen.dart untuk menggugurkan request ini kalau user tap Stop.
  Future<ChatResult> sendChat({
    required List<ChatMessage> history,
    required String model,
    String? sessionId,
    CancelToken? cancelToken,
    bool incognito = false,
    String? projectId,
  }) async {
    if (!isConfigured) {
      throw ApiException('Base URL belum diatur. Buka Settings untuk isi URL backend.');
    }
    if (cancelToken?.isCancelled == true) throw RequestCancelledException();
    final body = {
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        ...history.map((m) => m.toApiJson()),
      ],
      'model': model,
      if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
      if (incognito) 'incognito': true,
      if (projectId != null && projectId.isNotEmpty) 'project_id': projectId,
    };
    final client = http.Client();
    cancelToken?._client = client;
    http.Response res;
    try {
      res = await client
          .post(_uri('/chat'), headers: _headers, body: jsonEncode(body))
          .timeout(_chatTimeout, onTimeout: () => throw ApiException(
              'Timeout: AI tidak merespons dalam 90 detik.'));
    } on http.ClientException {
      if (cancelToken?.isCancelled == true) throw RequestCancelledException();
      rethrow;
    } finally {
      client.close();
    }
    if (res.statusCode != 200) {
      throw ApiException('Chat gagal (${res.statusCode}): ${res.body}');
    }
    final data = jsonDecode(res.body);
    if (data is Map<String, dynamic>) {
      final content = (data['content'] ?? data['reply'] ?? data['response'] ?? '').toString();
      return ChatResult(content: content, artifacts: _parseArtifacts(data['artifacts']));
    }
    return ChatResult(content: data.toString());
  }

  /// Fase 3.1 — kode/dokumen panjang terdeteksi backend (lihat has_artifact/
  /// artifacts di respons /chat). Dipakai juga secara spekulatif untuk
  /// /agent di bawah (belum dikonfirmasi task ada di sana, tapi field JSON
  /// tambahan aman diabaikan backend kalau memang tidak dikenal).
  List<Artifact> _parseArtifacts(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Artifact.fromApiJson(Map<String, dynamic>.from(e))).toList();
  }

  /// Level 3: Hermes Agent penuh (semua tools & skills).
  /// Pakai pola submit + poll untuk hindari timeout Cloudflare. [model]
  /// dikirim ke backend supaya pilihan Fast/High/Think/Vision/Opus di input
  /// bar juga berlaku untuk request yang lewat /agent, bukan cuma fallback
  /// /chat.
  /// [imageUrl]/[attachmentUrl] — URL file yang sudah diupload user lewat
  /// menu "+" (Upload Gambar/Upload File/Tambah dari Library, lihat
  /// input_bar.dart) dan mau disertakan bersama pesan ini. Belum ada kontrak
  /// resmi dari backend untuk field ini di /agent (beda dari /upload/file &
  /// /library yang sudah dikonfirmasi) — nama field dipilih mengikuti saran
  /// eksplisit dari task, dan URL-nya JUGA disisipkan sebagai teks di
  /// [prompt] (lihat pemanggil di chat_screen.dart) sebagai jaring pengaman
  /// kalau field JSON ini ternyata tidak diparse backend.
  /// [cancelToken] — lihat [CancelToken], dipakai fitur "Stop Generation".
  Future<AgentResult> sendAgentPrompt({
    required String prompt,
    required String model,
    String? agentSession,
    List<String> plugins = const [],
    String? imageUrl,
    String? attachmentUrl,
    CancelToken? cancelToken,
    String? projectId,
  }) async {
    if (!isConfigured) {
      throw ApiException('Base URL belum diatur. Buka Settings untuk isi URL backend.');
    }
    if (cancelToken?.isCancelled == true) throw RequestCancelledException();
    // Satu client dipakai sepanjang alur (sync + fallback submit+poll) supaya
    // satu cancelToken.cancel() menggugurkan tahap mana pun yang sedang aktif.
    final client = http.Client();
    cancelToken?._client = client;

    // Strategi: coba sync dulu (untuk request cepat <90s).
    // Kalau timeout, fallback ke async submit+poll.
    try {
      final body = {
        'prompt': prompt,
        'model': model,
        if (agentSession != null) 'session_id': agentSession,
        if (plugins.isNotEmpty) 'plugins': plugins,
        if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
        if (attachmentUrl != null && attachmentUrl.isNotEmpty) 'attachment_url': attachmentUrl,
        // Kontrak backend cuma mengonfirmasi project_id di /chat (lihat
        // task) — disisipkan juga di /agent sebagai jaring pengaman
        // (pola sama seperti image_url/attachment_url di atas), TIDAK
        // dijamin backend /agent benar-benar memprosesnya.
        if (projectId != null && projectId.isNotEmpty) 'project_id': projectId,
      };
      final res = await client
          .post(_uri('/agent'), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 95), onTimeout: () => throw AgentTimeoutException());

      if (res.statusCode == 504) {
        // Timeout sync → fallback ke async
        return await _agentSubmitPoll(prompt, model, agentSession, plugins,
            imageUrl: imageUrl, attachmentUrl: attachmentUrl, client: client, cancelToken: cancelToken,
            projectId: projectId);
      }
      if (res.statusCode != 200) {
        throw ApiException('Agent gagal (${res.statusCode}): ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final fileUrls = (data['file_urls'] as List?)?.cast<String>() ?? [];
      final pluginsUsed = (data['plugins_used'] as List?)?.cast<String>() ?? [];
      return AgentResult(
        content: (data['content'] ?? '').toString(),
        agentSession: data['agent_session']?.toString(),
        fileUrls: fileUrls,
        model: data['model']?.toString(),
        pluginsUsed: pluginsUsed,
        artifacts: _parseArtifacts(data['artifacts']),
      );
    } on AgentTimeoutException {
      // Sync timeout → fallback ke async submit+poll
      return await _agentSubmitPoll(prompt, model, agentSession, plugins,
          imageUrl: imageUrl, attachmentUrl: attachmentUrl, client: client, cancelToken: cancelToken,
          projectId: projectId);
    } on http.ClientException {
      if (cancelToken?.isCancelled == true) throw RequestCancelledException();
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<AgentResult> _agentSubmitPoll(
      String prompt, String model, String? agentSession, List<String> plugins,
      {String? imageUrl,
      String? attachmentUrl,
      required http.Client client,
      CancelToken? cancelToken,
      String? projectId}) async {
    // Submit task
    final submitBody = {
      'prompt': prompt,
      'model': model,
      if (agentSession != null) 'session_id': agentSession,
      if (plugins.isNotEmpty) 'plugins': plugins,
      if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
      if (attachmentUrl != null && attachmentUrl.isNotEmpty) 'attachment_url': attachmentUrl,
      if (projectId != null && projectId.isNotEmpty) 'project_id': projectId,
    };
    http.Response submitRes;
    try {
      submitRes = await client
          .post(_uri('/agent/submit'), headers: _headers, body: jsonEncode(submitBody))
          .timeout(_shortTimeout);
    } on http.ClientException {
      if (cancelToken?.isCancelled == true) throw RequestCancelledException();
      rethrow;
    }

    if (submitRes.statusCode != 200) {
      throw ApiException('Agent submit gagal (${submitRes.statusCode})');
    }
    final submitData = jsonDecode(submitRes.body) as Map<String, dynamic>;
    final taskId = submitData['task_id']?.toString();
    if (taskId == null) {
      throw ApiException('Agent submit: task_id tidak ditemukan');
    }

    // Poll setiap 5 detik, max 180 detik (agent berat butuh waktu) — cek
    // cancelToken sebelum & sesudah tiap jeda supaya Stop tetap responsif
    // (maks ~5 detik) walau sedang di antara dua panggilan poll.
    for (int i = 0; i < 36; i++) {
      if (cancelToken?.isCancelled == true) throw RequestCancelledException();
      await Future.delayed(const Duration(seconds: 5));
      if (cancelToken?.isCancelled == true) throw RequestCancelledException();
      http.Response pollRes;
      try {
        pollRes = await client
            .post(_uri('/agent/poll'), headers: _headers, body: jsonEncode({'task_id': taskId}))
            .timeout(_shortTimeout);
      } on http.ClientException {
        if (cancelToken?.isCancelled == true) throw RequestCancelledException();
        rethrow;
      }
      if (pollRes.statusCode != 200) continue;
      final pollData = jsonDecode(pollRes.body) as Map<String, dynamic>;
      final status = pollData['status']?.toString();
      if (status == 'done') {
        final fileUrls = (pollData['file_urls'] as List?)?.cast<String>() ?? [];
        final pluginsUsed = (pollData['plugins_used'] as List?)?.cast<String>() ?? [];
        return AgentResult(
          content: (pollData['content'] ?? '').toString(),
          agentSession: pollData['agent_session']?.toString(),
          fileUrls: fileUrls,
          model: pollData['model']?.toString(),
          pluginsUsed: pluginsUsed,
          artifacts: _parseArtifacts(pollData['artifacts']),
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

  /// Generate TTS via /tts endpoint (gratis: Edge Ardi) — [voiceId] opsional,
  /// dari suara yang dipilih user di Voice Studio (lihat getVoices()).
  /// Kosong/null = pakai suara default backend.
  Future<String> generateTTS(String text, {String? voiceId}) async {
    if (!isConfigured) throw ApiException('Base URL belum diatur.');
    final res = await http
        .post(_uri('/tts'), headers: _headers, body: jsonEncode({
          'text': text,
          if (voiceId != null && voiceId.isNotEmpty) 'voice_id': voiceId,
        }))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw ApiException('TTS gagal (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['audio_url'] ?? data['url'] ?? data['audioUrl'])?.toString() ?? '';
  }

  /// Daftar suara TTS Indonesia (Voice Studio) via GET /voices/api —
  /// {total, voices: [{voice_id, name, gender, age, descriptive, category,
  /// kelompok, preview_url, cloned_by_count}, ...]}.
  Future<Map<String, dynamic>> getVoices() => _get('/voices/api', timeout: const Duration(seconds: 30));

  // ---- Tugas Terjadwal & Notifikasi (fase 3.3) via /tasks & /notifications
  // — action get/create/update/delete/toggle & list/mark_read/mark_all_read/
  // clear. schedule_type: once/interval/daily/weekly/cron (lihat
  // tasks_screen.dart untuk format nilainya masing-masing). ----

  Future<List<Map<String, dynamic>>> listTasks() async {
    final res = await _post('/tasks', {'action': 'list'});
    final raw = res['tasks'] as List?;
    return raw?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
  }

  Future<Map<String, dynamic>> createTask({
    required String title,
    required String message,
    required String scheduleType,
    required String scheduleValue,
  }) async {
    final res = await _post('/tasks', {
      'action': 'create',
      'title': title,
      'message': message,
      'schedule_type': scheduleType,
      'schedule_value': scheduleValue,
    });
    final task = res['task'];
    return task is Map ? Map<String, dynamic>.from(task) : {};
  }

  Future<Map<String, dynamic>> updateTask(
    String id, {
    String? title,
    String? message,
    String? scheduleType,
    String? scheduleValue,
    bool? enabled,
  }) async {
    final res = await _post('/tasks', {
      'action': 'update',
      'id': id,
      if (title != null) 'title': title,
      if (message != null) 'message': message,
      if (scheduleType != null) 'schedule_type': scheduleType,
      if (scheduleValue != null) 'schedule_value': scheduleValue,
      if (enabled != null) 'enabled': enabled,
    });
    final task = res['task'];
    return task is Map ? Map<String, dynamic>.from(task) : {};
  }

  Future<void> deleteTask(String id) => _post('/tasks', {'action': 'delete', 'id': id});

  Future<Map<String, dynamic>> toggleTask(String id) async {
    final res = await _post('/tasks', {'action': 'toggle', 'id': id});
    final task = res['task'];
    return task is Map ? Map<String, dynamic>.from(task) : {};
  }

  /// {notifications: [...], unread: N} — [unread] dipakai badge lonceng di
  /// sidebar (lihat _pollNotifications di chat_screen.dart).
  Future<Map<String, dynamic>> listNotifications() => _post('/notifications', {'action': 'list'});

  Future<void> markNotificationRead(String id) =>
      _post('/notifications', {'action': 'mark_read', 'id': id});

  Future<void> markAllNotificationsRead() => _post('/notifications', {'action': 'mark_all_read'});

  Future<void> clearNotifications() => _post('/notifications', {'action': 'clear'});

  // ---- Feedback Rating (fase 4.1) via /feedback — action rate/delete.
  // [messageId] sintetis ("{conversationId}_{index}", lihat _messageId di
  // chat_screen.dart) karena ChatMessage belum punya id asli dari backend.
  // Kontrak /feedback tidak menyebutkan response 'rate' punya id feedback
  // terpisah, jadi [deleteFeedback] dipanggil dengan messageId yang sama
  // (satu pesan cuma bisa punya satu rating aktif, jadi messageId juga
  // valid dipakai sebagai kunci hapus). ----

  Future<Map<String, dynamic>> sendFeedback(String messageId, String rating, {String comment = ''}) =>
      _post('/feedback', {
        'action': 'rate',
        'message_id': messageId,
        'rating': rating,
        'comment': comment,
      });

  Future<void> deleteFeedback(String id) => _post('/feedback', {'action': 'delete', 'id': id});
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
  final List<String> pluginsUsed;
  final List<Artifact> artifacts;
  AgentResult({
    required this.content,
    this.agentSession,
    this.fileUrls = const [],
    this.model,
    this.pluginsUsed = const [],
    this.artifacts = const [],
  });
}

/// Hasil sendChat() (fase 3.1) — dulunya cuma String, sekarang membawa
/// [artifacts] juga (kode/dokumen panjang terdeteksi backend).
class ChatResult {
  final String content;
  final List<Artifact> artifacts;
  ChatResult({required this.content, this.artifacts = const []});
}

/// Token pembatal untuk sendChat()/sendAgentPrompt() (Fitur "Stop Generation")
/// — package:http tidak punya cancel-token bawaan seperti Dio, jadi ini
/// bungkus http.Client() yang bisa di-close() paksa dari luar untuk
/// menggugurkan request yang sedang berjalan. [cancel] juga men-set flag
/// [isCancelled] supaya poll loop di _agentSubmitPoll bisa berhenti di
/// antara jeda (bukan cuma saat ada request HTTP aktif untuk digugurkan).
class CancelToken {
  http.Client? _client;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _client?.close();
  }
}

/// Dilempar saat request dibatalkan lewat [CancelToken.cancel] — dibedakan
/// dari error jaringan asli supaya pemanggil tahu ini disengaja user (tidak
/// perlu fallback ke /chat atau tampilkan pesan error).
class RequestCancelledException implements Exception {
  @override
  String toString() => 'Dibatalkan oleh pengguna';
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
