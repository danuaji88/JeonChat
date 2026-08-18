import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';

/// Form daftar akun baru — pop(true) kalau berhasil (token otomatis
/// tersimpan di ApiService lewat register()), pop(false)/null kalau batal.
class RegisterScreen extends StatefulWidget {
  final ApiService api;

  const RegisterScreen({super.key, required this.api});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
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
      await widget.api.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      appBar: AppBar(
        backgroundColor: JeonColors.bg,
        elevation: 0,
        title: const Text('Daftar Akun JeonChat', style: TextStyle(fontSize: 15)),
      ),
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
                  const Text(
                    'Buat akun baru',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: JeonColors.ink),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Setelah daftar, kamu otomatis masuk',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: JeonColors.inkFaint),
                  ),
                  const SizedBox(height: 24),
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
                  _label('Nama'),
                  const SizedBox(height: 6),
                  _field(
                    controller: _nameController,
                    hint: 'Nama kamu',
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Wajib diisi' : null,
                  ),
                  const SizedBox(height: 16),
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
                    hint: 'Minimal 6 karakter',
                    obscureText: _obscurePassword,
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 18,
                        color: JeonColors.inkFaint,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (v) => (v == null || v.length < 6) ? 'Minimal 6 karakter' : null,
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
                          : const Text('Daftar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
