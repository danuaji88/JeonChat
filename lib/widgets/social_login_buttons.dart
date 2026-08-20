import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../services/api_service.dart';
import '../theme.dart';
import '../utils/google_button.dart';

/// 6 tombol login sosial dipakai bareng oleh LoginScreen & AuthGateScreen —
/// POST hasil token ke ApiService.socialLogin() (/auth/social) atau
/// phoneRequestOtp/phoneVerifyOtp() (/auth/phone, /auth/phone/verify).
///
/// Google: di web WAJIB pakai tombol GIS asli (buildGoogleRenderButton(),
/// lihat lib/utils/google_button_web.dart) — signIn() imperatif di web cuma
/// dapat access token, BUKAN idToken (dikonfirmasi langsung dari source
/// google_sign_in_web: kredensial ber-idToken cuma keluar dari alur
/// renderButton()/One Tap, ditangkap lewat GoogleSignIn().onCurrentUserChanged
/// — lihat _onGoogleAccountChanged). Di Android/iOS, signIn() native tetap
/// reliable dapat idToken, jadi tombol custom + _loginWithGoogle() tetap
/// dipakai di sana. Facebook jalan lewat package flutter_facebook_auth (SDK
/// JS di-init lazy saat tombol ditekan, appId dari /auth/social/config).
/// GitHub & TikTok jalan lewat redirect OAuth browser (client_id/redirect_uri
/// dari /auth/social/config) — backend tukar code → token lalu redirect ke
/// .../app/#token=..., dibaca SplashScreen._init() (lihat lib/utils/
/// oauth_redirect.dart untuk pembersihan hash-nya). WhatsApp jalan lewat
/// alur OTP 2 langkah (/auth/phone → /auth/phone/verify, dev_hint dipakai
/// selama belum ada gateway SMS/WA asli). Instagram belum ada App ID yang
/// dikonfigurasi di server — tombolnya jujur menampilkan "belum
/// dikonfigurasi", bukan pura-pura jalan.
class SocialLoginButtons extends StatefulWidget {
  final ApiService api;
  final VoidCallback onSuccess;

  const SocialLoginButtons({super.key, required this.api, required this.onSuccess});

  @override
  State<SocialLoginButtons> createState() => _SocialLoginButtonsState();
}

class _SocialLoginButtonsState extends State<SocialLoginButtons> {
  String? _loadingProvider;
  String? _pressedProvider;

  // Satu instance persisten dipakai bersama oleh path native (_loginWithGoogle,
  // signIn() imperatif) dan path web (listener onCurrentUserChanged di bawah)
  // — bukan bikin instance baru tiap tap, supaya GIS SDK tidak re-init tiap klik.
  late final GoogleSignIn _googleSignIn;
  StreamSubscription<GoogleSignInAccount?>? _googleAccountSub;

  bool get _loading => _loadingProvider != null;

  @override
  void initState() {
    super.initState();
    _googleSignIn = GoogleSignIn(scopes: const ['email']);
    if (kIsWeb) {
      // renderButton() (tombol GIS asli) tidak bisa di-await langsung dari
      // tap seperti signIn() — hasil suksesnya baru muncul lewat stream ini.
      _googleAccountSub = _googleSignIn.onCurrentUserChanged.listen(_onGoogleAccountChanged);
    }
  }

  @override
  void dispose() {
    _googleAccountSub?.cancel();
    super.dispose();
  }

