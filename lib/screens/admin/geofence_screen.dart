// ADMIN — geo-fence setup. An admin stands at the worksite, captures the
// phone's precise GPS fix as the fence centre, picks a radius, and saves.
// From then on, clock-in/out on THIS device is only allowed inside that
// circle, gated on a precise fix (poor-accuracy fixes are rejected, not
// guessed). Stored on-device via GeoFenceService — no backend change.

import 'package:flutter/material.dart';
import 'package:gis_attendance/services/attendance_service.dart';
import 'package:gis_attendance/services/geofence_service.dart';
import 'package:gis_attendance/theme/gis_palette.dart';

const _dark = Color(0xFF142412);
const _gold = Color(0xFFE1B12C);
const _bg = Color(0xFFF5F6F5);

class GeoFenceScreen extends StatefulWidget {
  const GeoFenceScreen({super.key});

  @override
  State<GeoFenceScreen> createState() => _GeoFenceScreenState();
}

class _GeoFenceScreenState extends State<GeoFenceScreen> {
  final _attendanceService = AttendanceService();
  final _nameCtrl = TextEditingController(text: 'Head Office');

  GeoFence? _saved;
  double? _capLat;
  double? _capLng;
  double? _capAcc;
  double _radius = 100;
  bool _busy = false;
  String? _status;

  // Live distance readout.
  double? _liveDistance;
  double? _liveAcc;
  bool _liveBusy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final fence = await GeoFenceService.load();
    if (!mounted) return;
    setState(() {
      _saved = fence;
      if (fence != null) {
        _radius = fence.radiusMeters;
        _nameCtrl.text = fence.name;
      }
    });
  }

  Future<void> _capture() async {
    setState(() {
      _busy = true;
      _status = 'Capturing precise GPS fix… stand still outdoors.';
    });
    try {
      final res = await _attendanceService.getCurrentLocation();
      if (!mounted) return;
      if (!res.success || res.location == null) {
        setState(() => _status = res.message);
        return;
      }
      final loc = res.location!;
      setState(() {
        _capLat = loc['lat'];
        _capLng = loc['lng'];
        _capAcc = loc['acc'];
        final acc = loc['acc'] ?? 999;
        _status = acc <= 30
            ? 'Precise fix locked (±${acc.toStringAsFixed(0)} m). Ready to save.'
            : 'Fix accuracy ±${acc.toStringAsFixed(0)} m — move outdoors and capture again for a precise anchor.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_capLat == null || _capLng == null) {
      setState(() => _status = 'Capture the location first.');
      return;
    }
    await GeoFenceService.save(GeoFence(
      lat: _capLat!,
      lng: _capLng!,
      radiusMeters: _radius,
      name: _nameCtrl.text.trim().isEmpty ? 'Worksite' : _nameCtrl.text.trim(),
    ));
    await _reload();
    if (!mounted) return;
    setState(() => _status = 'Geo-fence saved. Clock-in now requires being inside it.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Geo-fence saved'), backgroundColor: GisPalette.of(context).primary),
    );
  }

  Future<void> _clear() async {
    await GeoFenceService.clear();
    await _reload();
    if (!mounted) return;
    setState(() => _status = 'Geo-fence removed. Server branch locations apply again.');
  }

  Future<void> _refreshLive() async {
    setState(() {
      _liveBusy = true;
      _liveDistance = null;
    });
    try {
      final res = await _attendanceService.getCurrentLocation();
      if (!mounted || !res.success || res.location == null || _saved == null) {
        return;
      }
      final loc = res.location!;
      setState(() {
        _liveAcc = loc['acc'];
        _liveDistance = _attendanceService.distanceMeters(
          loc['lat']!, loc['lng']!, _saved!.lat, _saved!.lng);
      });
    } finally {
      if (mounted) setState(() => _liveBusy = false);
    }
  }

  Color _accColor(double? acc) {
    if (acc == null) return GisPalette.of(context).muted;
    if (acc <= 20) return Colors.green.shade700;
    if (acc <= 50) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Saved fence',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 8),
              if (_saved == null)
                Text('No fence set — server branch locations apply.',
                    style: TextStyle(color: GisPalette.of(context).muted))
              else ...[
                Text(
                    '${_saved!.name} • ±${_saved!.radiusMeters.toStringAsFixed(0)} m',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                    '${_saved!.lat.toStringAsFixed(6)}, ${_saved!.lng.toStringAsFixed(6)}',
                    style: TextStyle(color: GisPalette.of(context).muted, fontSize: 12.5)),
                if (_liveDistance != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _liveDistance! <= _saved!.radiusMeters
                        ? 'You are ${_liveDistance!.toStringAsFixed(0)} m away (±${(_liveAcc ?? 0).toStringAsFixed(0)} m GPS) — INSIDE ✅'
                        : 'You are ${_liveDistance!.toStringAsFixed(0)} m away (±${(_liveAcc ?? 0).toStringAsFixed(0)} m GPS) — OUTSIDE ❌',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _liveDistance! <= _saved!.radiusMeters
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _liveBusy ? null : _refreshLive,
                        icon: const Icon(Icons.my_location, size: 17),
                        label: Text(_liveBusy ? 'Checking…' : 'Where am I?'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _clear,
                        icon: const Icon(Icons.delete_outline, size: 17),
                        label: const Text('Remove fence'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Set new fence',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                'Stand at the worksite entrance, capture a precise fix, pick a range, save.',
                style: TextStyle(color: GisPalette.of(context).muted, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Site name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              const Text('Range (radius)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: GeoFenceService.radiusOptions.map((r) {
                  final selected = _radius == r;
                  return ChoiceChip(
                    label: Text('±${r.toStringAsFixed(0)} m'),
                    selected: selected,
                    onSelected: (_) => setState(() => _radius = r),
                    selectedColor: GisPalette.of(context).primary,
                    labelStyle: TextStyle(
                        color: selected
                            ? Colors.white
                            : GisPalette.of(context).ink,
                        fontWeight: FontWeight.w600),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              if (_capLat != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${_capLat!.toStringAsFixed(6)}, ${_capLng!.toStringAsFixed(6)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(
                        'Accuracy ±${(_capAcc ?? 999).toStringAsFixed(0)} m',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _accColor(_capAcc),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_capLat != null) const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _capture,
                      icon: const Icon(Icons.gps_fixed, size: 17),
                      label: Text(_busy ? 'Capturing…' : 'Capture location'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_busy || _capLat == null) ? null : _save,
                      icon: const Icon(Icons.save_outlined, size: 17),
                      label: const Text('Save fence'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GisPalette.of(context).primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              if (_status != null) ...[
                const SizedBox(height: 8),
                Text(_status!,
                    style: TextStyle(color: GisPalette.of(context).muted, fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}
