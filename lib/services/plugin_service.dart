import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu plugin yang sudah di-install user — cukup title+emoji, dipakai buat
/// render "My Plugins" di sidebar & badge jumlah di input bar tanpa perlu
/// coupling ke daftar Featured/Productivity/Creativity di plugins_screen.dart.
class InstalledPlugin {
  final String title;
  final String emoji;

  const InstalledPlugin({required this.title, required this.emoji});

  Map<String, dynamic> toJson() => {'title': title, 'emoji': emoji};

  factory InstalledPlugin.fromJson(Map<String, dynamic> json) => InstalledPlugin(
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

  static Future<List<InstalledPlugin>> install(String title, String emoji) async {
    final list = await listInstalled();
    if (!list.any((p) => p.title == title)) {
      list.add(InstalledPlugin(title: title, emoji: emoji));
      await _save(list);
    }
    return list;
  }

  static Future<List<InstalledPlugin>> uninstall(String title) async {
    final list = await listInstalled();
    list.removeWhere((p) => p.title == title);
    await _save(list);
    return list;
  }
}
