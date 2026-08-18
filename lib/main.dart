import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'theme.dart';

void main() {
  runApp(const JeonChatApp());
}

class JeonChatApp extends StatelessWidget {
  const JeonChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JeonChat',
      debugShowCheckedModeBanner: false,
      theme: buildJeonTheme(),
      home: const SplashScreen(),
    );
  }
}
