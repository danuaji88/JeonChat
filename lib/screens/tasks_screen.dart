import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';

/// "Tugas Terjadwal" (fase 3.3) — CRUD pengingat berjadwal via /tasks
/// (action list/create/update/delete/toggle). Notifikasi saat tugas
/// jalan (fired) dikelola terpisah lewat /notifications, badge-nya
/// dirender di sidebar (lihat NotificationBadge + _pollNotifications di
/// chat_screen.dart) — layar ini murni CRUD tugasnya.
class TasksScreen extends StatefulWidget {
  final ApiService api;

  const TasksScreen({super.key, required this.api});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  List<Map<String, dynamic>> _tasks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tasks = await widget.api.listTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
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

  Future<void> _openForm({Map<String, dynamic>? task}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JeonColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _TaskFormSheet(existing: task),
    );
    if (result == null) return;
    try {
      if (task == null) {
        await widget.api.createTask(
          title: result['title'] as String,
          message: result['message'] as String,
          scheduleType: result['scheduleType'] as String,
          scheduleValue: result['scheduleValue'] as String,
        );
      } else {
        await widget.api.updateTask(
          task['id']?.toString() ?? '',
          title: result['title'] as String,
          message: result['message'] as String,
          scheduleType: result['scheduleType'] as String,
          scheduleValue: result['scheduleValue'] as String,
        );
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(task == null ? 'Tugas dibuat' : 'Tugas diperbarui'),
            duration: const Duration(seconds: 1)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    }
  }

  Future<void> _toggleTask(Map<String, dynamic> task) async {
    final id = task['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      final updated = await widget.api.toggleTask(id);
      if (!mounted) return;
      setState(() {
        final idx = _tasks.indexWhere((t) => t['id']?.toString() == id);
        if (idx == -1) return;
        _tasks[idx] = updated.isNotEmpty ? updated : {...task, 'enabled': task['enabled'] != true};
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal ubah status: $e')));
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JeonColors.surface,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        elevation: 16,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus tugas ini?',
            style: TextStyle(color: JeonColors.ink, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text('"${(task['title'] ?? 'Tugas ini').toString()}" akan dihapus permanen.',
            style: const TextStyle(color: JeonColors.inkFaint, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal', style: TextStyle(color: JeonColors.inkFaint)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus', style: TextStyle(color: JeonColors.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = task['id']?.toString() ?? '';
    try {
      await widget.api.deleteTask(id);
      if (!mounted) return;
      setState(() => _tasks.removeWhere((t) => t['id']?.toString() == id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal hapus: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: JeonColors.bg,
      appBar: AppBar(
        backgroundColor: JeonColors.bg,
        elevation: 0,
        title: const Text('Tugas Terjadwal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        backgroundColor: JeonColors.accent,
        foregroundColor: const Color(0xFF04150A),
        child: const Icon(Icons.add),
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
              Text('Gagal memuat tugas.\n$_error',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: JeonColors.inkFaint)),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: _load,
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
    return RefreshIndicator(
      color: JeonColors.accent,
      backgroundColor: JeonColors.surface2,
      onRefresh: _load,
      child: _tasks.isEmpty
          ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [_emptyState()])
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: _tasks.length,
              itemBuilder: (context, i) => _taskCard(_tasks[i]),
            ),
    );
  }

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.only(top: 90),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_note_outlined, size: 30, color: JeonColors.inkFaint),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text('Belum ada tugas terjadwal. Buat pengingat pertama kamu!',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: JeonColors.inkFaint)),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 180,
              child: _PremiumButton(label: 'Buat Tugas', loading: false, onTap: () => _openForm()),
            ),
          ],
        ),
      );

  Widget _taskCard(Map<String, dynamic> task) {
    final title = (task['title'] ?? '').toString();
    final message = (task['message'] ?? '').toString();
    final scheduleType = (task['schedule_type'] ?? '').toString();
    final scheduleValue = (task['schedule_value'] ?? '').toString();
    final enabled = task['enabled'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JeonColors.surface2,
        border: Border.all(color: JeonColors.borderSoft),
        borderRadius: BorderRadius.circular(JeonRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title.isEmpty ? 'Tugas' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: JeonColors.ink)),
              ),
              Switch(
                value: enabled,
                onChanged: (_) => _toggleTask(task),
                activeThumbColor: JeonColors.accent,
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: JeonColors.inkFaint, height: 1.4)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule, size: 13, color: JeonColors.accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(_formatSchedule(scheduleType, scheduleValue),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: JeonColors.accent, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _cardAction(Icons.edit_outlined, 'Edit', () => _openForm(task: task)),
              const SizedBox(width: 4),
              _cardAction(Icons.delete_outline, 'Hapus', () => _confirmDelete(task), color: JeonColors.danger),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardAction(IconData icon, String label, VoidCallback onTap, {Color? color}) => InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color ?? JeonColors.inkMuted),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color ?? JeonColors.inkMuted)),
            ],
          ),
        ),
      );

  String _formatSchedule(String type, String value) {
    switch (type) {
      case 'interval':
        final n = int.tryParse(value) ?? 0;
        if (n >= 60 && n % 60 == 0) return 'Setiap ${n ~/ 60} jam';
        return 'Setiap $n menit';
      case 'daily':
        return 'Setiap hari $value';
      case 'weekly':
        return 'Setiap $value';
      case 'once':
        return 'Sekali ${value.replaceFirst('T', ' ')}';
      case 'cron':
        return value;
      default:
        return value;
    }
  }
}

