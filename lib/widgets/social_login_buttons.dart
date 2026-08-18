import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/api_service.dart';
import '../theme.dart';

/// 3 tombol login sosial dipakai bareng oleh LoginScreen & AuthGateScreen —
/// POST hasil token ke ApiService.socialLogin() (/auth/social).
///
/// Google beneran jalan lewat package google_sign_in (butuh Client ID resmi
/// dikonfigurasi di project Google Cloud Console — di luar akses kode ini).
/// TikTok & Facebook belum ada SDK yang bisa dipasang dengan aman tanpa App
/// ID/Client ID asli (Facebook SDK khususnya bisa bikin build Android crash
/// saat start kalau meta-data App ID tidak ada di AndroidManifest) — jadi
/// tombolnya jujur menampilkan "belum dikonfigurasi", bukan pura-pura jalan.
class SocialLoginButtons extends StatefulWidget {
  final ApiService api;
  final VoidCallback onSuccess;

  const SocialLoginButtons({super.key, required this.api, required this.onSuccess});

  @override
  State<SocialLoginButtons> createState() => _SocialLoginButtonsState();
}

class _SocialLoginButtonsState extends State<SocialLoginButtons> {
  String? _loadingProvider;

  bool get _loading => _loadingProvider != null;

  Future<void> _loginWithGoogle() async {
    setState(() => _loadingProvider = 'google');
    try {
      final googleSignIn = GoogleSignIn(scopes: const ['email']);
      final account = await googleSignIn.signIn();
      if (account == null) return; // User batal di dialog Google.
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('ID token Google tidak tersedia');
      }
      await widget.api.socialLogin(provider: 'google', token: idToken);
      if (!mounted) return;
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login gagal, coba lagi.')),
      );
    } finally {
      if (mounted) setState(() => _loadingProvider = null);
    }
  }

  void _showNotConfigured(String provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: JeonColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('$provider belum tersedia', style: const TextStyle(color: JeonColors.ink, fontSize: 15.5)),
        content: Text(
          'Login $provider butuh App ID/Client ID resmi dari $provider yang belum dikonfigurasi di server ini. '
          'Coba Google, atau masuk pakai email/password dulu ya.',
          style: const TextStyle(color: JeonColors.inkFaint, fontSize: 12.8),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Oke', style: TextStyle(color: JeonColors.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _socialButton(
          provider: 'google',
          label: 'Masuk dengan Google',
          bg: Colors.white,
          fg: Colors.black87,
          border: JeonColors.border,
          onTap: _loading ? null : _loginWithGoogle,
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
          onTap: _loading ? null : () => _showNotConfigured('TikTok'),
          leading: const Icon(Icons.music_note_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(height: 10),
        _socialButton(
          provider: 'facebook',
          label: 'Masuk dengan Facebook',
          bg: const Color(0xFF1877F2),
          fg: Colors.white,
          border: const Color(0xFF1877F2),
          onTap: _loading ? null : () => _showNotConfigured('Facebook'),
          leading: const Icon(Icons.facebook_rounded, size: 20, color: Colors.white),
        ),
      ],
    );
  }

  Widget _socialButton({
    required String provider,
    required String label,
    required Color bg,
    required Color fg,
    required Color border,
    required VoidCallback? onTap,
    required Widget leading,
  }) {
    final showSpinner = _loadingProvider == provider;
    return SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
        ),
        child: showSpinner
            ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  leading,
                  const SizedBox(width: 10),
                  Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: fg)),
                ],
              ),
      ),
    );
  }
}
