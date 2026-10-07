// ADMIN HOME — officer management, registration approvals, password
// resets and attendance oversight. Reachable from the drawer only when
// AuthService.isAdmin() is true (role-gated, same login).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gis_attendance/services/admin_service.dart';
import 'package:gis_attendance/services/notification_service.dart';
import 'package:gis_attendance/services/permissions.dart';
import 'package:gis_attendance/screens/admin/roster_report_screen.dart';
import 'package:gis_attendance/screens/admin/broadcast_screen.dart';
import 'package:gis_attendance/screens/admin/geofence_screen.dart';
import 'package:gis_attendance/theme/gis_palette.dart';

const _dark = Color(0xFF142412);
const _gold = Color(0xFFE1B12C);
const _red = Color(0xFFD63031);
const _green = Color(0xFF2ED573);
const _purple = Color(0xFF6C5CE7);

class AdminHomeScreen extends StatelessWidget {
  /// Which tab to open first (used by the dashboard roster shortcut,
  /// which deep-links to the Reports tab).
  final int initialTab;
  const AdminHomeScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: GisPalette.of(context).bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(6, 10, 16, 0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [GisPalette.of(context).primary, _dark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.maybePop(context),
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                                size: 19),
                          ),
                        ),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Administration",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 19,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "Officers · attendance · broadcasts",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings_rounded,
                            color: _dark,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const TabBar(
                      isScrollable: true,
                      indicatorColor: _gold,
                      indicatorWeight: 3,
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      labelStyle: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5),
                      unselectedLabelColor: Colors.white60,
                      unselectedLabelStyle: TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13.5),
                      labelPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      tabs: [
                        Tab(text: "Officers"),
                        Tab(text: "Approvals"),
                        Tab(text: "Attendance"),
                        Tab(text: "Live"),
                        Tab(text: "Reports"),
                        Tab(text: "Broadcast"),
                        Tab(text: "Geo-fence"),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _OfficersTab(),
                    _ApprovalsTab(),
                    _AttendanceTab(),
                    _LiveTab(),
                    RosterReportScreen(),
                    BroadcastScreen(),
                    GeoFenceScreen(),
                  ],
                ),
              ),
            ],
          ),
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
            child: Text("Cancel", style: TextStyle(color: GisPalette.of(context).muted))),
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
      backgroundColor: GisPalette.of(context).bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: GisPalette.of(context).primary,
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
                  ? Center(child: CircularProgressIndicator(color: GisPalette.of(context).primary))
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : _filtered.isEmpty
                          ? Center(
                              child: Text("No officers found",
                                  style: TextStyle(color: GisPalette.of(context).muted)))
                          : GridView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                  14, 6, 14, 90),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 380,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                mainAxisExtent: 92,
                              ),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) =>
                                  _officerCard(_filtered[i]),
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _officerCard(Map<String, dynamic> o) {
    final active = o['is_active'] == true;
    final role = _s(o['role']).toLowerCase();
    final roleLabel =
        role == 'super_admin' ? "SUPER" : role == 'admin' ? "ADMIN" : null;
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
                backgroundColor: GisPalette.of(context).primary.withValues(alpha: 0.12),
                child: Text(
                  (_s(o['full_name']).isNotEmpty ? _s(o['full_name'])[0] : '?')
                      .toUpperCase(),
                  style: TextStyle(color: GisPalette.of(context).primary, fontWeight: FontWeight.bold),
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
                        if (roleLabel != null) ...[
                          const SizedBox(width: 6),
                          _Chip(
                              text: roleLabel,
                              color: role == 'super_admin'
                                  ? _purple
                                  : _gold),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text("${_s(o['officer_id'])}  ·  ${_s(o['department'])}",
                        style: TextStyle(fontSize: 12, color: GisPalette.of(context).muted)),
                  ],
                ),
              ),
              _Chip(
                text: active ? "Active" : "Inactive",
                color: active ? _green : GisPalette.of(context).muted,
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
            Text(officerId, style: TextStyle(color: GisPalette.of(context).muted, fontSize: 12)),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: GisPalette.of(context).primary),
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
              leading: Icon(Icons.password_outlined, color: GisPalette.of(context).primary),
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
              child: Text("Cancel", style: TextStyle(color: GisPalette.of(context).muted))),
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
      return Center(child: CircularProgressIndicator(color: GisPalette.of(context).primary));
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _pending.isEmpty
          ? ListView(
              children: [
                SizedBox(height: 120),
                Icon(Icons.inbox_outlined, size: 40, color: GisPalette.of(context).muted),
                SizedBox(height: 8),
                Center(
                    child: Text("No officers awaiting approval",
                        style: TextStyle(color: GisPalette.of(context).muted))),
              ],
            )
          : GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(14),
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 400,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 216,
              ),
              itemCount: _pending.length,
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
                            style: TextStyle(fontSize: 12, color: GisPalette.of(context).muted)),
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
                  readOnly: true,
                  onTap: () => _pickDate(_dateCtrl),
                  decoration: InputDecoration(
                    hintText: "Pick a date",
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    suffixIcon: _dateCtrl.text.trim().isEmpty
                        ? IconButton(
                            icon: Icon(
                                Icons.calendar_month_outlined,
                                size: 19,
                                color: GisPalette.of(context).primary),
                            onPressed: () => _pickDate(_dateCtrl),
                          )
                        : IconButton(
                            icon: Icon(Icons.clear_rounded,
                                size: 19, color: GisPalette.of(context).muted),
                            onPressed: () {
                              setState(() => _dateCtrl.clear());
                              _refresh();
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: GisPalette.of(context).primary),
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
              ? Center(child: CircularProgressIndicator(color: GisPalette.of(context).primary))
              : _error != null
                  ? _ErrorState(message: _error!, onRetry: _refresh)
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: _rows.isEmpty
                          ? ListView(children: [
                              SizedBox(height: 120),
                              Center(
                                  child: Text("No attendance records",
                                      style: TextStyle(color: GisPalette.of(context).muted))),
                            ])
                          : GridView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                  14, 4, 14, 24),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 440,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                mainAxisExtent: 96,
                              ),
                              itemCount:
                                  _rows.length + (_hasMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i == _rows.length) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: _loadingMore
                                          ? CircularProgressIndicator(
                                              color: GisPalette.of(context).primary)
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
          colorScheme: ColorScheme.light(
            primary: GisPalette.of(context).primary,
            onPrimary: Colors.white,
            onSurface: _dark,
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
      _refresh();
    }
  }

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
                  style: TextStyle(fontSize: 12, color: GisPalette.of(context).muted),
                ),
              ],
            ),
          ),
          _Chip(text: open ? "Open" : "Closed", color: open ? _green : GisPalette.of(context).muted),
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
// LIVE — who's clocked in right now, auto-refreshed. Visible to admins
// and super admins (the whole admin surface is role-gated).
// --------------------------------------------------------------------------

