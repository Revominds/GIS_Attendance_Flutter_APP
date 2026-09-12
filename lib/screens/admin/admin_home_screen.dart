// ADMIN HOME — officer management, registration approvals, password
// resets and attendance oversight. Reachable from the drawer only when
// AuthService.isAdmin() is true (role-gated, same login).

import 'package:flutter/material.dart';
import 'package:gis_attendance/services/admin_service.dart';

const _olive = Color(0xFF2E4D2A);
const _dark = Color(0xFF142412);
const _gold = Color(0xFFE1B12C);
const _red = Color(0xFFD63031);
const _green = Color(0xFF2ED573);
const _bg = Color(0xFFF5F6F5);
const _muted = Color(0xFF6E7A6C);

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _olive,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text("Admin", style: TextStyle(fontWeight: FontWeight.w700)),
          bottom: const TabBar(
            indicatorColor: _gold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: "Officers"),
              Tab(text: "Approvals"),
              Tab(text: "Attendance"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_OfficersTab(), _ApprovalsTab(), _AttendanceTab()],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------
// shared helpers
// --------------------------------------------------------------------------

void _snack(BuildContext context, String msg, {bool ok = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: ok ? _green : _red,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<bool> _confirm(BuildContext context, String title, String message,
    {String confirmLabel = "Confirm", Color confirmColor = _red}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: _muted))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel,
                style: TextStyle(color: confirmColor, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  return res == true;
}

String _s(dynamic v) => (v ?? '').toString();

// --------------------------------------------------------------------------
// OFFICERS
// --------------------------------------------------------------------------

class _OfficersTab extends StatefulWidget {
  const _OfficersTab();
  @override
  State<_OfficersTab> createState() => _OfficersTabState();
}

class _OfficersTabState extends State<_OfficersTab> {
  final _admin = AdminService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _admin.listOfficers();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _all = res.data ?? [];
        _all.sort((a, b) => _s(a['officer_id']).compareTo(_s(b['officer_id'])));
      } else {
        _error = res.message;
      }
    });
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all.where((o) {
      return _s(o['officer_id']).toLowerCase().contains(q) ||
          _s(o['full_name']).toLowerCase().contains(q) ||
          _s(o['email']).toLowerCase().contains(q) ||
          _s(o['department']).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _olive,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text("New officer"),
        onPressed: () async {
          final created = await showDialog<bool>(
            context: context,
            builder: (_) => const _OfficerFormDialog(),
          );
          if (created == true) _load();
        },
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: "Search by ID, name, email, department",
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _olive))
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _officerCard(_filtered[i]),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _officerCard(Map<String, dynamic> o) {
    final active = o['is_active'] == true;
    final isAdmin = _s(o['role']) == 'admin';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openActions(o),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: _olive.withValues(alpha: 0.12),
                child: Text(
                  (_s(o['full_name']).isNotEmpty ? _s(o['full_name'])[0] : '?')
                      .toUpperCase(),
                  style: const TextStyle(color: _olive, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(_s(o['full_name']),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(width: 6),
                          const _Chip(text: "ADMIN", color: _gold),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text("${_s(o['officer_id'])}  ·  ${_s(o['department'])}",
                        style: const TextStyle(fontSize: 12, color: _muted)),
                  ],
                ),
              ),
              _Chip(
                text: active ? "Active" : "Inactive",
                color: active ? _green : _muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openActions(Map<String, dynamic> o) {
    final officerId = _s(o['officer_id']);
    final active = o['is_active'] == true;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(_s(o['full_name']),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(officerId, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: _olive),
              title: const Text("Edit details"),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final saved = await showDialog<bool>(
                  context: context,
                  builder: (_) => _OfficerFormDialog(existing: o),
                );
                if (saved == true) _load();
              },
            ),
            ListTile(
              leading: Icon(active ? Icons.pause_circle_outline : Icons.play_circle_outline,
                  color: active ? _red : _green),
              title: Text(active ? "Deactivate" : "Activate"),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final res = await _admin.setOfficerActive(officerId, !active);
                if (!mounted) return;
                _snack(context, res.ok ? "Updated." : res.message, ok: res.ok);
                if (res.ok) _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.password_outlined, color: _olive),
              title: const Text("Reset password"),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await _resetPassword(officerId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: _red),
              title: const Text("Delete officer", style: TextStyle(color: _red)),
              onTap: () async {
                Navigator.pop(sheetCtx);
                if (await _confirm(context, "Delete officer",
                    "Permanently delete $officerId? This cannot be undone.",
                    confirmLabel: "Delete")) {
                  final res = await _admin.deleteOfficer(officerId);
                  if (!mounted) return;
                  _snack(context, res.ok ? "Deleted." : res.message, ok: res.ok);
                  if (res.ok) _load();
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _resetPassword(String officerId) async {
    final ctrl = TextEditingController();
    final newPass = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reset password", style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: "New password (min 6 chars)",
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: _muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text("Reset", style: TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (newPass == null || newPass.isEmpty) return;
    if (newPass.length < 6) {
      if (mounted) _snack(context, "Password must be at least 6 characters.");
      return;
    }
    final res = await _admin.resetPassword(officerId, newPass);
    if (!mounted) return;
    _snack(context, res.ok ? "Password reset for $officerId." : res.message,
        ok: res.ok);
  }
}

// --------------------------------------------------------------------------
// APPROVALS
// --------------------------------------------------------------------------

class _ApprovalsTab extends StatefulWidget {
  const _ApprovalsTab();
  @override
  State<_ApprovalsTab> createState() => _ApprovalsTabState();
}

class _ApprovalsTabState extends State<_ApprovalsTab> {
  final _admin = AdminService();
  List<Map<String, dynamic>> _pending = [];
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
    final res = await _admin.listOfficers();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _pending =
            (res.data ?? []).where((o) => o['is_active'] != true).toList();
      } else {
        _error = res.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _olive));
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _pending.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Icon(Icons.inbox_outlined, size: 40, color: _muted),
                SizedBox(height: 8),
                Center(
                    child: Text("No officers awaiting approval",
                        style: TextStyle(color: _muted))),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: _pending.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final o = _pending[i];
                final officerId = _s(o['officer_id']);
                return Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_s(o['full_name']),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                            "$officerId  ·  ${_s(o['department'])}\n${_s(o['email'])}",
                            style: const TextStyle(fontSize: 12, color: _muted)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: _green,
                                    foregroundColor: Colors.white,
                                    elevation: 0),
                                icon: const Icon(Icons.check, size: 18),
                                label: const Text("Approve"),
                                onPressed: () async {
                                  final res = await _admin.setOfficerActive(
                                      officerId, true);
                                  if (!mounted) return;
                                  _snack(context,
                                      res.ok ? "$officerId approved." : res.message,
                                      ok: res.ok);
                                  if (res.ok) _load();
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: _red,
                                    side: const BorderSide(color: _red)),
                                icon: const Icon(Icons.close, size: 18),
                                label: const Text("Reject"),
                                onPressed: () async {
                                  if (await _confirm(
                                      context,
                                      "Reject registration",
                                      "Delete $officerId? They'll need to be re-added.",
                                      confirmLabel: "Reject")) {
                                    final res =
                                        await _admin.deleteOfficer(officerId);
                                    if (!mounted) return;
                                    _snack(context,
                                        res.ok ? "$officerId rejected." : res.message,
                                        ok: res.ok);
                                    if (res.ok) _load();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// --------------------------------------------------------------------------
// ATTENDANCE
// --------------------------------------------------------------------------

class _AttendanceTab extends StatefulWidget {
  const _AttendanceTab();
  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> {
  final _admin = AdminService();
  final _officerCtrl = TextEditingController();
  final _dateCtrl = TextEditingController(); // yyyy-mm-dd

  int _todayCount = 0;
  int _openCount = 0;
  final List<Map<String, dynamic>> _rows = [];
  static const int _pageSize = 50;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _officerCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows.clear();
      _hasMore = true;
    });

    // today stats (best-effort — doesn't block the list)
    _admin.todayAttendance().then((res) {
      if (!mounted || !res.ok) return;
      final data = res.data ?? [];
      setState(() {
        _todayCount = data.length;
        _openCount = data.where((r) => r['is_open'] == true).length;
      });
    });

    final res = await _admin.allAttendance(
      officerId: _officerCtrl.text.trim(),
      date: _dateCtrl.text.trim(),
      limit: _pageSize,
      offset: 0,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        final data = res.data ?? [];
        _rows.addAll(data);
        _hasMore = data.length == _pageSize;
      } else {
        _error = res.message;
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final res = await _admin.allAttendance(
      officerId: _officerCtrl.text.trim(),
      date: _dateCtrl.text.trim(),
      limit: _pageSize,
      offset: _rows.length,
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.ok) {
        final data = res.data ?? [];
        _rows.addAll(data);
        _hasMore = data.length == _pageSize;
      } else {
        _snack(context, res.message);
      }
    });
  }

  String _time(dynamic iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      return "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return iso.toString();
    }
  }

  String _dur(dynamic m) {
    final mins = m is num ? m.round() : int.tryParse('$m');
    if (mins == null) return '';
    return "${mins ~/ 60}h ${mins % 60}m";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // filters
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _officerCtrl,
                  onSubmitted: (_) => _refresh(),
                  decoration: _filterDecoration("Officer ID (optional)"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _dateCtrl,
                  onSubmitted: (_) => _refresh(),
                  keyboardType: TextInputType.datetime,
                  decoration: _filterDecoration("YYYY-MM-DD"),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: _olive),
                onPressed: _refresh,
                icon: const Icon(Icons.search, size: 20),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              _Stat(label: "Records today", value: "$_todayCount"),
              const SizedBox(width: 10),
              _Stat(label: "Still clocked in", value: "$_openCount", color: _green),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _olive))
              : _error != null
                  ? _ErrorState(message: _error!, onRetry: _refresh)
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: _rows.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 120),
                              Center(
                                  child: Text("No attendance records",
                                      style: TextStyle(color: _muted))),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                              itemCount: _rows.length + (_hasMore ? 1 : 0),
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                if (i == _rows.length) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: _loadingMore
                                          ? const CircularProgressIndicator(
                                              color: _olive)
                                          : OutlinedButton(
                                              onPressed: _loadMore,
                                              child: const Text("Load more")),
                                    ),
                                  );
                                }
                                return _row(_rows[i]);
                              },
                            ),
                    ),
        ),
      ],
    );
  }

  InputDecoration _filterDecoration(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  Widget _row(Map<String, dynamic> r) {
    final open = r['is_open'] == true || r['check_out_time'] == null;
    final name = _s(r['full_name']).isEmpty ? _s(r['officer_id']) : _s(r['full_name']);
    final id = _s(r['id']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  "${_s(r['date'])}   ·   in ${_time(r['check_in_time'])}   ·   out ${_time(r['check_out_time'])}"
                  "${_dur(r['duration_minutes']).isEmpty ? '' : '   ·   ${_dur(r['duration_minutes'])}'}",
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
          _Chip(text: open ? "Open" : "Closed", color: open ? _green : _muted),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'out') {
                final res = await _admin.forceClockOut(id);
                if (!mounted) return;
                _snack(context, res.ok ? "Clocked out." : res.message, ok: res.ok);
                if (res.ok) _refresh();
              } else if (v == 'del') {
                if (await _confirm(context, "Delete record",
                    "Delete ${_s(r['officer_id'])}'s row for ${_s(r['date'])}?",
                    confirmLabel: "Delete")) {
                  final res = await _admin.deleteAttendance(id);
                  if (!mounted) return;
                  _snack(context, res.ok ? "Deleted." : res.message, ok: res.ok);
                  if (res.ok) _refresh();
                }
              }
            },
            itemBuilder: (_) => [
              if (open)
                const PopupMenuItem(value: 'out', child: Text("Force clock-out")),
              const PopupMenuItem(value: 'del', child: Text("Delete record")),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// officer create / edit dialog
// --------------------------------------------------------------------------

class _OfficerFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _OfficerFormDialog({this.existing});

  @override
  State<_OfficerFormDialog> createState() => _OfficerFormDialogState();
}

class _OfficerFormDialogState extends State<_OfficerFormDialog> {
  final _admin = AdminService();
  final _form = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _dept;
  late final TextEditingController _pos;
  late final TextEditingController _phone;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? const {};
    _id = TextEditingController(text: _s(e['officer_id']));
    _name = TextEditingController(text: _s(e['full_name']));
    _email = TextEditingController(text: _s(e['email']));
    _dept = TextEditingController(text: _s(e['department']));
    _pos = TextEditingController(text: _s(e['position']));
    _phone = TextEditingController(text: _s(e['phone_number']));
  }

  @override
  void dispose() {
    for (final c in [_id, _name, _email, _dept, _pos, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final res = _isEdit
        ? await _admin.updateOfficer(
            officerId: _id.text.trim(),
            fullName: _name.text.trim(),
            email: _email.text.trim(),
            department: _dept.text.trim(),
            position: _pos.text.trim(),
            phoneNumber: _phone.text.trim(),
          )
        : await _admin.createOfficer(
            officerId: _id.text.trim(),
            fullName: _name.text.trim(),
            email: _email.text.trim(),
            department: _dept.text.trim(),
            position: _pos.text.trim(),
            phoneNumber: _phone.text.trim(),
          );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.pop(context, true);
      _snack(context, _isEdit ? "Officer updated." : "Officer created.", ok: true);
    } else {
      _snack(context, res.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? "Edit officer" : "New officer",
          style: const TextStyle(fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_id, "Officer ID", enabled: !_isEdit, required: true),
              _field(_name, "Full name", required: true),
              _field(_email, "Email", required: true, keyboard: TextInputType.emailAddress),
              _field(_dept, "Department"),
              _field(_pos, "Position"),
              _field(_phone, "Phone number", keyboard: TextInputType.phone),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: _muted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: _olive, foregroundColor: Colors.white, elevation: 0),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_isEdit ? "Save" : "Create"),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool enabled = true,
      bool required = false,
      TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: c,
        enabled: enabled,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, isDense: true),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? "Required" : null
            : null,
      ),
    );
  }
}

// --------------------------------------------------------------------------
// small widgets
// --------------------------------------------------------------------------

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Stat({required this.label, required this.value, this.color = _olive});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11.5, color: _muted)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.error_outline, color: _red, size: 40),
        const SizedBox(height: 10),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted)),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: OutlinedButton(onPressed: onRetry, child: const Text("Retry")),
        ),
      ],
    );
  }
}
