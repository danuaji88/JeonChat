import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/profile_service.dart';
import '../theme.dart';
import '../utils/oauth_redirect.dart';
import 'chat_screen.dart';
import 'login_screen.dart';
import 'onboarding_profile_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  late final AnimationController _glowController;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
    _scale = CurvedAnimation(parent: _introController, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _introController, curve: const Interval(0.0, 0.7, curve: Curves.easeOut));

    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _glow = CurvedAnimation(parent: _glowController, curve: Curves.easeInOut);

    _init();
  }

  Future<void> _init() async {
    final results = await Future.wait([
      ApiService.loadFromPrefs(),
      ProfileService.loadFromPrefs(),
      Future.delayed(const Duration(milliseconds: 1600)),
    ]);
    final api = results[0] as ApiService;
    final profile = results[1] as ProfileService;

    // Landing dari redirect OAuth (GitHub/TikTok) — backend tukar code →
    // token lalu redirect ke .../app/#token=...&email=... (sukses) atau
    // .../app/?error=... (gagal). SplashScreen selalu jadi entry point
    // pertama tiap kali browser reload halaman, jadi dibaca sekali di sini.
    String? authError = Uri.base.queryParameters['error'];
    final fragment = Uri.base.fragment;
    if (fragment.isNotEmpty) {
      final params = Uri.splitQueryString(fragment);
      final incomingToken = params['token'];
      if (incomingToken != null && incomingToken.isNotEmpty) {
        try {
          await api.restoreSocialSession(incomingToken);
          authError = null;
        } catch (e) {
          authError = e.toString();
        }
      }
      clearOAuthRedirectFragment();
    }

    if (!mounted) return;
    Widget target;
    if (!api.isAuthenticated) {
      target = LoginScreen(api: api, initialError: authError);
    } else if (!profile.onboarded) {
      target = OnboardingProfileScreen(api: api, profile: profile);
    } else {
      target = JeonChatScreen(api: api, profile: profile);
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => target));
  }

  @override
  void dispose() {
    _introController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _glow,
                  builder: (context, child) {
                    final blur = 24 + _glow.value * 20;
                    final spread = 2 + _glow.value * 6;
                    return Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [JeonColors.accent, JeonColors.accentDim],
                        ),
                        boxShadow: [
                          BoxShadow(color: JeonColors.accentGlow, blurRadius: blur, spreadRadius: spread),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: child,
                    );
                  },
                  child: const Text(
                    'J',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 38, color: Color(0xFF04150A)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'JEON',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: JeonColors.ink, letterSpacing: 5),
                ),
                const SizedBox(height: 5),
                const Text(
                  'AI Integrated Coworker',
                  style: TextStyle(fontSize: 11.5, color: JeonColors.inkFaint, letterSpacing: 1.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
