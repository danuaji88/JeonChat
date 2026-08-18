import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../widgets/social_login_buttons.dart';
import 'chat_screen.dart';
import 'onboarding_profile_screen.dart';

class LoginScreen extends StatefulWidget {
  final ApiService api;

  const LoginScreen({super.key, required this.api});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Server URL selalu pakai default (https://chat.jeonlive.com) — tidak perlu input manual.
    widget.api.baseUrl = ApiService.defaultBaseUrl;
  }

  @override
  void dispose() {
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
    widget.api.baseUrl = ApiService.defaultBaseUrl;
    try {
      await widget.api.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      await _goNext();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueAsGuest() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    widget.api.baseUrl = ApiService.defaultBaseUrl;
    try {
      await widget.api.continueAsGuest();
      await _goNext();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goNext() async {
    final profile = await ProfileService.loadFromPrefs();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => profile.onboarded
            ? JeonChatScreen(api: widget.api, profile: profile)
            : OnboardingProfileScreen(api: widget.api, profile: profile),
      ),
    );
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
                      child: const Text(
                        'J',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 26, color: Color(0xFF04150A)),
                      ),
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
                    'Gunakan akun kerja kamu untuk melanjutkan',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: JeonColors.inkFaint),
                  ),
                  const SizedBox(height: 28),
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
                  const SizedBox(height: 26),
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
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: _loading ? null : _continueAsGuest,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: JeonColors.inkMuted,
                        side: const BorderSide(color: JeonColors.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
                      ),
                      child: const Text('Coba Gratis', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: JeonColors.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('atau', style: TextStyle(fontSize: 11.5, color: JeonColors.inkFaint)),
                      ),
                      const Expanded(child: Divider(color: JeonColors.border)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SocialLoginButtons(api: widget.api, onSuccess: _goNext),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

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
