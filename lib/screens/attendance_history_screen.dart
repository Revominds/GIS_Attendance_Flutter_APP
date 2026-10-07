import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gis_attendance/services/attendance_service.dart';
import 'package:gis_attendance/theme/gis_palette.dart';

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
  String _filter = 'All'; // All | Ongoing | Completed

  late ScrollController _scrollController;

  // GIS Theme Colors now resolve from GisPalette (light/dark aware).

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
      backgroundColor: GisPalette.of(context).bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: GisPalette.of(context).ink,
        iconTheme: IconThemeData(color: GisPalette.of(context).primary),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: GisPalette.of(context).primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Attendance History',
          style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: GisPalette.of(context).ink),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: GisPalette.of(context).primary),
            onPressed: _loadHistory,
            tooltip: 'Refresh history',
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: GisPalette.of(context).hairline),
        ),
      ),
      body: _historyLoading && _history.isEmpty
          ? Center(
              child: CircularProgressIndicator(color: GisPalette.of(context).primary),
            )
          : _history.isEmpty
              ? _buildEmptyState()
              : _buildHistoryList(),
    );
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'Ongoing') {
      return _history.where((r) => _isOpenRecord(r)).toList();
    }
    if (_filter == 'Completed') {
      return _history.where((r) => !_isOpenRecord(r)).toList();
    }
    return _history;
  }

  int _totalMinutes() {
    var total = 0;
    for (final r in _history) {
      num? minutes;
      final raw = r['duration_minutes'];
      if (raw != null) minutes = num.tryParse(raw.toString());
      minutes ??= () {
        final inTime = _clockIn(r);
        final outTime = _clockOut(r);
        if (inTime is String && outTime is String) {
          try {
            return DateTime.parse(outTime)
                .difference(DateTime.parse(inTime))
                .inMinutes;
          } catch (_) {
            return null;
          }
        }
        return null;
      }();
      if (minutes != null) total += minutes.abs().round();
    }
    return total;
  }

  String _prettyHours(int totalMinutes) {
    if (totalMinutes <= 0) return '0h';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Widget _summaryTile(
      String value, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GisPalette.of(context).hairline),
      ),
      child: Column(
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
          Text(
            value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color),
          ),
          Text(label,
              style:
                  TextStyle(fontSize: 11.5, color: GisPalette.of(context).muted)),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final ongoing =
        _history.where((r) => _isOpenRecord(r)).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Expanded(
              child: _summaryTile('${_history.length}', 'Shifts',
                  Icons.calendar_month_outlined, GisPalette.of(context).primary)),
          const SizedBox(width: 10),
          Expanded(
              child: _summaryTile(
                  _prettyHours(_totalMinutes()),
                  'Hours worked',
                  Icons.hourglass_top_rounded,
                  GisPalette.of(context).goldDark)),
          const SizedBox(width: 10),
          Expanded(
              child: _summaryTile(
                  '$ongoing',
                  'Ongoing',
                  Icons.timelapse_rounded,
                  ongoing > 0 ? GisPalette.of(context).danger : GisPalette.of(context).success)),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final ongoing =
        _history.where((r) => _isOpenRecord(r)).length;
    final counts = {
      'All': _history.length,
      'Ongoing': ongoing,
      'Completed': _history.length - ongoing,
    };
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final f in counts.keys)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$f · ${counts[f]}'),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
                selectedColor: GisPalette.of(context).primary,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _filter == f ? Colors.white : GisPalette.of(context).ink,
                ),
                side: BorderSide(
                  color: _filter == f ? GisPalette.of(context).primary : GisPalette.of(context).hairline,
                ),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: Color(0xFFE3EAE1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_toggle_off_rounded,
                size: 40,
                color: GisPalette.of(context).primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No duty records',
              style: TextStyle(
                fontSize: 17,
                color: GisPalette.of(context).ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your clock in/out history will appear here once you start checking in.',
              style: TextStyle(fontSize: 13, color: GisPalette.of(context).muted, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadHistory,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh history'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GisPalette.of(context).primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList() {
    final shown = _filtered;
    return RefreshIndicator(
      color: GisPalette.of(context).primary,
      onRefresh: _loadHistory,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildSummary()),
          SliverToBoxAdapter(child: _buildFilters()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            sliver: SliverGrid(
              gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 420,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                mainAxisExtent: 148,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final record = shown[index];
                  return _buildHistoryCard(record, _isOpenRecord(record));
                },
                childCount: shown.length,
              ),
            ),
          ),
          if (_historyLoading)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: GisPalette.of(context).primary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatShortTime(dynamic time) {
    if (time == null) return "--:--";
    if (time is String) {
      try {
        final dt = DateTime.parse(time).toLocal();
        return DateFormat('HH:mm').format(dt);
      } catch (_) {
        return time.toString();
      }
    }
    return time.toString();
  }

  /// Compact "8h 5m" duration for the grid card.
  String _shortDuration(Map<String, dynamic> record) {
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
          minutes = DateTime.parse(outTime)
              .difference(DateTime.parse(inTime))
              .inMinutes;
        } catch (_) {
          minutes = null;
        }
      }
    }
    if (minutes == null) return "-";
    final total = minutes.abs().round();
    final h = total ~/ 60;
    final m = total % 60;
    return m == 0 ? "${h}h" : "${h}h ${m}m";
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: GisPalette.of(context).muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOpen ? GisPalette.of(context).gold : GisPalette.of(context).hairline,
          width: isOpen ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_outlined,
                  color: GisPalette.of(context).primary, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _formatDate(dateValue),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: GisPalette.of(context).ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isOpen
                      ? const Color(0xFFFBF1D8)
                      : const Color(0xFFE1F9EC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isOpen ? 'ONGOING' : 'DONE',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: isOpen
                        ? const Color(0xFF9E7500)
                        : const Color(0xFF14663A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _miniStat('IN', _formatShortTime(clockInTime),
                  const Color(0xFF14663A)),
              _miniStat(
                  'OUT',
                  clockOutTime == null
                      ? 'Pending'
                      : _formatShortTime(clockOutTime),
                  clockOutTime == null ? GisPalette.of(context).goldDark : GisPalette.of(context).danger),
              _miniStat(
                  'HRS', _shortDuration(record), GisPalette.of(context).primary),
            ],
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.sticky_note_2_outlined,
                    size: 12, color: GisPalette.of(context).muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    notes,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: GisPalette.of(context).muted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  
}
