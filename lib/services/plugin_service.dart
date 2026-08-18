import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu plugin yang sudah di-install user — [id] slug snake_case (mis.
/// "video_editor") dikirim apa adanya ke backend lewat /agent 'plugins',
/// title+emoji buat render "My Plugins" di sidebar & badge di input bar.
class InstalledPlugin {
  final String id;
  final String title;
  final String emoji;

  const InstalledPlugin({required this.id, required this.title, required this.emoji});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'emoji': emoji};

  factory InstalledPlugin.fromJson(Map<String, dynamic> json) => InstalledPlugin(
        // Data lama (sebelum field id ada) dipersist tanpa id — pakai title
        // sebagai fallback biar tidak hilang begitu saja saat upgrade.
        id: (json['id'] ?? json['title'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        emoji: (json['emoji'] ?? '🧩').toString(),
      );
}

/// Simpan & muat daftar plugin yang aktif/terinstall ke SharedPreferences —
/// satu-satunya sumber kebenaran dipakai bareng oleh Plugin Store, section
/// "My Plugins" di sidebar, dan badge "✓N" di input bar.
class PluginService {
  static const _key = 'jeon_installed_plugins';

  static Future<List<InstalledPlugin>> listInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.whereType<Map<String, dynamic>>().map(InstalledPlugin.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<InstalledPlugin> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list.map((p) => p.toJson()).toList()));
  }

  static Future<List<InstalledPlugin>> install(String id, String title, String emoji) async {
    final list = await listInstalled();
    if (!list.any((p) => p.id == id)) {
      list.add(InstalledPlugin(id: id, title: title, emoji: emoji));
      await _save(list);
    }
    return list;
  }

  static Future<List<InstalledPlugin>> uninstall(String id) async {
    final list = await listInstalled();
    list.removeWhere((p) => p.id == id);
    await _save(list);
    return list;
  }
}