class _LiveTab extends StatefulWidget {
  const _LiveTab();
  @override
  State<_LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<_LiveTab> {
  final _admin = AdminService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  DateTime _updatedAt = DateTime.now();
  Timer? _timer;

  static const Duration _pollEvery = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_pollEvery, (_) {
      if (mounted) _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _isOpen(Map<String, dynamic> r) =>
      r['is_open'] == true || r['check_out_time'] == null;

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final res = await _admin.todayAttendance();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _updatedAt = DateTime.now();
      if (res.ok) {
        _rows = res.data ?? [];
        _rows.sort((a, b) {
          final ao = _isOpen(a) ? 0 : 1;
          final bo = _isOpen(b) ? 0 : 1;
          if (ao != bo) return ao.compareTo(bo);
          return _s(b['check_in_time'])
              .compareTo(_s(a['check_in_time']));
        });
        _error = null;
      } else if (_rows.isEmpty) {
        _error = res.message;
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

  String _clocked(DateTime t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}";

  /// "2h 15m so far" for an open shift counting from check-in.
  String _elapsed(dynamic iso) {
    if (iso == null) return '';
    try {
      final mins =
          DateTime.now().difference(DateTime.parse(iso.toString())).inMinutes;
      if (mins < 0) return '';
      if (mins < 60) return '${mins}m so far';
      return '${mins ~/ 60}h ${mins % 60}m so far';
    } catch (_) {
      return '';
    }
  }

  Widget _liveCard(Map<String, dynamic> r) {
    final open = _isOpen(r);
    final id = _s(r['id']);
    final name = _s(r['full_name']).isEmpty
        ? _s(r['officer_id'])
        : _s(r['full_name']);
    final sub = open
        ? "In ${_time(r['check_in_time'])}${_elapsed(r['check_in_time']).isEmpty ? '' : '   ·   ${_elapsed(r['check_in_time'])}'}"
        : "In ${_time(r['check_in_time'])}   ·   out ${_time(r['check_out_time'])}";
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: open
            ? Border.all(
                color: _green.withValues(alpha: 0.5), width: 1.2)
            : null,
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                backgroundColor: GisPalette.of(context).primary.withValues(alpha: 0.12),
                child: Text(
                  (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                  style: TextStyle(
                      color: GisPalette.of(context).primary, fontWeight: FontWeight.bold),
                ),
              ),
              if (open)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  "${_s(r['officer_id'])}   ·   $sub",
                  style:
                      TextStyle(fontSize: 12, color: GisPalette.of(context).muted),
                ),
              ],
            ),
          ),
          _Chip(
              text: open ? "In now" : "Out",
              color: open ? _green : GisPalette.of(context).muted),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,
                size: 19, color: GisPalette.of(context).muted),
            onSelected: (v) async {
              if (v == 'out') {
                final res = await _admin.forceClockOut(id);
                if (!mounted) return;
                _snack(context,
                    res.ok ? "Clocked out." : res.message, ok: res.ok);
                if (res.ok) _refresh();
              } else if (v == 'del') {
                if (await _confirm(
                    context,
                    "Delete record",
                    "Delete ${_s(r['officer_id'])}'s row for ${_s(r['date'])}?",
                    confirmLabel: "Delete")) {
                  final res = await _admin.deleteAttendance(id);
                  if (!mounted) return;
                  _snack(context,
                      res.ok ? "Deleted." : res.message, ok: res.ok);
                  if (res.ok) _refresh();
                }
              }
            },
            itemBuilder: (_) => [
              if (open)
                const PopupMenuItem(
                    value: 'out', child: Text("Force clock-out")),
              const PopupMenuItem(
                  value: 'del', child: Text("Delete record")),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _liveGrid(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return const [];
    return [
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate:
            const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 440,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 100,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _liveCard(items[i]),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final open = _rows.where(_isOpen).toList();
    final closed = _rows.where((r) => !_isOpen(r)).toList();
    return Column(
      children: [
        // live banner
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [GisPalette.of(context).primary, _dark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fiber_manual_record_rounded,
                          size: 10, color: Colors.white),
                      SizedBox(width: 4),
                      Text("LIVE",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Updated ${_clocked(_updatedAt)}  ·  auto-refresh 30s",
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11.5),
                  ),
                ),
                InkWell(
                  onTap: () => _refresh(),
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color:
                          Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.refresh_rounded,
                        size: 17, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              _Stat(
                  label: "Clocked in now",
                  value: "${open.length}",
                  color: _green),
              const SizedBox(width: 10),
              _Stat(
                  label: "Clocked out",
                  value: "${closed.length}"),
              const SizedBox(width: 10),
              _Stat(label: "Total today", value: "${_rows.length}"),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(color: GisPalette.of(context).primary))
              : _error != null && _rows.isEmpty
                  ? _ErrorState(message: _error!, onRetry: _refresh)
                  : RefreshIndicator(
                      onRefresh: () => _refresh(),
                      child: _rows.isEmpty
                          ? ListView(children: [
                              SizedBox(height: 100),
                              Icon(Icons.radar_rounded,
                                  size: 40, color: GisPalette.of(context).muted),
                              SizedBox(height: 8),
                              Center(
                                  child: Text(
                                      "No clock-ins recorded today",
                                      style:
                                          TextStyle(color: GisPalette.of(context).muted))),
                            ])
                          : ListView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                  14, 4, 14, 24),
                              children: [
                                _LiveSectionLabel(
                                    "Clocked in now (${open.length})"),
                                const SizedBox(height: 8),
                                if (open.isEmpty)
                                  const _LiveEmptyNote(
                                      "Nobody is clocked in right now."),
                                ..._liveGrid(open),
                                const SizedBox(height: 14),
                                _LiveSectionLabel(
                                    "Clocked out (${closed.length})"),
                                const SizedBox(height: 8),
                                if (closed.isEmpty)
                                  const _LiveEmptyNote(
                                      "No clock-outs recorded yet."),
                                ..._liveGrid(closed),
                              ],
                            ),
                    ),
        ),
      ],
    );
  }
}

