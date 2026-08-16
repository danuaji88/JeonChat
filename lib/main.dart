import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'services/api_service.dart';
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
      home: const _JeonChatRoot(),
    );
  }
}

class _JeonChatRoot extends StatefulWidget {
  const _JeonChatRoot();

  @override
  State<_JeonChatRoot> createState() => _JeonChatRootState();
}

class _JeonChatRootState extends State<_JeonChatRoot> {
  ApiService? _api;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final api = await ApiService.loadFromPrefs();
    setState(() => _api = api);
  }

  @override
  Widget build(BuildContext context) {
    if (_api == null) {
      return const Scaffold(
        backgroundColor: JeonColors.bg,
        body: Center(child: CircularProgressIndicator(color: JeonColors.accent)),
      );
    }
    return ChatScreen(api: _api!);
  }
}
