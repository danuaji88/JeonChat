import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

/// Simpan & muat percakapan multi-conversation ke SharedPreferences
/// (localStorage di web). Tiap conversation:
/// {id, title, messages, pinned, createdAt, updatedAt, agentSession}.
/// Ini SATU-SATUNYA sumber daftar riwayat chat — backend tidak punya
/// endpoint /chat/history yang berfungsi (dicek, hasilnya 404).
class ChatHistoryService {
  static const _conversationsKey = 'jeon_chat_conversations';
  static const _projectsKey = 'jeon_chat_projects';

  // Key skema lama (satu daftar pesan flat) — dipertahankan hanya untuk
  // migrasi satu-kali ke conversation pertama, lalu dihapus.
  static const _legacyKey = 'jeonchat_history';
  static const _legacySessionKey = 'jeonchat_agent_session';

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
      'messages': <Map<String, dynamic>>[],
      'pinned': false,
      'archived': false,
      'createdAt': now,
      'updatedAt': now,
      'agentSession': null,
      'projectId': projectId,
    });
    await _writeConversations(prefs, list);
    return id;
  }

  /// Simpan pesan-pesan sebuah conversation. [title] dipaksa (rename manual);
  /// kalau tidak diisi, judul lama dipertahankan, atau di-generate otomatis
  /// dari pesan pertama kalau conversation ini baru.
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
    final resolvedTitle = title ?? (existing?['title'] as String?) ?? await autoTitle(messages);
    final updated = {
      'id': id,
      'title': resolvedTitle,
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
  }

  /// Pindahkan sebuah conversation ke project [projectId] (null = lepas dari project).
  static Future<void> setConversationProject(String id, String? projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    final idx = list.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'projectId': projectId};
    await _writeConversations(prefs, list);
  }

  static Future<void> deleteConversation(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    list.removeWhere((c) => c['id'] == id);
    await _writeConversations(prefs, list);
  }

  static Future<void> renameConversation(String id, String title) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    final idx = list.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'title': title};
    await _writeConversations(prefs, list);
  }

  static Future<void> pinConversation(String id, bool pinned) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    final idx = list.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'pinned': pinned};
    await _writeConversations(prefs, list);
  }

  static Future<void> archiveConversation(String id, bool archived) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readConversations(prefs);
    final idx = list.indexWhere((c) => c['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'archived': archived};
    await _writeConversations(prefs, list);
  }

  /// Judul otomatis dari pesan pertama user, dipotong maksimal 40 karakter.
  static Future<String> autoTitle(List<ChatMessage> messages) async {
    final firstUser = messages.where((m) => m.isUser).toList();
    if (firstUser.isEmpty) return 'Percakapan Baru';
    final text = firstUser.first.text.trim();
    if (text.isEmpty) return 'Percakapan Baru';
    return text.length > 40 ? '${text.substring(0, 40)}…' : text;
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
    return id;
  }

  static Future<void> renameProject(String id, String name) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readProjects(prefs);
    final idx = list.indexWhere((p) => p['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'name': name};
    await _writeProjects(prefs, list);
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
  }

  static Future<void> pinProject(String id, bool pinned) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readProjects(prefs);
    final idx = list.indexWhere((p) => p['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'pinned': pinned};
    await _writeProjects(prefs, list);
  }

  static Future<void> archiveProject(String id, bool archived) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await _readProjects(prefs);
    final idx = list.indexWhere((p) => p['id'] == id);
    if (idx == -1) return;
    list[idx] = {...list[idx], 'archived': archived};
    await _writeProjects(prefs, list);
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
  }
}
