// ROLES & PERMISSIONS — who is an officer / admin / super_admin and what
// each role may do. Role changes are written to the server with
// PATCH /officers (best-effort: the call reports the server message when
// the backend rejects it). Reachable from the dashboard drawer for
// admins and super admins.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gis_attendance/services/admin_service.dart';
import 'package:gis_attendance/services/auth_service.dart';
import 'package:gis_attendance/services/notification_service.dart';
import 'package:gis_attendance/services/permissions.dart';

class RolesPermissionsScreen extends StatefulWidget {
  const RolesPermissionsScreen({super.key});
  @override
  State<RolesPermissionsScreen> createState() =>
      _RolesPermissionsScreenState();
}

class _RolesPermissionsScreenState extends State<RolesPermissionsScreen> {
  static const olive = Color(0xFF2E4D2A);
  static const dark = Color(0xFF142412);
  static const bg = Color(0xFFF5F6F5);
  static const muted = Color(0xFF6E7A6C);
  static const hairline = Color(0xFFE7E9E4);
  static const danger = Color(0xFFD63031);
  static const purple = Color(0xFF6C5CE7);
  static const purpleTint = Color(0xFFEDEBFF);
  static const goldTint = Color(0xFFFBF1D8);
  static const oliveTint = Color(0xFFE3EAE1);
  static const darkAmber = Color(0xFF7A5F00);

  final _admin = AdminService();
  final _auth = AuthService();
  final _searchCtrl = TextEditingController();