class _LiveSectionLabel extends StatelessWidget {
  final String text;
  const _LiveSectionLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: GisPalette.of(context).muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _LiveEmptyNote extends StatelessWidget {
  final String text;
  const _LiveEmptyNote(this.text);
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: GisPalette.of(context).muted)),
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
  String _role = AppRoles.officer;
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
    final r = _s(e['role']).toLowerCase();
    _role = AppRoles.all.contains(r) ? r : AppRoles.officer;
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
    String? roleError;
    if (res.ok) {
      final hadRole = _isEdit
          ? _s(widget.existing!['role']).toLowerCase()
          : AppRoles.officer;
      final wantRole =
          AppRoles.all.contains(_role) ? _role : AppRoles.officer;
      if (wantRole != (AppRoles.all.contains(hadRole) ? hadRole : AppRoles.officer)) {
        final roleRes =
            await _admin.setOfficerRole(_id.text.trim(), wantRole);
        if (roleRes.ok) {
          NotificationService.logActivity(
            'Role updated',
            '${_id.text.trim()} is now ${AppRoles.label(wantRole)}.',
            category: 'System',
          );
        } else {
          roleError = roleRes.message;
        }
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok && roleError == null) {
      Navigator.pop(context, true);
      _snack(context, _isEdit ? "Officer updated." : "Officer created.", ok: true);
    } else if (res.ok) {
      final officerId = _id.text.trim();
      final attemptedRole =
          AppRoles.all.contains(_role) ? _role : AppRoles.officer;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Saved, but the role was not applied: $roleError"),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'COPY SQL FIX',
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: "-- Promote an officer when the API rejects `role` updates.\n"
                      "-- Run in Supabase SQL Editor, then have them sign out and back in.\n"
                      "UPDATE public.officers SET role = '$attemptedRole', updated_at = NOW() WHERE officer_id = '$officerId';"));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'SQL copied — run it in Supabase SQL Editor, then the officer signs out and back in.')),
              );
            },
          ),
        ),
      );
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
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                      labelText: "Role", isDense: true),
                  items: AppRoles.all
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(AppRoles.label(r)),
                          ))
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (v) => setState(
                          () => _role = v ?? AppRoles.officer),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: GisPalette.of(context).muted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: GisPalette.of(context).primary, foregroundColor: Colors.white, elevation: 0),
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

  /// Bright brand colors are unreadable as small text on light tints,
  /// so map them to darker ink variants for the label.
  Color get _textColor {
    if (color == _gold) return const Color(0xFF7A5F00);
    if (color == _green) return const Color(0xFF14663A);
    if (color == _red) return const Color(0xFF9E2B2B);
    return color;
  }

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
              color: _textColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Stat({required this.label, required this.value, this.color});

  Color _valueColor(BuildContext context) {
    final c = color ?? GisPalette.of(context).primary;
    return c == _green ? const Color(0xFF14663A) : c;
  }

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
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _valueColor(context))),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11.5, color: GisPalette.of(context).muted)),
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
                style: TextStyle(color: GisPalette.of(context).muted)),
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
