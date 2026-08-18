import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import 'api_service.dart';

/// Simpan & muat percakapan multi-conversation ke SharedPreferences
/// (localStorage di web) SEKALIGUS sinkron ke server via /history (kalau
/// user login — lihat [enableServerSync]) supaya tidak hilang di
/// incognito/pindah perangkat. localStorage tetap dipertahankan sebagai
/// cache offline & sumber data untuk guest (belum login, /history butuh
/// token). Tiap conversation:
/// {id, title, messages, pinned, createdAt, updatedAt, agentSession}.
class ChatHistoryService {
  static const _conversationsKey = 'jeon_chat_conversations';
  static const _projectsKey = 'jeon_chat_projects';

  // Key skema lama (satu daftar pesan flat) — dipertahankan hanya untuk
  // migrasi satu-kali ke conversation pertama, lalu dihapus.
  static const _legacyKey = 'jeonchat_history';
  static const _legacySessionKey = 'jeonchat_agent_session';

  // ---- Sinkronisasi server (/history) ----

  /// Kalau true, [syncFromServer] & [pushToServer] beneran jalan — diaktifkan
  /// sekali lewat [enableServerSync] saat user punya sesi login.
  static bool _serverSyncEnabled = false;
  static ApiService? _api;
  static bool _syncing = false;
  static Timer? _pushDebounce;

  /// Aktifkan sinkronisasi server — dipanggil begitu ada sesi login (app
  /// start dengan token tersimpan, atau baru saja login/register/social).
  static void enableServerSync(ApiService api) {
    _serverSyncEnabled = true;
    _api = api;
  }