  /// Dipanggil setelah user berhasil pilih akun lewat tombol GIS asli
  /// (buildGoogleRenderButton, web-only) — account di sini punya idToken
  /// beneran karena datang dari credential response GIS, bukan access token.
  Future<void> _onGoogleAccountChanged(GoogleSignInAccount? account) async {
    if (account == null || !mounted) return;
    setState(() => _loadingProvider = 'google');
    try {
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('ID token Google tidak tersedia');
      }
      await widget.api.socialLogin(provider: 'google', token: idToken, name: account.displayName ?? '');
      if (!mounted) return;
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login Google gagal: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  /// Path native (Android/iOS) — signIn() imperatif reliable dapat idToken
  /// di platform ini (beda dengan web, lihat dok class di atas).
  Future<void> _loginWithGoogle() async {
    setState(() => _loadingProvider = 'google');
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return; // User batal di dialog Google.
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('ID token Google tidak tersedia');
      }
      await widget.api.socialLogin(provider: 'google', token: idToken, name: account.displayName ?? '');
      if (!mounted) return;
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login Google gagal: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  /// TikTok OAuth — sama pola dengan GitHub: buka halaman otorisasi TikTok
  /// (client_key publik dari /auth/social/config, fallback ke nilai default
  /// kalau config gagal diambil), redirect balik ke callback server →
  /// #token=... → dibaca SplashScreen._init().
  Future<void> _loginWithTikTok() async {
    setState(() => _loadingProvider = 'tiktok');
    try {
      var clientKey = 'sbawa4ub8q0th6v024';
      var redirectUri = 'https://chat.jeonlive.com/auth/tiktok/callback';
      try {
        final cfg = await widget.api.fetchSocialConfig();
        final tk = cfg['tiktok'] as Map<String, dynamic>?;
        final ck = tk?['client_key']?.toString() ?? '';
        final ruri = tk?['redirect_uri']?.toString() ?? '';
        if (ck.isNotEmpty) clientKey = ck;
        if (ruri.isNotEmpty) redirectUri = ruri;
      } catch (_) {
        // Config server gagal diambil — tetap coba pakai nilai default di atas.
      }
      final authUrl = 'https://www.tiktok.com/v2/auth/authorize/'
          '?client_key=$clientKey'
          '&scope=user.info.basic'
          '&response_type=code'
          '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
          '&state=jeonchat';
      final ok = await launchUrlString(authUrl, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membuka halaman login TikTok.')),
        );
      }
      // Tab baru terbuka ke TikTok → user login di sana → redirect balik ke
      // backend → app (dibaca SplashScreen). Tab ini sendiri tetap idle.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login TikTok gagal: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  /// GitHub OAuth — sama pola dengan TikTok: buka halaman otorisasi GitHub
  /// (client_id publik dari /auth/social/config, fallback ke nilai default
  /// kalau config gagal diambil), redirect balik ke callback server →
  /// #token=... → dibaca SplashScreen._init().
  Future<void> _loginWithGitHub() async {
    setState(() => _loadingProvider = 'github');
    try {
      var clientId = 'Ov23liIXOE1ajl3fchAh';
      var redirectUri = 'https://chat.jeonlive.com/auth/github/callback';
      try {
        final cfg = await widget.api.fetchSocialConfig();
        final gh = cfg['github'] as Map<String, dynamic>?;
        final cid = gh?['client_id']?.toString() ?? '';
        final ruri = gh?['redirect_uri']?.toString() ?? '';
        if (cid.isNotEmpty) clientId = cid;
        if (ruri.isNotEmpty) redirectUri = ruri;
      } catch (_) {
        // Config server gagal diambil — tetap coba pakai nilai default di atas.
      }
      final authUrl = 'https://github.com/login/oauth/authorize'
          '?client_id=$clientId'
          '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
          '&scope=${Uri.encodeComponent('read:user user:email')}';
      final ok = await launchUrlString(authUrl, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal membuka halaman login GitHub.')),
        );
      }
      // Tab baru terbuka ke GitHub → user login di sana → redirect balik ke
      // backend → app (dibaca SplashScreen). Tab ini sendiri tetap idle.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login GitHub gagal: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  /// Facebook — package flutter_facebook_auth. SDK JS (web) di-init lazy di
  /// sini (bukan di main()) supaya user yang tidak pernah pakai Facebook
  /// tidak kena biaya network call itu; appId dari /auth/social/config,
  /// fallback ke nilai default kalau config gagal diambil.
  Future<void> _loginWithFacebook() async {
    setState(() => _loadingProvider = 'facebook');
    try {
      if (!FacebookAuth.i.isWebSdkInitialized) {
        var appId = '1057222590048711';
        try {
          final cfg = await widget.api.fetchSocialConfig();
          final fb = cfg['facebook'] as Map<String, dynamic>?;
          final cid = fb?['app_id']?.toString() ?? '';
          if (cid.isNotEmpty) appId = cid;
        } catch (_) {
          // Config server gagal diambil — tetap coba pakai nilai default di atas.
        }
        await FacebookAuth.i.webAndDesktopInitialize(
          appId: appId,
          cookie: true,
          xfbml: false,
          version: 'v23.0',
        );
      }
      final result = await FacebookAuth.i.login(
        permissions: const ['email', 'public_profile'],
        loginTracking: LoginTracking.enabled,
      );
      if (result.status == LoginStatus.cancelled) return; // User batal.
      if (result.status != LoginStatus.success) {
        throw Exception(result.message ?? 'Login Facebook gagal');
      }
      final accessToken = result.accessToken?.tokenString ?? '';
      if (accessToken.isEmpty) {
        throw Exception('Access token Facebook tidak tersedia');
      }
      await widget.api.socialLogin(provider: 'facebook', token: accessToken);
      if (!mounted) return;
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login Facebook gagal: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  Future<void> _loginWithInstagram() async {
    showDialog(
      context: context,
      builder: (context) => _premiumDialog(
        title: 'Instagram belum aktif',
        content: const Text(
          'Login Instagram butuh Instagram App ID yang didaftarkan di Meta Developer. Appa sedang menyiapkan. '
          'Sementara pakai email/password, Google, atau WhatsApp dulu ya.',
          style: TextStyle(color: JeonColors.inkFaint, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Oke', style: TextStyle(color: JeonColors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _loginWithPhone() async {
    final phoneController = TextEditingController();
    final localPhone = await showDialog<String>(
      context: context,
      builder: (ctx) => _premiumDialog(
        title: 'Masuk dengan WhatsApp',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Masukkan nomor HP (WhatsApp) untuk menerima kode OTP.',
                style: TextStyle(color: JeonColors.inkFaint, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              autofocus: true,
              style: const TextStyle(color: JeonColors.ink, fontSize: 13.5),
              decoration: _dialogFieldDecoration('81234567890', prefixText: '+62 '),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal', style: TextStyle(color: JeonColors.inkFaint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(phoneController.text.trim()),
            child: const Text('Kirim OTP', style: TextStyle(color: JeonColors.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (localPhone == null || localPhone.isEmpty || !mounted) return;
    setState(() => _loadingProvider = 'phone');

    try {
      final digits = localPhone.startsWith('0') ? localPhone.substring(1) : localPhone;
      final phone = '+62$digits';
      final res = await widget.api.phoneRequestOtp(phone);
      if (!mounted) return;
      // dev_hint = OTP sementara (belum ada gateway SMS/WA asli).
      // TODO: hapus dev_hint saat gateway WA/SMS aktif.
      final devHint = res['dev_hint']?.toString() ?? '';

      final otpController = TextEditingController();
      final otp = await showDialog<String>(
        context: context,
        builder: (ctx) => _premiumDialog(
          title: 'Masukkan Kode OTP',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Kode dikirim ke $phone',
                  style: const TextStyle(color: JeonColors.inkFaint, fontSize: 13, height: 1.4)),
              if (devHint.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: JeonColors.ink.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Mode dev: kode kamu $devHint',
                      style: const TextStyle(color: JeonColors.inkFaint, fontSize: 11.5)),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: JeonColors.ink, fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                decoration: _dialogFieldDecoration('••••••').copyWith(counterText: ''),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Batal', style: TextStyle(color: JeonColors.inkFaint)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(otpController.text.trim()),
              child: const Text('Verifikasi', style: TextStyle(color: JeonColors.accent, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
      if (otp == null || otp.isEmpty || !mounted) return;

      await widget.api.phoneVerifyOtp(phone, otp);
      if (!mounted) return;
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().contains('OTP') ? e.toString() : 'Login gagal, coba lagi.')),
      );
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  // ---- Dialog premium bersama: radius 16, shadow lembut, input filled
  // radius 10 tanpa border, title 16/600, content 13 inkFaint. ----

  Widget _premiumDialog({required String title, required Widget content, required List<Widget> actions}) {
    return AlertDialog(
      backgroundColor: JeonColors.surface,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      elevation: 16,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      title: Text(title, style: const TextStyle(color: JeonColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
      content: content,
      actions: actions,
    );
  }

  InputDecoration _dialogFieldDecoration(String hint, {String? prefixText}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: JeonColors.inkFaint),
        prefixText: prefixText,
        prefixStyle: const TextStyle(color: JeonColors.ink, fontSize: 13.5),
        filled: true,
        fillColor: JeonColors.ink.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Web WAJIB pakai tombol GIS asli (lihat dok class) — custom button
        // cuma dipakai di Android/iOS di mana signIn() native tetap reliable.
        if (kIsWeb)
          SizedBox(height: 46, child: Center(child: buildGoogleRenderButton()))
        else
          _socialButton(
            provider: 'google',
            label: 'Masuk dengan Google',
            bg: Colors.white,
            fg: Colors.black87,
            border: JeonColors.border,
            onTap: _loading ? null : _loginWithGoogle,
            loading: _loadingProvider == 'google',
            leading: const Text('G',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4285F4))),
          ),
        const SizedBox(height: 10),
        _socialButton(
          provider: 'tiktok',
          label: 'Masuk dengan TikTok',
          bg: Colors.black,
          fg: Colors.white,
          border: Colors.black,
          onTap: _loading ? null : _loginWithTikTok,
          loading: _loadingProvider == 'tiktok',
          leading: const Icon(Icons.music_note_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(height: 10),
        _socialButton(
          provider: 'facebook',
          label: 'Masuk dengan Facebook',
          bg: const Color(0xFF1877F2),
          fg: Colors.white,
          border: const Color(0xFF1877F2),
          onTap: _loading ? null : _loginWithFacebook,
          loading: _loadingProvider == 'facebook',
          leading: const Icon(Icons.facebook_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(height: 10),
        _socialButton(
          provider: 'github',
          label: 'Masuk dengan GitHub',
          bg: const Color(0xFF24292E),
          fg: Colors.white,
          border: const Color(0xFF24292E),
          onTap: _loading ? null : _loginWithGitHub,
          loading: _loadingProvider == 'github',
          leading: const Icon(Icons.code_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(height: 10),
        _socialButton(
          provider: 'instagram',
          label: 'Masuk dengan Instagram',
          bg: const Color(0xFF833AB4),
          bgGradient: const LinearGradient(colors: [Color(0xFF833AB4), Color(0xFFE1306C)]),
          fg: Colors.white,
          border: const Color(0xFFE1306C),
          onTap: _loading ? null : _loginWithInstagram,
          leading: const Icon(Icons.photo_camera_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(height: 10),
        _socialButton(
          provider: 'phone',
          label: 'Masuk dengan WhatsApp',
          bg: const Color(0xFF25D366),
          fg: Colors.white,
          border: const Color(0xFF25D366),
          onTap: _loading ? null : _loginWithPhone,
          loading: _loadingProvider == 'phone',
          leading: const Icon(Icons.chat_rounded, size: 18, color: Colors.white),
        ),
      ],
    );
  }

  /// Tombol sosial premium — tinggi 46, radius 12, border tipis 12% opacity,
  /// shadow halus, micro-interaction scale 0.98 saat ditekan, loading state
  /// pakai spinner 16px + label "Sebentar..." (tombol lain ikut disabled
  /// lewat [_loading] di masing-masing onTap pemanggil).
  Widget _socialButton({
    required String provider,
    required String label,
    required Color bg,
    required Color fg,
    required Color border,
    required VoidCallback? onTap,
    required Widget leading,
    Gradient? bgGradient,
    bool loading = false,
  }) {
    final pressed = _pressedProvider == provider;
    return AnimatedScale(
      scale: pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: GestureDetector(
        onTapDown: onTap == null ? null : (_) => setState(() => _pressedProvider = provider),
        onTapUp: onTap == null ? null : (_) => setState(() => _pressedProvider = null),
        onTapCancel: () => setState(() => _pressedProvider = null),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 46,
          decoration: BoxDecoration(
            color: bgGradient == null ? bg : null,
            gradient: bgGradient,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Center(
            child: loading
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
                      const SizedBox(width: 10),
                      Text('Sebentar...', style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      leading,
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
