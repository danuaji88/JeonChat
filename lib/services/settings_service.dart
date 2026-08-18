import 'package:shared_preferences/shared_preferences.dart';

/// App-level preferences (Settings screen). `higherIntelligence` and
/// `enableDictation` are fully wired into ChatScreen; the display prefs
/// (appearance/contrast/accent/icon/language) are stored but not yet
/// applied across the whole UI — see Settings > General for the caveat
/// shown to the user.
class SettingsService {
  String appearance;
  String contrast;
  String accentColorPref;
  String iconColorPref;
  String language;
  bool higherIntelligence;
  bool enableDictation;
  String callMeAs;
  String aiStyle;

  SettingsService({
    required this.appearance,
    required this.contrast,
    required this.accentColorPref,
    required this.iconColorPref,
    required this.language,
    required this.higherIntelligence,
    required this.enableDictation,
    required this.callMeAs,
    required this.aiStyle,
  });

  static const _kAppearance = 'jeonchat_pref_appearance';
  static const _kContrast = 'jeonchat_pref_contrast';
  static const _kAccentColor = 'jeonchat_pref_accent_color';
  static const _kIconColor = 'jeonchat_pref_icon_color';
  static const _kLanguage = 'jeonchat_pref_language';
  static const _kHigherIntel = 'jeonchat_pref_higher_intelligence';
  static const _kDictation = 'jeonchat_pref_enable_dictation';
  static const _kCallMeAs = 'jeonchat_pref_call_me_as';
  static const _kAiStyle = 'jeonchat_pref_ai_style';

  static Future<SettingsService> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(
      appearance: prefs.getString(_kAppearance) ?? 'System',
      contrast: prefs.getString(_kContrast) ?? 'System',
      accentColorPref: prefs.getString(_kAccentColor) ?? 'Default',
      iconColorPref: prefs.getString(_kIconColor) ?? 'Black',
      language: prefs.getString(_kLanguage) ?? 'Auto-detect',
      higherIntelligence: prefs.getBool(_kHigherIntel) ?? false,
      enableDictation: prefs.getBool(_kDictation) ?? true,
      callMeAs: prefs.getString(_kCallMeAs) ?? '',
      aiStyle: prefs.getString(_kAiStyle) ?? 'Ringkas',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAppearance, appearance);
    await prefs.setString(_kContrast, contrast);
    await prefs.setString(_kAccentColor, accentColorPref);
    await prefs.setString(_kIconColor, iconColorPref);
    await prefs.setString(_kLanguage, language);
    await prefs.setBool(_kHigherIntel, higherIntelligence);
    await prefs.setBool(_kDictation, enableDictation);
    await prefs.setString(_kCallMeAs, callMeAs);
    await prefs.setString(_kAiStyle, aiStyle);
  }

  Future<void> resetLocalPrefs() async {
    appearance = 'System';
    contrast = 'System';
    accentColorPref = 'Default';
    iconColorPref = 'Black';
    language = 'Auto-detect';
    higherIntelligence = false;
    enableDictation = true;
    callMeAs = '';
    aiStyle = 'Ringkas';
    await save();
  }
}
