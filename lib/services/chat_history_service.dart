import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

/// Simpan & muat histori percakapan ke SharedPreferences (localStorage di web).
/// Format: List of {isUser, text, timestamp}
class ChatHistoryService {
  static const _key = 'jeonchat_history';
  static const _sessionKey = 'jeonchat_agent_session';

  /// Simpan semua pesan ke storage
  static Future<void> save(List<ChatMessage> messages, {String? agentSession}) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = messages.map((m) => m.toJson()).toList();
    await prefs.setString(_key, jsonEncode(jsonList));
    if (agentSession != null) {
      await prefs.setString(_sessionKey, agentSession);
    }
  }

  /// Muat histori dari storage
  static Future<List<ChatMessage>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map<String, dynamic>>().map(ChatMessage.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  /// Muat agent session dari storage
  static Future<String?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionKey);
  }

  /// Hapus semua histori
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_sessionKey);
  }

  /// Cek apakah ada histori tersimpan
  static Future<bool> hasHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return raw != null && raw.isNotEmpty;
  }
}