  /// Ambil conversations+projects dari server, merge dengan localStorage.
  /// Strategi: server = sumber kebenaran utama untuk id yang sama. Kalau
  /// server kosong tapi lokal ada (user lama/guest yang baru login),
  /// migrasi: push lokal ke server. Kalau server ada isinya, conversation
  /// lokal yang id-nya TIDAK ada di server tetap dipertahankan (mis. belum
  /// sempat ke-push), digabung di depan lalu ditulis ulang ke localStorage
  /// sebagai cache offline.
  static Future<void> syncFromServer() async {
    if (!_serverSyncEnabled || _api == null || _syncing) return;
    _syncing = true;
    try {
      final remote = await _api!.getHistory();
      if (remote == null) return;
      final remoteConvs = (remote['conversations'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
      final remoteProjects = (remote['projects'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];

      final prefs = await SharedPreferences.getInstance();
      final localConvs = await _readConversations(prefs);

      if (remoteConvs.isEmpty && localConvs.isNotEmpty) {
        // Migrasi: lokal ada, server kosong → push lokal ke server.
        await _pushToServer(localConvs, await _readProjects(prefs));
        return;
      }
      if (remoteConvs.isNotEmpty) {
        // Merge: server menang; tambahkan lokal yang id-nya tidak ada di server.
        final remoteIds = remoteConvs.map((c) => c['id']).toSet();
        final extraLocal = localConvs.where((c) => !remoteIds.contains(c['id'])).toList();
        final merged = [...extraLocal, ...remoteConvs];
        merged.sort((a, b) {
          final pinnedA = a['pinned'] == true;
          final pinnedB = b['pinned'] == true;
          if (pinnedA != pinnedB) return pinnedA ? -1 : 1;
          return ((b['updatedAt'] as int?) ?? 0).compareTo((a['updatedAt'] as int?) ?? 0);
        });
        await _writeConversations(prefs, merged);
        await _writeProjects(prefs, remoteProjects);
      }
    } finally {
      _syncing = false;
    }
  }

  /// Push semua conversations+projects (dari localStorage saat ini) ke server.
  static Future<void> pushToServer() async {
    if (!_serverSyncEnabled || _api == null || _syncing) return;
    _syncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final convs = await _readConversations(prefs);
      final projs = await _readProjects(prefs);
      await _pushToServer(convs, projs);
    } finally {
      _syncing = false;
    }
  }

  static Future<void> _pushToServer(List<Map<String, dynamic>> convs, List<Map<String, dynamic>> projs) async {
    if (_api == null) return;
    await _api!.saveHistory(conversations: convs, projects: projs);
  }

  static Future<List<Map<String, dynamic>>> _readConversations(SharedPreferences prefs) async {
    final raw = prefs.getString(_conversationsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeConversations(SharedPreferences prefs, List<Map<String, dynamic>> list) async {
    await prefs.setString(_conversationsKey, jsonEncode(list));
  }

  /// Migrasi satu-kali dari skema lama (1 daftar pesan flat) jadi conversation
  /// pertama — supaya histori sebelum fitur multi-chat ini tidak hilang.
  static Future<Map<String, dynamic>?> _migrateLegacy(SharedPreferences prefs) async {
    final legacyRaw = prefs.getString(_legacyKey);
    if (legacyRaw == null || legacyRaw.isEmpty) return null;
    try {
      final decoded = jsonDecode(legacyRaw) as List;
      final rawMessages = decoded.whereType<Map<String, dynamic>>().toList();
      if (rawMessages.isEmpty) {
        await prefs.remove(_legacyKey);
        await prefs.remove(_legacySessionKey);
        return null;
      }
      final messages = rawMessages.map(ChatMessage.fromJson).toList();
      final now = DateTime.now().millisecondsSinceEpoch;
      final conv = {
        'id': now.toString(),
        'title': await autoTitle(messages),
        'titleAuto': true,
        'messages': rawMessages,
        'pinned': false,
        'createdAt': now,
        'updatedAt': now,
        'agentSession': prefs.getString(_legacySessionKey),
      };
      final existing = await _readConversations(prefs);
      existing.add(conv);
      await _writeConversations(prefs, existing);
      await prefs.remove(_legacyKey);
      await prefs.remove(_legacySessionKey);
      return conv;
    } catch (_) {
      return null;
    }
  }

  /// Semua percakapan, urut: pinned dulu, lalu terbaru (updatedAt desc).
  static Future<List<Map<String, dynamic>>> listConversations() async {
    final prefs = await SharedPreferences.getInstance();
    var list = await _readConversations(prefs);
    if (list.isEmpty) {
      final migrated = await _migrateLegacy(prefs);
      if (migrated != null) list = [migrated];
    }
    list.sort((a, b) {
      final pinnedA = a['pinned'] == true;
      final pinnedB = b['pinned'] == true;
      if (pinnedA != pinnedB) return pinnedA ? -1 : 1;
      final updatedA = a['updatedAt'] as int? ?? 0;
      final updatedB = b['updatedAt'] as int? ?? 0;
      return updatedB.compareTo(updatedA);
    });
    return list;
  }

  static Future<Map<String, dynamic>?> loadConversation(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    for (final c in list) {
      if (c['id'] == id) return c;
    }
    return null;
  }

  static Future<String> createConversation({String? projectId}) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = '${now}_${list.length}';
    list.insert(0, {
      'id': id,
      'title': 'Percakapan Baru',
      'titleAuto': true,
      'messages': <Map<String, dynamic>>[],
      'pinned': false,
      'archived': false,
      'createdAt': now,
      'updatedAt': now,
      'agentSession': null,
      'projectId': projectId,
    });
    await _writeConversations(prefs, list);
    await pushToServer();
    return id;
  }

  /// Simpan pesan-pesan sebuah conversation. [title] dipaksa (rename manual,
  /// mematikan auto-title seterusnya); kalau tidak diisi dan auto-title masih
  /// aktif, judul di-generate dari pesan user PERTAMA (lihat autoTitle()) —
  /// begitu pesan pertama terkirim judulnya langsung kebentuk dan tetap sama
  /// untuk pesan-pesan berikutnya, kecuali di-rename manual.
  static Future<void> saveConversation(
    String id,
    List<ChatMessage> messages, {
    String? title,
    String? agentSession,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    final now = DateTime.now().millisecondsSinceEpoch;
    final idx = list.indexWhere((c) => c['id'] == id);
    final existing = idx != -1 ? list[idx] : null;

    String resolvedTitle;
    bool resolvedTitleAuto;
    if (title != null) {
      resolvedTitle = title;
      resolvedTitleAuto = false;
    } else if (_isTitleAuto(existing)) {
      resolvedTitle = await autoTitle(messages);
      resolvedTitleAuto = true;
    } else {
      resolvedTitle = (existing?['title'] as String?) ?? await autoTitle(messages);
      resolvedTitleAuto = false;
    }

    final updated = {
      'id': id,
      'title': resolvedTitle,
      'titleAuto': resolvedTitleAuto,
      'messages': messages.map((m) => m.toJson()).toList(),
      'pinned': existing?['pinned'] ?? false,
      'archived': existing?['archived'] ?? false,
      'createdAt': existing?['createdAt'] ?? now,
      'updatedAt': now,
      'agentSession': agentSession ?? existing?['agentSession'],
      'projectId': existing?['projectId'],
    };
    if (idx != -1) {
      list[idx] = updated;
    } else {
      list.insert(0, updated);
    }
    await _writeConversations(prefs, list);
    // Debounce 2 detik — saveConversation() dipanggil sangat sering (tiap
    // kirim pesan/balasan), jadi push langsung tiap kali akan bikin banyak
    // POST kecil beruntun. Method tulis lain (rename/pin/delete/dst) jauh
    // lebih jarang dipanggil sehingga tetap push langsung.
    _pushDebounce?.cancel();
    _pushDebounce = Timer(const Duration(seconds: 2), () => pushToServer());
  }

  /// Auto-title masih aktif kalau: conversation baru, field titleAuto=true
  /// eksplisit, atau data lama (sebelum fitur ini ada) yang judulnya masih
  /// placeholder default — supaya percakapan lama yang kepentok bug "selalu
  /// Percakapan Baru" ikut kebenerin otomatis, tanpa menimpa judul yang
  /// sudah pernah di-rename manual sebelumnya.
  static bool _isTitleAuto(Map<String, dynamic>? existing) {
    if (existing == null) return true;
    if (existing.containsKey('titleAuto')) return existing['titleAuto'] == true;
    return (existing['title'] as String?) == 'Percakapan Baru';
  }

  /// Pindahkan sebuah conversation ke project [projectId] (null = lepas dari project).
  static Future<void> setConversationProject(String id, String? projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    final idx = list.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'projectId': projectId};
    await _writeConversations(prefs, list);
    await pushToServer();
  }

  static Future<void> deleteConversation(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    list.removeWhere((c) => c['id'] == id);
    await _writeConversations(prefs, list);
    await pushToServer();
  }

  /// Rename manual dari menu ⋯ → Rename — mematikan auto-title seterusnya
  /// biar tidak ketiban timpa lagi oleh saveConversation().
  static Future<void> renameConversation(String id, String title) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    final idx = list.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'title': title, 'titleAuto': false};
    await _writeConversations(prefs, list);
    await pushToServer();
  }

  static Future<void> pinConversation(String id, bool pinned) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    final idx = list.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'pinned': pinned};
    await _writeConversations(prefs, list);
    await pushToServer();
  }

  static Future<void> archiveConversation(String id, bool archived) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    final idx = list.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'archived': archived};
    await _writeConversations(prefs, list);
    await pushToServer();
  }

  /// Judul otomatis dari pesan user PERTAMA — sekali terisi, judul tetap
  /// sama walau ada pesan/balasan berikutnya (deterministik: pesan pertama
  /// tidak pernah berubah, jadi hasilnya otomatis "beku" tanpa perlu flag
  /// tambahan). Huruf pertama dikapitalkan, dipotong maksimal 40 karakter +
  /// "...". Tidak ada panggilan API — murni dari teks pesan yang sudah ada.
  static Future<String> autoTitle(List<ChatMessage> messages) async {
    final userTexts = messages.where((m) => m.isUser && m.text.trim().isNotEmpty).toList();
    if (userTexts.isEmpty) return 'Percakapan Baru';
    final text = userTexts.first.text.trim();
    final capitalized = text[0].toUpperCase() + text.substring(1);
    return capitalized.length > 40 ? '${capitalized.substring(0, 40)}...' : capitalized;
  }

  /// Jaring pengaman satu kali: perbaiki SEMUA judul yang masih placeholder
  /// default padahal conversation-nya sudah punya pesan user — dipanggil
  /// sekali saat chat screen dimuat, supaya chat lama yang kepentok bug lama
  /// ("selalu Percakapan Baru") langsung benar di sidebar tanpa perlu diklik
  /// satu-satu dulu. Tidak menyentuh judul yang sudah pernah di-rename manual.
  static Future<void> fixAllStaleTitles() async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      final existing = list[i];
      if (!_isTitleAuto(existing)) continue;
      final rawMessages = existing['messages'];
      if (rawMessages is! List) continue;
      final messages = rawMessages.whereType<Map<String, dynamic>>().map(ChatMessage.fromJson).toList();
      final newTitle = await autoTitle(messages);
      if (newTitle != existing['title']) {
        list[i] = {...existing, 'title': newTitle, 'titleAuto': true};
        changed = true;
      }
    }
    if (changed) await _writeConversations(prefs, list);
  }

  // ---- Projects ----
  // {id, name, description, color, icon, pinned, archived, createdAt}

  static Future<List<Map<String, dynamic>>> _readProjects(SharedPreferences prefs) async {
    final raw = prefs.getString(_projectsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeProjects(SharedPreferences prefs, List<Map<String, dynamic>> list) async {
    await prefs.setString(_projectsKey, jsonEncode(list));
  }

  /// Semua project (default: yang belum di-archive), urut: pinned dulu,
  /// lalu dari yang paling lama dibuat.
  static Future<List<Map<String, dynamic>>> listProjects({bool includeArchived = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readProjects(prefs);
    final filtered = includeArchived ? list : list.where((p) => p['archived'] != true).toList();
    filtered.sort((a, b) {
      final pinnedA = a['pinned'] == true;
      final pinnedB = b['pinned'] == true;
      if (pinnedA != pinnedB) return pinnedA ? -1 : 1;
      return (a['createdAt'] as int? ?? 0).compareTo(b['createdAt'] as int? ?? 0);
    });
    return filtered;
  }

  static Future<String> createProject({
    required String name,
    required String color,
    required String icon,
    String description = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readProjects(prefs);
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'proj_${now}_${list.length}';
    list.add({
      'id': id,
      'name': name,
      'description': description,
      'color': color,
      'icon': icon,
      'pinned': false,
      'archived': false,
      'createdAt': now,
    });
    await _writeProjects(prefs, list);
    await pushToServer();
    return id;
  }

  static Future<void> renameProject(String id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readProjects(prefs);
    final idx = list.indexWhere((p) => p['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'name': name};
    await _writeProjects(prefs, list);
    await pushToServer();
  }

  /// Update lengkap dari halaman "Project settings" — nama, deskripsi, warna, ikon.
  static Future<void> updateProjectSettings(
    String id, {
    required String name,
    required String description,
    required String color,
    required String icon,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readProjects(prefs);
    final idx = list.indexWhere((p) => p['id'] == id);
    if (idx == -1) return;
    list[idx] = {
      ...list[idx],
      'name': name,
      'description': description,
      'color': color,
      'icon': icon,
    };
    await _writeProjects(prefs, list);
    await pushToServer();
  }

  static Future<void> pinProject(String id, bool pinned) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readProjects(prefs);
    final idx = list.indexWhere((p) => p['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'pinned': pinned};
    await _writeProjects(prefs, list);
    await pushToServer();
  }

  static Future<void> archiveProject(String id, bool archived) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readProjects(prefs);
    final idx = list.indexWhere((p) => p['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'archived': archived};
    await _writeProjects(prefs, list);
    await pushToServer();
  }

  /// Hapus project — chat yang tadinya masuk situ dilepas (projectId jadi null),
  /// bukan ikut terhapus.
  static Future<void> deleteProject(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readProjects(prefs);
    list.removeWhere((p) => p['id'] == id);
    await _writeProjects(prefs, list);

    final conversations = await _readConversations(prefs);
    var changed = false;
    for (var i = 0; i < conversations.length; i++) {
      if (conversations[i]['projectId'] == id) {
        conversations[i] = {...conversations[i], 'projectId': null};
        changed = true;
      }
    }
    if (changed) await _writeConversations(prefs, conversations);
    await pushToServer();
  }
}
