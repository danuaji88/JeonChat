import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../services/api_service.dart';
import '../theme.dart';

const _gmailRed = Color(0xFFEA4335);
const _calendarBlue = Color(0xFF4285F4);
const _driveGreen = Color(0xFF34A853);
const _sheetsGreen = Color(0xFF0F9D58);

/// "Integrasi Google" (fase 3.2) — hubungkan akun Google (satu izin untuk
/// Gmail/Calendar/Drive/Sheets sekaligus, lihat connectorAuthUrl) lalu
/// jalankan aksi ringan per layanan lewat /connectors. Backend sudah live —
/// layar ini murni UI + panggilan API.
class ConnectorsScreen extends StatefulWidget {
  final ApiService api;

  const ConnectorsScreen({super.key, required this.api});

  @override
  State<ConnectorsScreen> createState() => _ConnectorsScreenState();
}

class _ConnectorsScreenState extends State<ConnectorsScreen> with WidgetsBindingObserver {
  bool _loading = true;
  String? _error;
  bool _connected = false;
  List<String> _scopes = [];
  bool _connecting = false;
  bool _disconnecting = false;

  final _gmailQueryController = TextEditingController();
  bool _gmailSearching = false;
  List<Map<String, dynamic>>? _gmailResults;

  bool _calendarLoading = false;
  List<Map<String, dynamic>>? _calendarEvents;

  bool _driveLoading = false;
  List<Map<String, dynamic>>? _driveFiles;

