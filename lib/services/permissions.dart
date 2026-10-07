/// Roles, hierarchy and the client-side permission matrix.
///
/// Server truth lives on the officer record (`role` is 'officer', 'admin'
/// or 'super_admin'); this matrix decides which *screens and actions* the
/// app shows for each role. API endpoints enforce their own server-side
/// checks on top.
abstract class AppRoles {
  static const String officer = 'officer';
  static const String admin = 'admin';
  static const String superAdmin = 'super_admin';

  static const List<String> all = [officer, admin, superAdmin];

  static String label(String role) {
    switch (role.toLowerCase()) {
      case admin:
        return 'Admin';
      case superAdmin:
        return 'Super admin';
      default:
        return 'Officer';
    }
  }

  /// Higher number = higher rank. Used for guards like "at least admin".
  static int rank(String? role) {
    switch ((role ?? officer).toLowerCase()) {
      case superAdmin:
        return 3;
      case admin:
        return 2;
      default:
        return 1;
    }
  }
}

/// Permission keys used across the app for UI gating.
abstract class AppPermissions {
  /// Sign in, clock in/out, view own dashboard & history.
  static const String clock = 'attendance.clock';

  /// Enter the admin surface (officer/approval/attendance tabs).
  static const String adminAccess = 'admin.access';

  /// Send broadcasts.
  static const String broadcast = 'broadcast.send';

  /// Create / edit / activate / reset-password / delete officers.
  static const String officersManage = 'officers.manage';

  /// Duty-roster PDF generation & sharing (super-admin only).
  static const String rosterPdf = 'roster.pdf';

  /// Change officer roles (admins can bootstrap; super admins always can).
  static const String rolesManage = 'roles.manage';

  /// SMTP / SMS / attendance-window system configuration.
  static const String systemConfig = 'system.config';
}

/// Which permissions each role holds on this device. Admins and super
/// admins hold the full set (including the duty-roster PDF); officers
/// hold the basics.
abstract class RolePermissions {
  static const Map<String, Set<String>> matrix = {
    AppRoles.officer: {
      AppPermissions.clock,
    },
    AppRoles.admin: {
      AppPermissions.clock,
      AppPermissions.adminAccess,
      AppPermissions.broadcast,
      AppPermissions.officersManage,
      AppPermissions.rolesManage,
      AppPermissions.systemConfig,
      AppPermissions.rosterPdf,
    },
    AppRoles.superAdmin: {
      AppPermissions.clock,
      AppPermissions.adminAccess,
      AppPermissions.broadcast,
      AppPermissions.officersManage,
      AppPermissions.rolesManage,
      AppPermissions.systemConfig,
      AppPermissions.rosterPdf,
    },
  };

  /// All permission keys, in display order.
  static const List<String> permissions = [
    AppPermissions.clock,
    AppPermissions.adminAccess,
    AppPermissions.broadcast,
    AppPermissions.officersManage,
    AppPermissions.rolesManage,
    AppPermissions.systemConfig,
    AppPermissions.rosterPdf,
  ];

  static String permissionLabel(String permission) {
    switch (permission) {
      case AppPermissions.clock:
        return 'Sign in & clock in/out';
      case AppPermissions.adminAccess:
        return 'Open admin surface';
      case AppPermissions.broadcast:
        return 'Send broadcasts';
      case AppPermissions.officersManage:
        return 'Manage officers';
      case AppPermissions.rolesManage:
        return 'Manage roles';
      case AppPermissions.systemConfig:
        return 'System configuration';
      case AppPermissions.rosterPdf:
        return 'Duty-roster PDF';
      default:
        return permission;
    }
  }

  static bool can(String? role, String permission) {
    final key = (role ?? AppRoles.officer).toLowerCase();
    return matrix[key]?.contains(permission) ?? false;
  }

  static bool atLeastAdmin(String? role) =>
      AppRoles.rank(role) >= AppRoles.rank(AppRoles.admin);
}
