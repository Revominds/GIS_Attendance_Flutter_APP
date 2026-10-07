// Roster report screen — filter clock-in/out rows, preview a clean PDF
// roster, then download/share it. Data comes from AdminService.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gis_attendance/services/admin_service.dart';
import 'package:gis_attendance/services/notification_service.dart';
import 'package:gis_attendance/services/report_service.dart';
import 'package:gis_attendance/theme/app_theme.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';

class RosterReportScreen extends StatefulWidget {
  const RosterReportScreen({super.key});
  @override
  State<RosterReportScreen> createState() => _RosterReportScreenState();
}

class _RosterReportScreenState extends State<RosterReportScreen> {
  final _admin = AdminService();
  final _officerCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  bool _building = false;
  String? _error;
  File? _lastFile;

  @override
  void dispose() {
    _officerCtrl.dispose();
    _dateCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  RosterReportFilter get _filter => RosterReportFilter(
        officerId: _officerCtrl.text.trim(),
        date: _dateCtrl.text.trim(),
        from: _fromCtrl.text.trim(),
        to: _toCtrl.text.trim(),
      );

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final res = await _admin.allAttendance(
      officerId: _officerCtrl.text.trim().isEmpty ? null : _officerCtrl.text.trim(),
      date: _dateCtrl.text.trim().isEmpty ? null : _dateCtrl.text.trim(),
      from: _fromCtrl.text.trim().isEmpty ? null : _fromCtrl.text.trim(),
      to: _toCtrl.text.trim().isEmpty ? null : _toCtrl.text.trim(),
      limit: 500,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _rows = res.data ?? [];
      } else {
        _error = res.message;
      }
    });
  }

  Future<List<int>?> _buildPdf() async {
    setState(() => _building = true);
    try {
      return await RosterReportService.buildPdf(rows: _rows, filter: _filter);
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  Future<void> _preview() async {
    final bytes = await _buildPdf();
    if (bytes == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await RosterReportService.preview(bytes);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Preview failed: $e')));
    }
  }

  Future<void> _download() async {
    final bytes = await _buildPdf();
    if (bytes == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // On web there is no file viewer to open — trigger a browser
      // download instead of OpenFilex.
      if (kIsWeb) {
        await Printing.sharePdf(
            bytes: Uint8List.fromList(bytes),
            filename: RosterReportService.fileName(_filter));
        NotificationService.logActivity(
          'Roster PDF downloaded',
          'Duty-roster PDF generated (${_rows.length} records, ${_filter.label}).',
          category: 'Roster',
        );
        messenger.showSnackBar(const SnackBar(
            content: Text('Roster downloaded'),
            backgroundColor: AppColors.success));
        return;
      }
      final file = await RosterReportService.saveToFile(
          bytes, RosterReportService.fileName(_filter));
      if (!mounted) return;
      setState(() => _lastFile = file);
      messenger.showSnackBar(
          SnackBar(content: Text('Saved ${file.path}'), backgroundColor: AppColors.success));
      NotificationService.logActivity(
        'Roster PDF downloaded',
        'Duty-roster PDF generated (${_rows.length} records, ${_filter.label}).',
        category: 'Roster',
      );
      await OpenFilex.open(file.path);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  Future<void> _share() async {
    final bytes = await _buildPdf();
    if (bytes == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      // share_plus has no share sheet on web — download instead.
      if (kIsWeb) {
        await Printing.sharePdf(
            bytes: Uint8List.fromList(bytes),
            filename: RosterReportService.fileName(_filter));
        NotificationService.logActivity(
          'Roster PDF shared',
          'Duty-roster PDF shared (${_rows.length} records, ${_filter.label}).',
          category: 'Roster',
        );
        messenger.showSnackBar(const SnackBar(
            content: Text('Roster downloaded'),
            backgroundColor: AppColors.success));
        return;
      }
      final file = await RosterReportService.saveToFile(
          bytes, RosterReportService.fileName(_filter));
      if (!mounted) return;
      setState(() => _lastFile = file);
      NotificationService.logActivity(
        'Roster PDF shared',
        'Duty-roster PDF shared (${_rows.length} records, ${_filter.label}).',
        category: 'Roster',
      );
      await RosterReportService.share(file);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<void> _pickDate(TextEditingController c) async {
    final now = DateTime.now();
    DateTime initial = now;
    final cur = c.text.trim();
    if (cur.isNotEmpty) {
      try {
        initial = DateTime.parse(cur);
      } catch (_) {}
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.olive,
            onPrimary: Colors.white,
            onSurface: AppColors.oliveDark,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        c.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  Widget _dateField(TextEditingController c, String label) {
    final hasValue = c.text.trim().isNotEmpty;
    return TextField(
      controller: c,
      readOnly: true,
      onTap: () => _pickDate(c),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.event_outlined),
        suffixIcon: hasValue
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 19),
                onPressed: () => setState(c.clear),
              )
            : IconButton(
                icon: const Icon(Icons.calendar_month_outlined, size: 19),
                onPressed: () => _pickDate(c),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open =
        _rows.where((r) => r['is_open'] == true || r['check_out_time'] == null).length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        const PremiumHeader(
            title: 'Roster reports',
            subtitle: 'Filter clock-in / clock-out rows, preview a clean PDF, download or share.'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              TextField(controller: _officerCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Officer ID (optional)', prefixIcon: Icon(Icons.badge_outlined))),
              const SizedBox(height: 8),
              LayoutBuilder(builder: (ctx, c) {
                if (c.maxWidth >= 560) {
                  return Row(children: [
                    Expanded(child: _dateField(_dateCtrl, 'Date')),
                    const SizedBox(width: 8),
                    Expanded(child: _dateField(_fromCtrl, 'From')),
                    const SizedBox(width: 8),
                    Expanded(child: _dateField(_toCtrl, 'To')),
                  ]);
                }
                return Column(children: [
                  _dateField(_dateCtrl, 'Date'),
                  const SizedBox(height: 8),
                  _dateField(_fromCtrl, 'From'),
                  const SizedBox(height: 8),
                  _dateField(_toCtrl, 'To'),
                ]);
              }),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity,
                  child: ElevatedButton.icon(
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.search, size: 18),
                      label: Text(_loading ? 'Loading…' : 'Load records'))),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          StatTile(label: 'Records', value: '${_rows.length}', icon: Icons.receipt_long),
          const SizedBox(width: 10),
          StatTile(label: 'Still clocked in', value: '$open',
              color: AppColors.success, icon: Icons.timelapse),
        ]),
        const SizedBox(height: 12),
        if (_error != null)
          Card(child: Padding(padding: const EdgeInsets.all(14),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)))),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('PDF actions  •  ${_filter.label}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ElevatedButton.icon(
                    onPressed: (_rows.isEmpty || _building) ? null : _preview,
                    icon: const Icon(Icons.preview_outlined, size: 18),
                    label: Text(_building ? 'Building…' : 'Preview PDF')),
                OutlinedButton.icon(
                    onPressed: (_rows.isEmpty || _building) ? null : _download,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Download / Open')),
                OutlinedButton.icon(
                    onPressed: (_rows.isEmpty || _building) ? null : _share,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share')),
              ]),
              if (_lastFile != null) ...[
                const SizedBox(height: 8),
                Text('Last file: ${_lastFile!.path}',
                    style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ],
              if (_rows.isEmpty && _error == null && !_loading)
                const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Load records first — the PDF mirrors the table above.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted))),
            ]),
          ),
        ),
      ]),
    );
  }
}
