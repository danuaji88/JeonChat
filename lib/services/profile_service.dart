import 'package:shared_preferences/shared_preferences.dart';

/// Local display profile (avatar + name), separate from auth.
/// Set once right after login/guest entry, then persisted.
class ProfileService {
  String displayName;
  String avatarEmoji;
  bool onboarded;

  ProfileService({
    required this.displayName,
    required this.avatarEmoji,
    required this.onboarded,
  });

  static const _kName = 'jeonchat_display_name';
  static const _kAvatar = 'jeonchat_avatar_emoji';
  static const _kOnboarded = 'jeonchat_onboarded';

  static Future<ProfileService> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return ProfileService(
      displayName: prefs.getString(_kName) ?? 'Appa Jeon',
      avatarEmoji: prefs.getString(_kAvatar) ?? '🙂',
      onboarded: prefs.getBool(_kOnboarded) ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, displayName);
    await prefs.setString(_kAvatar, avatarEmoji);
    await prefs.setBool(_kOnboarded, true);
    onboarded = true;
  }
}
