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

  ApiService({required this.baseUrl, required this.apiKey});

  static const _prefsBaseUrlKey = 'jeonchat_base_url';
  static const _prefsApiKeyKey = 'jeonchat_api_key';

  static Future<ApiService> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return ApiService(
      baseUrl: prefs.getString(_prefsBaseUrlKey) ?? '',
      apiKey: prefs.getString(_prefsApiKeyKey) ?? 'jeongpt-demo',
    );
  }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBaseUrlKey, baseUrl);
    await prefs.setString(_prefsApiKeyKey, apiKey);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  static const _shortTimeout = Duration(seconds: 15);
  static const _chatTimeout = Duration(seconds: 90);

  bool get isConfigured => baseUrl.isNotEmpty;

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
      'messages': history.map((m) => m.toApiJson()).toList(),
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
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
