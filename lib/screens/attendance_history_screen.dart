import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gis_attendance/services/attendance_service.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final AttendanceService attendanceService;

  const AttendanceHistoryScreen({
    Key? key,
    required this.profile,
    required this.attendanceService,
  }) : super(key: key);

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  late AttendanceService _attendanceService;
  Map<String, dynamic>? _profile;

  List<Map<String, dynamic>> _history = [];
  bool _historyLoading = false;
  String? _openAttendanceId;

  late ScrollController _scrollController;

  // GIS Theme Colors
  static const Color gisDeepOlive = Color(0xFF2E4D2A);
  static const Color gisDarkBackground = Color(0xFF142412);
  static const Color ghanaGold = Color(0xFFE1B12C);
  static const Color nationalRed = Color(0xFFD63031);
  static const Color successGreen = Color(0xFF2ED573);
  static const Color darkCharcoal = Color(0xFF1A2519);

  @override
  void initState() {
    super.initState();
    _attendanceService = widget.attendanceService;
    _profile = widget.profile;
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadHistory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreHistory();
    }
  }

  Future<void> _loadHistory() async {
    // Attendance rows are keyed by the business officer_id, not
    // _profile['id'] (the officers table's internal uuid) — using the
    // uuid here would miss every face-based clock-in/out, which the
    // backend stores under the real officer_id (see checkFace()).
    final userId = _profile?["officerId"]?.toString() ??
        _profile?["username"]?.toString();
    if (userId == null) return;

    setState(() => _historyLoading = true);

    final items = await _attendanceService.getHistory(userId: userId);
    if (!mounted) return;

    setState(() {
      _history = items;
      _historyLoading = false;
    });

    _findOpenAttendance();
  }

  Future<void> _loadMoreHistory() async {
    if (_historyLoading) return;

    // Attendance rows are keyed by the business officer_id, not
    // _profile['id'] (the officers table's internal uuid) — using the
    // uuid here would miss every face-based clock-in/out, which the
    // backend stores under the real officer_id (see checkFace()).
    final userId = _profile?["officerId"]?.toString() ??
        _profile?["username"]?.toString();
    if (userId == null) return;

    setState(() => _historyLoading = true);

    final items = await _attendanceService.getHistory(userId: userId);
    if (!mounted) return;

    setState(() {
      _history.addAll(items);
      _historyLoading = false;
    });

    _findOpenAttendance();
  }

  // --- Field helpers -------------------------------------------------
  // Backend uses check_in_time / check_out_time / duration_minutes / status.
  // We fall back to older field names in case any endpoint still returns them.
  dynamic _clockIn(Map<String, dynamic> r) =>
      r['clock_in'] ??
      r['check_in_time'] ??
      r['clock_in_time'] ??
      r['clockIn'];

  dynamic _clockOut(Map<String, dynamic> r) =>
      r['clock_out'] ??
      r['check_out_time'] ??
      r['clock_out_time'] ??
      r['clockOut'];

  bool _recordIsOpen(Map<String, dynamic> r) {
    final status = r['status']?.toString().toLowerCase();
    if (status != null) return status != 'completed';
    // Fallback: no check-out time means the shift is still open.
    return _clockOut(r) == null;
  }

  void _findOpenAttendance() {
    final open = _history.firstWhere(
      (r) => _recordIsOpen(r) && _clockIn(r) != null,
      orElse: () => {},
    );

    if (open.isNotEmpty && open['id'] != null) {
      setState(() {
        _openAttendanceId = open['id'].toString();
      });
    } else {
      setState(() {
        _openAttendanceId = null;
      });
    }
  }

  String _formatTime(dynamic time) {
    if (time == null) return "N/A";
    if (time is String) {
      try {
        final dt = DateTime.parse(time).toLocal();
        return DateFormat('HH:mm:ss').format(dt);
      } catch (e) {
        return time.toString();
      }
    }
    return time.toString();
  }

  String _formatDate(dynamic dateOrTime) {
    if (dateOrTime == null) return "N/A";
    if (dateOrTime is String) {
      try {
        final dt = DateTime.parse(dateOrTime).toLocal();
        return DateFormat('EEE, MMM dd, yyyy').format(dt);
      } catch (e) {
        return dateOrTime.toString();
      }
    }
    return dateOrTime.toString();
  }

  /// Formats a duration given in MINUTES (backend field: duration_minutes).
  /// If duration_minutes is null but both timestamps exist, computes it
  /// from check_in_time/check_out_time instead.
  String _formatDuration(Map<String, dynamic> record) {
    num? minutes;

    final rawMinutes = record['duration_minutes'];
    if (rawMinutes != null) {
      minutes = num.tryParse(rawMinutes.toString());
    }

    if (minutes == null) {
      final inTime = _clockIn(record);
      final outTime = _clockOut(record);
      if (inTime is String && outTime is String) {
        try {
          final inDt = DateTime.parse(inTime);
          final outDt = DateTime.parse(outTime);
          minutes = outDt.difference(inDt).inMinutes;
        } catch (_) {
          minutes = null;
        }
      }
    }

    if (minutes == null) return "-";

    final totalMinutes = minutes.abs().round();
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return "$hours hrs $mins mins";
  }

  bool _isOpenRecord(Map<String, dynamic> record) {
    return record['id']?.toString() == _openAttendanceId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: gisDeepOlive.withValues(alpha: 0.93),
        foregroundColor: Colors.white,
        title: const Text(
          'Attendance History',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
            tooltip: 'Refresh Logs',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [gisDarkBackground, gisDeepOlive],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: _historyLoading && _history.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(ghanaGold),
                  ),
                )
              : _history.isEmpty
                  ? _buildEmptyState()
                  : _buildHistoryList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: ghanaGold.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.history_toggle_off_rounded,
                size: 64,
                color: ghanaGold,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Duty Records Found',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Your official deployment and shift logs will appear here. Pull down to refresh when new records arrive.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadHistory,
              style: ElevatedButton.styleFrom(
                backgroundColor: ghanaGold,
                foregroundColor: gisDarkBackground,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'REFRESH HISTORY',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    return RefreshIndicator(
      color: ghanaGold,
      backgroundColor: gisDeepOlive.withValues(alpha: 0.15),
      onRefresh: _loadHistory,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        itemCount: _history.length + (_historyLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _history.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(ghanaGold),
                ),
              ),
            );
          }

          final record = _history[index];
          final isOpen = _isOpenRecord(record);

          return _buildHistoryCard(record, isOpen);
        },
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> record, bool isOpen) {
    final clockInTime = _clockIn(record);
    final clockOutTime = _clockOut(record);
    // Prefer the explicit "date" field the backend sends; fall back to
    // deriving it from the check-in timestamp.
    final dateValue = record['date'] ?? clockInTime;
    final notes = record['notes']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      elevation: isOpen ? 6 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isOpen ? ghanaGold : Colors.white.withValues(alpha: 0.12),
          width: isOpen ? 2.2 : 1,
        ),
      ),
      color: isOpen ? Colors.white.withValues(alpha: 0.95) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Date and Status Accent
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_outlined,
                        color: gisDeepOlive,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(dateValue),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: darkCharcoal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isOpen)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: ghanaGold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ghanaGold.withValues(alpha: 0.8), width: 1.2),
                    ),
                    child: const Text(
                      'ONGOING DUTY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF9E7500),
                        letterSpacing: 0.6,
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: successGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'COMPLETED',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF208B3A),
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
            ),

            // Timings Area
            _buildTimeRow(
              label: 'Clock In (Duty Start)',
              time: _formatTime(clockInTime),
              icon: Icons.login_rounded,
              color: successGreen,
            ),
            const SizedBox(height: 16),
            _buildTimeRow(
              label: 'Clock Out (Duty End)',
              time: clockOutTime == null ? 'Pending Sign-out' : _formatTime(clockOutTime),
              icon: Icons.logout_rounded,
              color: clockOutTime == null ? ghanaGold : nationalRed,
            ),
            const SizedBox(height: 16),
            _buildTimeRow(
              label: 'Total Hours Worked',
              time: _formatDuration(record),
              icon: Icons.hourglass_top_rounded,
              color: gisDeepOlive,
            ),

            // Optional Notes Section (from backend)
            if (notes.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, thickness: 1, color: Color(0xFFE7E0CD)),
              ),
              _buildInfoRow(
                label: 'Officer Notes',
                value: notes,
                icon: Icons.rate_review_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildTimeRow({
    required String label,
    required String time,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: darkCharcoal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: darkCharcoal,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}