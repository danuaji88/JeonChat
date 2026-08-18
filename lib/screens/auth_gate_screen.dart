import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/social_login_buttons.dart';
import 'register_screen.dart';

enum _AuthMode { token, credentials }

/// Auth gate ala ChatGPT — halaman penuh (bukan snackbar) yang muncul saat
/// user tamu coba buka fitur yang butuh login (Plugins/Library/Scheduled/
/// More). pop(true) kalau berhasil masuk, pop(false)/null kalau Batal.
class AuthGateScreen extends StatefulWidget {
  final ApiService api;

  const AuthGateScreen({super.key, required this.api});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  _AuthMode _mode = _AuthMode.token;
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _tokenController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_mode == _AuthMode.token) {
        await widget.api.loginWithToken(_tokenController.text);
      } else {
        await widget.api.login(email: _emailController.text.trim(), password: _passwordController.text);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRegister() async {
    final registered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RegisterScreen(api: widget.api)),
    );
    if (registered == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [JeonColors.accent, JeonColors.accentDim],
                        ),
                        boxShadow: [BoxShadow(color: JeonColors.accentGlow, blurRadius: 20, spreadRadius: 2)],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.lock_outline, size: 26, color: Color(0xFF04150A)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Masuk ke JeonChat',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: JeonColors.ink),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Anda perlu masuk untuk mengakses fitur ini',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: JeonColors.inkFaint),
                  ),
                  const SizedBox(height: 24),
                  _modeToggle(),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: JeonColors.danger.withValues(alpha: 0.1),
                        border: Border.all(color: JeonColors.danger.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(JeonRadius.small),
                      ),
                      child: Text(_error!, style: const TextStyle(fontSize: 12, color: JeonColors.danger)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_mode == _AuthMode.token) ..._tokenFields() else ..._credentialFields(),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: JeonColors.accent,
                        foregroundColor: const Color(0xFF04150A),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF04150A)),
                            )
                          : const Text('Masuk', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: _loading ? null : _openRegister,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: JeonColors.ink,
                        side: const BorderSide(color: JeonColors.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
                      ),
                      child: const Text('Daftar', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: JeonColors.inkFaint, thickness: 0.5)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('atau',
                            style: TextStyle(color: JeonColors.inkFaint, fontSize: 12, letterSpacing: 0.3)),
                      ),
                      const Expanded(child: Divider(color: JeonColors.inkFaint, thickness: 0.5)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SocialLoginButtons(
                    api: widget.api,
                    onSuccess: () => Navigator.of(context).pop(true),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 46,
                    child: TextButton(
                      onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Batal', style: TextStyle(fontSize: 13.5, color: JeonColors.inkMuted)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modeToggle() => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: JeonColors.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: JeonColors.border),
        ),
        child: Row(
          children: [
            _modeSegment('Token', _AuthMode.token),
            _modeSegment('Email & Password', _AuthMode.credentials),
          ],
        ),
      );

  Widget _modeSegment(String label, _AuthMode value) {
    final active = _mode == value;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _mode = value;
          _error = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? JeonColors.accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? JeonColors.accent : JeonColors.inkFaint)),
        ),
      ),
    );
  }

  List<Widget> _tokenFields() => [
        _label('Token JeonChat'),
        const SizedBox(height: 6),
        _field(
          controller: _tokenController,
          hint: 'Tempel token dari halaman Daftar',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
          onSubmitted: (_) => _submit(),
        ),
      ];

  List<Widget> _credentialFields() => [
        _label('Email'),
        const SizedBox(height: 6),
        _field(
          controller: _emailController,
          hint: 'nama@jeon.com',
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Wajib diisi';
            if (!v.contains('@')) return 'Email tidak valid';
            return null;
          },
        ),
        const SizedBox(height: 16),
        _label('Password'),
        const SizedBox(height: 6),
        _field(
          controller: _passwordController,
          hint: '••••••••',
          obscureText: _obscurePassword,
          suffix: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 18,
              color: JeonColors.inkFaint,
            ),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
          validator: (v) => (v == null || v.isEmpty) ? 'Wajib diisi' : null,
          onSubmitted: (_) => _submit(),
        ),
      ];

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.inkMuted),
      );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffix,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 13.5, color: JeonColors.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: JeonColors.inkFaint),
        filled: true,
        fillColor: JeonColors.surface2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JeonRadius.card),
          borderSide: const BorderSide(color: JeonColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JeonRadius.card),
          borderSide: const BorderSide(color: JeonColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JeonRadius.card),
          borderSide: const BorderSide(color: JeonColors.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JeonRadius.card),
          borderSide: const BorderSide(color: JeonColors.danger),
        ),
      ),
    );
  }
}