/// Form buat/edit tugas — bottom sheet dengan field jadwal yang berubah
/// sesuai tipe (interval/daily/weekly/once/cron). Tidak memanggil API sama
/// sekali — cuma validasi lalu pop() dengan data mentahnya, pemanggilan
/// createTask/updateTask jadi tanggung jawab TasksScreen (lihat _openForm).
class _TaskFormSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const _TaskFormSheet({this.existing});

  @override
  State<_TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends State<_TaskFormSheet> {
  static const _days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
  static const _scheduleTypes = {
    'once': 'Sekali',
    'interval': 'Interval',
    'daily': 'Setiap Hari',
    'weekly': 'Setiap Minggu',
    'cron': 'Cron',
  };

  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _intervalController = TextEditingController(text: '60');
  final _cronController = TextEditingController();

  String _scheduleType = 'once';
  DateTime? _onceDate;
  TimeOfDay? _onceTime;
  TimeOfDay _dailyTime = const TimeOfDay(hour: 9, minute: 0);
  String _weeklyDay = 'Senin';
  TimeOfDay _weeklyTime = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleController.text = (e['title'] ?? '').toString();
      _messageController.text = (e['message'] ?? '').toString();
      _scheduleType = (e['schedule_type'] ?? 'once').toString();
      if (!_scheduleTypes.containsKey(_scheduleType)) _scheduleType = 'once';
      _prefillScheduleValue(_scheduleType, (e['schedule_value'] ?? '').toString());
    }
  }

  void _prefillScheduleValue(String type, String value) {
    switch (type) {
      case 'interval':
        _intervalController.text = value.isNotEmpty ? value : '60';
        break;
      case 'daily':
        final parts = value.split(':');
        if (parts.length == 2) {
          _dailyTime = TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0);
        }
        break;
      case 'weekly':
        final parts = value.split(' ');
        if (parts.length == 2) {
          _weeklyDay = _days.contains(parts[0]) ? parts[0] : 'Senin';
          final timeParts = parts[1].split(':');
          if (timeParts.length == 2) {
            _weeklyTime = TimeOfDay(hour: int.tryParse(timeParts[0]) ?? 9, minute: int.tryParse(timeParts[1]) ?? 0);
          }
        }
        break;
      case 'once':
        final dt = DateTime.tryParse(value);
        if (dt != null) {
          _onceDate = DateTime(dt.year, dt.month, dt.day);
          _onceTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
        }
        break;
      case 'cron':
        _cronController.text = value;
        break;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _intervalController.dispose();
    _cronController.dispose();
    super.dispose();
  }

  String _twoDigit(int n) => n.toString().padLeft(2, '0');

  String? _buildScheduleValue() {
    switch (_scheduleType) {
      case 'interval':
        final n = int.tryParse(_intervalController.text.trim());
        if (n == null || n < 1) return null;
        return '$n';
      case 'daily':
        return '${_twoDigit(_dailyTime.hour)}:${_twoDigit(_dailyTime.minute)}';
      case 'weekly':
        return '$_weeklyDay ${_twoDigit(_weeklyTime.hour)}:${_twoDigit(_weeklyTime.minute)}';
      case 'once':
        final d = _onceDate;
        final t = _onceTime;
        if (d == null || t == null) return null;
        return '${d.year}-${_twoDigit(d.month)}-${_twoDigit(d.day)}T${_twoDigit(t.hour)}:${_twoDigit(t.minute)}';
      case 'cron':
        final v = _cronController.text.trim();
        return v.isEmpty ? null : v;
    }
    return null;
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Judul tidak boleh kosong')));
      return;
    }
    final scheduleValue = _buildScheduleValue();
    if (scheduleValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lengkapi jadwal dulu')));
      return;
    }
    Navigator.of(context).pop({
      'title': title,
      'message': _messageController.text.trim(),
      'scheduleType': _scheduleType,
      'scheduleValue': scheduleValue,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Tugas Baru' : 'Edit Tugas',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: JeonColors.ink)),
            const SizedBox(height: 16),
            _label('JUDUL'),
            const SizedBox(height: 6),
            _textField(_titleController, hint: 'Contoh: Ingatkan cek laporan'),
            const SizedBox(height: 14),
            _label('PESAN'),
            const SizedBox(height: 6),
            _textField(_messageController, hint: 'Isi pesan pengingat', maxLines: 3),
            const SizedBox(height: 14),
            _label('TIPE JADWAL'),
            const SizedBox(height: 6),
            _scheduleTypeDropdown(),
            const SizedBox(height: 14),
            _scheduleValueField(),
            const SizedBox(height: 20),
            _PremiumButton(label: 'Simpan', loading: false, onTap: _save),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style:
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: JeonColors.inkMuted, letterSpacing: 1.2));

  Widget _textField(TextEditingController controller,
      {String? hint, int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: JeonColors.inkFaint, fontSize: 12.5),
        filled: true,
        fillColor: JeonColors.ink.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _scheduleTypeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: JeonColors.ink.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _scheduleType,
          isExpanded: true,
          dropdownColor: JeonColors.surface2,
          style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
          items: _scheduleTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _scheduleType = v);
          },
        ),
      ),
    );
  }

  Widget _scheduleValueField() {
    switch (_scheduleType) {
      case 'interval':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('SETIAP BERAPA MENIT'),
            const SizedBox(height: 6),
            _textField(_intervalController, hint: 'Contoh: 60', keyboardType: TextInputType.number),
          ],
        );
      case 'daily':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('JAM'),
            const SizedBox(height: 6),
            _timePickerButton(_dailyTime, (t) => setState(() => _dailyTime = t)),
          ],
        );
      case 'weekly':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('HARI'),
            const SizedBox(height: 6),
            _dayDropdown(),
            const SizedBox(height: 14),
            _label('JAM'),
            const SizedBox(height: 6),
            _timePickerButton(_weeklyTime, (t) => setState(() => _weeklyTime = t)),
          ],
        );
      case 'once':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('TANGGAL & JAM'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _datePickerButton()),
                const SizedBox(width: 10),
                Expanded(child: _onceTimePickerButton()),
              ],
            ),
          ],
        );
      case 'cron':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('EKSPRESI CRON'),
            const SizedBox(height: 6),
            _textField(_cronController, hint: 'Contoh: 0 9 * * 1'),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _dayDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: JeonColors.ink.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _weeklyDay,
          isExpanded: true,
          dropdownColor: JeonColors.surface2,
          style: const TextStyle(fontSize: 13.4, color: JeonColors.ink),
          items: _days.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _weeklyDay = v);
          },
        ),
      ),
    );
  }

  Widget _datePickerButton() {
    final d = _onceDate;
    final label = d == null ? 'Pilih tanggal' : '${d.year}-${_twoDigit(d.month)}-${_twoDigit(d.day)}';
    return _pickerButton(Icons.calendar_today_outlined, label, () async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: _onceDate ?? now,
        firstDate: now.subtract(const Duration(days: 1)),
        lastDate: now.add(const Duration(days: 3650)),
      );
      if (picked != null) setState(() => _onceDate = picked);
    });
  }

  Widget _onceTimePickerButton() {
    final t = _onceTime;
    final label = t == null ? 'Pilih jam' : '${_twoDigit(t.hour)}:${_twoDigit(t.minute)}';
    return _pickerButton(Icons.access_time, label, () async {
      final picked = await showTimePicker(context: context, initialTime: _onceTime ?? TimeOfDay.now());
      if (picked != null) setState(() => _onceTime = picked);
    });
  }

  Widget _timePickerButton(TimeOfDay time, ValueChanged<TimeOfDay> onChanged) {
    final label = '${_twoDigit(time.hour)}:${_twoDigit(time.minute)}';
    return _pickerButton(Icons.access_time, label, () async {
      final picked = await showTimePicker(context: context, initialTime: time);
      if (picked != null) onChanged(picked);
    });
  }

  Widget _pickerButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: JeonColors.ink.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: JeonColors.inkMuted),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: JeonColors.ink))),
          ],
        ),
      ),
    );
  }
}

/// Tombol premium bersama — tinggi 46, radius 12, shadow halus (black 0.08
/// blur 8), micro-interaction scale 0.98 saat ditekan, loading spinner 16px.
class _PremiumButton extends StatefulWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  const _PremiumButton({required this.label, required this.loading, required this.onTap});

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
            color: JeonColors.accent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          alignment: Alignment.center,
          child: widget.loading
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF04150A)))
              : Text(widget.label,
                  style: const TextStyle(color: Color(0xFF04150A), fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
