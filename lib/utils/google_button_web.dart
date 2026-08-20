import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web_gsi;

/// Tombol Google Identity Services asli (bukan custom) — SATU-SATUNYA cara
/// dapat idToken beneran di Flutter web (signIn() imperatif cuma dapat
/// access token, lihat SocialLoginButtons untuk penjelasan lengkap). Locale
/// dipaksa 'id' supaya labelnya ikut Bahasa Indonesia seperti tombol lain.
Widget buildGoogleRenderButton() {
  return web_gsi.renderButton(
    configuration: web_gsi.GSIButtonConfiguration(
      theme: web_gsi.GSIButtonTheme.outline,
      size: web_gsi.GSIButtonSize.large,
      shape: web_gsi.GSIButtonShape.rectangular,
      text: web_gsi.GSIButtonText.continueWith,
      locale: 'id',
      minimumWidth: 400,
    ),
  );
}
