import 'package:web/web.dart' as web;

/// Hapus fragment (#token=...) & query (?error=...) dari address bar browser
/// setelah dibaca SplashScreen — anti-loop kalau user refresh halaman
/// (fragment/param lama tidak diproses ulang).
void clearOAuthRedirectFragment() {
  web.window.history.replaceState(null, '', web.window.location.pathname);
}
