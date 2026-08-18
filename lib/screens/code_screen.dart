import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';

/// Code Interpreter — tulis & jalankan kode lewat ApiService.runCode().
/// Kalau user pilih "Kirim ke Chat" setelah run berhasil, halaman ini
/// pop(true) dengan {code, output/error} lewat [Navigator.pop], yang
/// dibaca chat_screen.dart buat ditambahkan sebagai pesan (lihat
/// chat_bubble.dart _codeResultCard untuk cara tampilnya).
class CodeScreen extends StatefulWidget {
  final ApiService api;

  const CodeScreen({super.key, required this.api});

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  final _codeController = TextEditingController();
  bool _running = false;
  String? _output;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _running) return;
    setState(() {
      _running = true;
      _output = null;
      _error = null;
    });
    try {
      final result = await widget.api.runCode(code);
      if (!mounted) return;
      setState(() {
        _output = (result['output'] ?? result['stdout'] ?? result['result'] ?? '').toString();
        final err = result['error'] ?? result['stderr'];
        _error = err == null ? null : err.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _sendToChat() {
    final code = _codeController.text.trim();
    Navigator.of(context).pop({
      'code': code,
      if (_output != null && _output!.isNotEmpty) 'output': _output!,
      if (_error != null && _error!.isNotEmpty) 'error': _error!,
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _output != null || _error != null;
    return Scaffold(
      backgroundColor: JeonColors.bg,
      appBar: AppBar(
        backgroundColor: JeonColors.bg,
        elevation: 0,
        title: const Text('Code Interpreter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (hasResult)
            TextButton(
              onPressed: _sendToChat,
              child: const Text('Kirim ke Chat', style: TextStyle(fontSize: 13, color: JeonColors.accent)),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Kode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.inkMuted)),
            const SizedBox(height: 8),
            Expanded(
              flex: hasResult ? 3 : 5,
              child: Container(
                decoration: BoxDecoration(
                  color: JeonColors.surface2,
                  border: Border.all(color: JeonColors.border),
                  borderRadius: BorderRadius.circular(JeonRadius.card),
                ),
                padding: const EdgeInsets.all(10),
                child: TextField(
                  controller: _codeController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: JeonColors.ink, height: 1.4),
                  decoration: const InputDecoration(
                    hintText: 'print("Halo dari JeonAI")',
                    hintStyle: TextStyle(fontFamily: 'monospace', color: JeonColors.inkFaint),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF04150A)),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 20, color: Color(0xFF04150A)),
                label: Text(_running ? 'Menjalankan...' : 'Run',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: JeonColors.accent,
                  foregroundColor: const Color(0xFF04150A),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
                ),
              ),
            ),
            if (hasResult) ...[
              const SizedBox(height: 16),
              const Text('Output', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.inkMuted)),
              const SizedBox(height: 8),
              Expanded(
                flex: 2,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D0D0D),
                    border: Border.all(color: JeonColors.borderSoft),
                    borderRadius: BorderRadius.circular(JeonRadius.card),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      (_output?.isNotEmpty ?? false) ? _output! : (_error ?? ''),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.4,
                        color: (_error != null && (_output == null || _output!.isEmpty))
                            ? JeonColors.danger
                            : JeonColors.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
