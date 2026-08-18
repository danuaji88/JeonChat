import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';

const _outputGreen = Color(0xFF2ECC71);

/// Code Interpreter — tulis & jalankan kode (default Python) lewat
/// ApiService.runCode(). Kalau user pilih "Kirim ke Chat" setelah run,
/// halaman ini pop(true) dengan {code, output/error} lewat [Navigator.pop],
/// dibaca chat_screen.dart buat ditambahkan sebagai pesan (lihat
/// chat_bubble.dart _codeResultCard untuk cara tampilnya).
class CodeScreen extends StatefulWidget {
  final ApiService api;

  const CodeScreen({super.key, required this.api});

  @override
  State<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends State<CodeScreen> {
  static const _welcomeCode = '# Contoh:\nprint("Halo JEON!")\nfor i in range(5):\n    print(f"Baris {i}")';

  final _codeController = TextEditingController(text: _welcomeCode);
  bool _running = false;
  String? _output;
  String? _error;
  String? _exitCode;

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
      _exitCode = null;
    });
    try {
      final result = await widget.api.runCode(code);
      if (!mounted) return;
      setState(() {
        final out = (result['output'] ?? result['stdout'] ?? result['result'] ?? '').toString();
        _output = out.isEmpty ? null : out;
        final err = result['error'] ?? result['stderr'];
        _error = (err == null || err.toString().isEmpty) ? null : err.toString();
        final exitCode = result['exit_code'] ?? result['exitCode'];
        _exitCode = exitCode?.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _clear() {
    setState(() {
      _codeController.clear();
      _output = null;
      _error = null;
      _exitCode = null;
    });
  }

  void _sendToChat() {
    final code = _codeController.text.trim();
    Navigator.of(context).pop({
      'code': code,
      if (_output != null) 'output': _output!,
      if (_error != null) 'error': _error!,
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
            Row(
              children: [
                const Text('Kode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.inkMuted)),
                const Spacer(),
                const Text('Python', style: TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
              ],
            ),
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
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
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
                        backgroundColor: _outputGreen,
                        foregroundColor: const Color(0xFF04150A),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _running ? null : _clear,
                    icon: const Icon(Icons.clear, size: 18, color: JeonColors.inkMuted),
                    label: const Text('Clear', style: TextStyle(fontSize: 13, color: JeonColors.inkMuted)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: JeonColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JeonRadius.pill)),
                    ),
                  ),
                ),
              ],
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_output != null)
                          SelectableText(_output!,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12.5, height: 1.4, color: _outputGreen)),
                        if (_error != null) ...[
                          if (_output != null) const SizedBox(height: 8),
                          SelectableText(_error!,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12.5, height: 1.4, color: JeonColors.danger)),
                        ],
                        if (_exitCode != null) ...[
                          const SizedBox(height: 8),
                          Text('Exit code: $_exitCode',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: JeonColors.inkFaint)),
                        ],
                      ],
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