  bool _sheetsLoading = false;
  List<List<dynamic>>? _sheetsRows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gmailQueryController.dispose();
    super.dispose();
  }

  /// Tab Google OAuth kebuka di tab BARU (LaunchMode.externalApplication,
  /// lihat _connect) — tab Flutter ini sendiri tetap idle di background.
  /// Begitu user kembali (switch tab/window), status koneksi disegarkan
  /// otomatis; tombol "Saya sudah selesai" di UI jadi cadangan manual kalau
  /// browser/OS tidak memicu transisi resumed ini secara andal.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.api.connectorStatus();
      if (!mounted) return;
      final rawScopes = res['scopes'];
      setState(() {
        _connected = res['connected'] == true;
        _scopes = rawScopes is List ? rawScopes.map((e) => e.toString()).toList() : const [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: JeonColors.danger));
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 1)));
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      final res = await widget.api.connectorAuthUrl();
      final url = (res['url'] ?? res['auth_url'] ?? '').toString();
      if (url.isEmpty) throw Exception('URL otorisasi tidak ditemukan pada respons server');
      final ok = await launchUrlString(url, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _showError('Gagal membuka halaman otorisasi Google.');
    } catch (e) {
      if (!mounted) return;
      _showError('Gagal memulai koneksi: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JeonColors.surface,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        elevation: 16,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Putuskan koneksi Google?',
            style: TextStyle(color: JeonColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text(
          'JEON Chat tidak akan bisa lagi mengakses Gmail, Calendar, Drive, atau Sheets kamu sampai dihubungkan ulang.',
          style: TextStyle(color: JeonColors.inkFaint, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal', style: TextStyle(color: JeonColors.inkFaint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Putuskan', style: TextStyle(color: JeonColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _disconnecting = true);
    try {
      await widget.api.connectorDisconnect();
      if (!mounted) return;
      setState(() {
        _connected = false;
        _scopes = [];
        _gmailResults = null;
        _calendarEvents = null;
        _driveFiles = null;
        _sheetsRows = null;
      });
      _showInfo('Koneksi Google diputus');
    } catch (e) {
      if (!mounted) return;
      _showError('Gagal memutuskan koneksi: $e');
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  Future<void> _searchGmail() async {
    final query = _gmailQueryController.text.trim();
    if (query.isEmpty) return;
    setState(() => _gmailSearching = true);
    try {
      final res = await widget.api.connectorAction('gmail_search', {'query': query});
      final list = _extractList(res, ['results', 'messages', 'emails']);
      if (!mounted) return;
      setState(() {
        _gmailResults = list.take(5).toList();
        _gmailSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _gmailSearching = false);
      _showError('Gagal cari email: $e');
    }
  }

  Future<void> _loadCalendar() async {
    setState(() => _calendarLoading = true);
    try {
      final res = await widget.api.connectorAction('calendar_list', const {});
      final list = _extractList(res, ['events', 'items', 'results']);
      if (!mounted) return;
      setState(() {
        _calendarEvents = list;
        _calendarLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _calendarLoading = false);
      _showError('Gagal ambil agenda: $e');
    }
  }

  Future<void> _loadDrive() async {
    setState(() => _driveLoading = true);
    try {
      final res = await widget.api.connectorAction('drive_search', const {});
      final list = _extractList(res, ['files', 'items', 'results']);
      if (!mounted) return;
      setState(() {
        _driveFiles = list;
        _driveLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _driveLoading = false);
      _showError('Gagal ambil file Drive: $e');
    }
  }

  Future<void> _loadSheet() async {
    setState(() => _sheetsLoading = true);
    try {
      final res = await widget.api
          .connectorAction('sheets_get', const {'spreadsheet_id': '', 'range': 'A1:F10'});
      final raw = res['values'] ?? res['rows'];
      final rows = raw is List ? raw.whereType<List>().map((r) => r.toList()).toList() : <List<dynamic>>[];
      if (!mounted) return;
      setState(() {
        _sheetsRows = rows;
        _sheetsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sheetsLoading = false);
      _showError('Gagal baca sheet: $e');
    }
  }

  List<Map<String, dynamic>> _extractList(Map<String, dynamic> res, List<String> keys) {
    for (final key in keys) {
      final raw = res[key];
      if (raw is List) {
        return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      appBar: AppBar(
        backgroundColor: JeonColors.bg,
        elevation: 0,
        title: const Text('Integrasi Google', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: JeonColors.accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 30, color: JeonColors.inkFaint),
              const SizedBox(height: 12),
              Text('Gagal memuat status koneksi.\n$_error',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: JeonColors.inkFaint)),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: _loadStatus,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: JeonColors.accent,
                    side: const BorderSide(color: JeonColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Coba Lagi', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _statusCard(),
        const SizedBox(height: 16),
        _connectorCard(
          color: _gmailRed,
          icon: Icons.mail_outline,
          title: 'Gmail',
          subtitle: 'Baca & kirim email',
          child: _connected ? _gmailAction() : null,
        ),
        const SizedBox(height: 12),
        _connectorCard(
          color: _calendarBlue,
          icon: Icons.calendar_today_outlined,
          title: 'Google Calendar',
          subtitle: 'Jadwal & agenda',
          child: _connected ? _calendarAction() : null,
        ),
        const SizedBox(height: 12),
        _connectorCard(
          color: _driveGreen,
          icon: Icons.cloud_outlined,
          title: 'Google Drive',
          subtitle: 'File & dokumen',
          child: _connected ? _driveAction() : null,
        ),
        const SizedBox(height: 12),
        _connectorCard(
          color: _sheetsGreen,
          icon: Icons.table_chart_outlined,
          title: 'Google Sheets',
          subtitle: 'Spreadsheet & data',
          child: _connected ? _sheetsAction() : null,
        ),
      ],
    );
  }

  Widget _statusCard() {
    if (!_connected) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [JeonColors.accent.withValues(alpha: 0.18), JeonColors.accentDim.withValues(alpha: 0.10)],
          ),
          border: Border.all(color: JeonColors.accent.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Hubungkan akun Google kamu',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
            const SizedBox(height: 4),
            const Text(
              'Satu izin untuk mengakses Gmail, Calendar, Drive, dan Sheets lewat JEON Chat.',
              style: TextStyle(fontSize: 12.5, color: JeonColors.inkFaint, height: 1.4),
            ),
            const SizedBox(height: 14),
            _PremiumButton(
              label: 'Hubungkan Google',
              icon: Icons.link,
              loading: _connecting,
              onTap: _connecting ? null : _connect,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _loading ? null : _loadStatus,
                child: const Text('Saya sudah selesai — cek ulang status',
                    style: TextStyle(fontSize: 12, color: JeonColors.accent, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JeonColors.ink.withValues(alpha: 0.04),
        border: Border.all(color: JeonColors.borderSoft),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _driveGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('✓ Terhubung',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _driveGreen)),
                ),
                if (_scopes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(_scopes.join(', '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          _disconnecting
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: JeonColors.danger))
              : InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _confirmDisconnect,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: JeonColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.link_off, size: 14, color: JeonColors.danger),
                        SizedBox(width: 5),
                        Text('Putuskan',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: JeonColors.danger)),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _connectorCard({
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget? child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JeonColors.ink.withValues(alpha: 0.04),
        border: Border.all(color: JeonColors.borderSoft),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: JeonColors.inkFaint)),
                  ],
                ),
              ),
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 12),
            child,
          ] else if (!_connected) ...[
            const SizedBox(height: 10),
            const Text('Hubungkan Google dulu untuk pakai fitur ini.',
                style: TextStyle(fontSize: 11.5, color: JeonColors.inkFaint, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  Widget _gmailAction() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _gmailQueryController,
                onSubmitted: (_) => _searchGmail(),
                style: const TextStyle(fontSize: 13, color: JeonColors.ink),
                decoration: InputDecoration(
                  hintText: 'Cari email...',
                  hintStyle: const TextStyle(color: JeonColors.inkFaint, fontSize: 12.5),
                  filled: true,
                  fillColor: JeonColors.ink.withValues(alpha: 0.06),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _squareIconButton(Icons.search, loading: _gmailSearching, onTap: _gmailSearching ? null : _searchGmail),
          ],
        ),
        if (_gmailResults != null) ...[
          const SizedBox(height: 10),
          if (_gmailResults!.isEmpty)
            const Text('Tidak ada email ditemukan.', style: TextStyle(fontSize: 12, color: JeonColors.inkFaint))
          else
            ..._gmailResults!.map((m) => _resultTile(
                  title: (m['subject'] ?? m['title'] ?? '(tanpa subjek)').toString(),
                  subtitle: (m['from'] ?? m['sender'] ?? '').toString(),
                  detail: (m['snippet'] ?? '').toString(),
                )),
        ],
      ],
    );
  }

  Widget _calendarAction() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _outlineActionButton('Agenda hari ini', loading: _calendarLoading, onTap: _calendarLoading ? null : _loadCalendar),
        if (_calendarEvents != null) ...[
          const SizedBox(height: 10),
          if (_calendarEvents!.isEmpty)
            const Text('Tidak ada agenda.', style: TextStyle(fontSize: 12, color: JeonColors.inkFaint))
          else
            ..._calendarEvents!.map((e) => _resultTile(
                  title: (e['summary'] ?? e['title'] ?? '(tanpa judul)').toString(),
                  subtitle: (e['start'] ?? '').toString(),
                )),
        ],
      ],
    );
  }

  Widget _driveAction() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _outlineActionButton('File terbaru', loading: _driveLoading, onTap: _driveLoading ? null : _loadDrive),
        if (_driveFiles != null) ...[
          const SizedBox(height: 10),
          if (_driveFiles!.isEmpty)
            const Text('Tidak ada file ditemukan.', style: TextStyle(fontSize: 12, color: JeonColors.inkFaint))
          else
            ..._driveFiles!.map((f) => _resultTile(
                  title: (f['name'] ?? '(tanpa nama)').toString(),
                  subtitle: (f['mimeType'] ?? '').toString(),
                )),
        ],
      ],
    );
  }

  Widget _sheetsAction() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _outlineActionButton('Baca sheet', loading: _sheetsLoading, onTap: _sheetsLoading ? null : _loadSheet),
        if (_sheetsRows != null) ...[
          const SizedBox(height: 10),
          if (_sheetsRows!.isEmpty)
            const Text('Tidak ada data.', style: TextStyle(fontSize: 12, color: JeonColors.inkFaint))
          else
            _sheetsTable(_sheetsRows!),
        ],
      ],
    );
  }

  Widget _sheetsTable(List<List<dynamic>> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        border: const TableBorder.symmetric(inside: BorderSide(color: JeonColors.borderSoft)),
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          for (int r = 0; r < rows.length; r++)
            TableRow(
              decoration: BoxDecoration(color: r == 0 ? JeonColors.ink.withValues(alpha: 0.06) : null),
              children: [
                for (final cell in rows[r])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Text(cell.toString(),
                        style: TextStyle(
                            fontSize: 12,
                            color: JeonColors.ink,
                            fontWeight: r == 0 ? FontWeight.w700 : FontWeight.normal)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _resultTile({required String title, String subtitle = '', String detail = ''}) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: JeonColors.surface2, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: JeonColors.ink)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
          ],
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(detail,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: JeonColors.inkFaint)),
          ],
        ],
      ),
    );
  }

  Widget _outlineActionButton(String label, {required bool loading, required VoidCallback? onTap}) {
    return SizedBox(
      height: 46,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: JeonColors.ink,
          side: const BorderSide(color: JeonColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: loading
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: JeonColors.accent))
            : const Icon(Icons.refresh_rounded, size: 18, color: JeonColors.inkMuted),
        label: Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _squareIconButton(IconData icon, {required bool loading, required VoidCallback? onTap}) {
    final disabled = onTap == null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: disabled ? JeonColors.accent.withValues(alpha: 0.4) : JeonColors.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF04150A)))
            : Icon(icon, size: 18, color: const Color(0xFF04150A)),
      ),
    );
  }
}

/// Tombol premium bersama — tinggi 46, radius 12, shadow halus (black 0.08
/// blur 8), micro-interaction scale 0.98 saat ditekan, loading spinner 16px.
class _PremiumButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onTap;

  const _PremiumButton({required this.label, this.icon, required this.loading, required this.onTap});

  @override
  State<_PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<_PremiumButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
        onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [JeonColors.accent, JeonColors.accentDim]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF04150A)))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 18, color: const Color(0xFF04150A)),
                      const SizedBox(width: 8),
                    ],
                    Text(widget.label,
                        style: const TextStyle(color: Color(0xFF04150A), fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ],
                ),
        ),
      ),
    );
  }
}