  bool _checkingAccess = true;
  bool _allowed = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _query = '';
  List<Map<String, dynamic>> _officers = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final allowed = await _auth.isAdminOrSuper();
    if (!mounted) return;
    setState(() {
      _allowed = allowed;
      _checkingAccess = false;
    });
    if (allowed) await _load();
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
        _officers = res.data ?? [];
      } else {
        _error = res.message;
      }
    });
  }

  String _roleOf(Map<String, dynamic> o) =>
      (o['role']?.toString() ?? AppRoles.officer).toLowerCase();

  String _nameOf(Map<String, dynamic> o) {
    final v = (o['full_name'] ?? o['fullName'] ?? o['email'] ?? '—').toString();
    return v.isEmpty ? '—' : v;
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? _officers
        : _officers.where((o) {
            return _roleOf(o).contains(q) ||
                _nameOf(o).toLowerCase().contains(q) ||
                (o['officer_id']?.toString() ?? '')
                    .toLowerCase()
                    .contains(q) ||
                (o['department']?.toString() ?? '')
                    .toLowerCase()
                    .contains(q);
          }).toList();
    list.sort((a, b) =>
        AppRoles.rank(_roleOf(b)).compareTo(AppRoles.rank(_roleOf(a))));
    return list;
  }

  Color _roleColor(String role) {
    switch (role) {
      case AppRoles.superAdmin:
        return purple;
      case AppRoles.admin:
        return darkAmber;
      default:
        return olive;
    }
  }

  Color _roleTint(String role) {
    switch (role) {
      case AppRoles.superAdmin:
        return purpleTint;
      case AppRoles.admin:
        return goldTint;
      default:
        return oliveTint;
    }
  }

  /// SQL the backend operator runs when the API rejects every `role`
  /// update route (the checked-in schema has no role handling on writes).
  /// The officer must sign out and back in afterwards to pick up the role.
  static String roleSqlFix(String officerId, String role) =>
      "-- Promote an officer when the API rejects `role` updates.\n"
      "-- Run in Supabase SQL Editor, then have them sign out and back in.\n"
      "UPDATE public.officers SET role = '$role', updated_at = NOW() WHERE officer_id = '$officerId';";

  void _showRoleFailure(String officerId, String role, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: danger,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'COPY SQL FIX',
          textColor: Colors.white,
          onPressed: () {
            Clipboard.setData(
                ClipboardData(text: roleSqlFix(officerId, role)));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'SQL copied — run it in Supabase SQL Editor, then the officer signs out and back in.')),
            );
          },
        ),
      ),
    );
  }

  Future<void> _changeRole(Map<String, dynamic> o, String role) async {
    final officerId = (o['officer_id'] ?? '').toString();
    if (officerId.isEmpty || _roleOf(o) == role) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Change role',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
          role == AppRoles.superAdmin
              ? '$officerId will become a SUPER ADMIN with full access (including the duty-roster PDF). Continue?'
              : 'Set $officerId to "${AppRoles.label(role)}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: olive,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    final res = await _admin.setOfficerRole(officerId, role);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      NotificationService.logActivity(
        'Role updated',
        '$officerId is now ${AppRoles.label(role)}.',
        category: 'System',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$officerId → ${AppRoles.label(role)}'),
            backgroundColor: olive),
      );
      await _load();
    } else {
      _showRoleFailure(officerId, role, res.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: dark,
        iconTheme: const IconThemeData(color: olive),
        elevation: 0,
        title: const Text('Roles & Permissions',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: dark)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: hairline),
        ),
      ),
      body: _checkingAccess
          ? const Center(child: CircularProgressIndicator(color: olive))
          : !_allowed
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Only admins and super admins can manage roles.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: dark,
                          height: 1.5),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: olive,
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 860),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildStats(),
                            const SizedBox(height: 14),
                            _buildMatrix(),
                            const SizedBox(height: 14),
                            _buildOfficers(),
                            if (_saving) ...[
                              const SizedBox(height: 12),
                              const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: olive)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _card(Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: hairline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildStats() {
    var supers = 0, admins = 0, officers = 0;
    for (final o in _officers) {
      switch (_roleOf(o)) {
        case AppRoles.superAdmin:
          supers++;
          break;
        case AppRoles.admin:
          admins++;
          break;
        default:
          officers++;
      }
    }
    return Row(
      children: [
        Expanded(
            child: _stat('$supers', 'Super admins', purple,
                Icons.verified_user_outlined)),
        const SizedBox(width: 10),
        Expanded(
            child: _stat('$admins', 'Admins', darkAmber,
                Icons.admin_panel_settings_outlined)),
        const SizedBox(width: 10),
        Expanded(
            child: _stat('$officers', 'Officers', olive,
                Icons.badge_outlined)),
      ],
    );
  }

  Widget _stat(String value, String label, Color color, IconData icon) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color)),
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: muted)),
        ],
      ),
    );
  }

  Widget _buildMatrix() {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What each role can do',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: dark)),
          const SizedBox(height: 2),
          const Text(
            'Enforced in the app for menus and shortcuts; the API enforces its own checks too.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(flex: 4, child: SizedBox()),
              _MatrixHead('Officer'),
              _MatrixHead('Admin'),
              _MatrixHead('Super'),
            ],
          ),
          const Divider(height: 12, color: hairline),
          ...RolePermissions.permissions.map((p) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        RolePermissions.permissionLabel(p),
                        style: const TextStyle(
                            fontSize: 12.5, color: dark),
                      ),
                    ),
                    _MatrixCell(
                        allowed: RolePermissions.can(
                            AppRoles.officer, p)),
                    _MatrixCell(
                        allowed: RolePermissions.can(
                            AppRoles.admin, p)),
                    _MatrixCell(
                        allowed: RolePermissions.can(
                            AppRoles.superAdmin, p)),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: goldTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Admins and super admins hold all permissions, including the duty-roster PDF. Role changes try PATCH, then PUT, then PATCH-by-id — if the server rejects all three, role updates must be enabled backend-side.',
              style: TextStyle(
                  fontSize: 12.5,
                  color: darkAmber,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfficers() {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Officers',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: dark)),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search name, ID, department, role',
              prefixIcon:
                  const Icon(Icons.search_rounded, color: muted),
              filled: true,
              fillColor: bg,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Center(
                child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: olive),
            ))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                      child: Text(_error!,
                          style:
                              const TextStyle(color: danger, fontSize: 13))),
                  TextButton(
                      onPressed: _load,
                      child: const Text('Retry')),
                ],
              ),
            )
          else if (_filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('No officers found',
                      style: TextStyle(color: muted))),
            )
          else
            ..._filtered.map((o) {
              final role = _roleOf(o);
              final name = _nameOf(o);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 19,
                        backgroundColor:
                            _roleTint(role),
                        child: Text(
                          name.isEmpty
                              ? '?'
                              : name[0].toUpperCase(),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _roleColor(role)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: dark)),
                            Text(
                              '${o['officer_id'] ?? '—'}  ·  ${o['department'] ?? '—'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: muted),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: _roleTint(role),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          AppRoles.label(role),
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: _roleColor(role)),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded,
                            size: 19, color: muted),
                        onSelected: (r) => _changeRole(o, r),
                        itemBuilder: (_) => AppRoles.all
                            .map((r) => PopupMenuItem(
                                  value: r,
                                  child: Row(
                                    children: [
                                      if (r == role)
                                        const Icon(Icons.check_rounded,
                                            size: 16, color: olive),
                                      if (r == role)
                                        const SizedBox(width: 6),
                                      Text(
                                          'Make ${AppRoles.label(r)}'),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _MatrixHead extends StatelessWidget {
  final String text;
  const _MatrixHead(this.text);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6E7A6C)),
      ),
    );
  }
}

class _MatrixCell extends StatelessWidget {
  final bool allowed;
  const _MatrixCell({required this.allowed});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Icon(
        allowed ? Icons.check_circle_rounded : Icons.remove_circle_outline,
        size: 19,
        color: allowed
            ? const Color(0xFF1FAA53)
            : Colors.grey.shade300,
      ),
    );
  }
}
