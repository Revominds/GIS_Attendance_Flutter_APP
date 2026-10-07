// On-device geo-fence set by an admin: a precise GPS point + radius.
// Clock-in/out is only allowed inside it. Stored locally so it works
// without backend changes (the server's branch data is currently static
// placeholders). When no fence is set, the app falls back to the
// server-provided branch locations.

import 'package:shared_preferences/shared_preferences.dart';

class GeoFence {
  final double lat;
  final double lng;
  final double radiusMeters;
  final String name;

  const GeoFence({
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    required this.name,
  });
}

class GeoFenceService {
  static const _kLat = 'geofence_lat';
  static const _kLng = 'geofence_lng';
  static const _kRadius = 'geofence_radius';
  static const _kName = 'geofence_name';

  static const List<double> radiusOptions = [50, 100, 200, 500, 1000];

  static Future<GeoFence?> load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kLat) || !prefs.containsKey(_kLng)) return null;
    return GeoFence(
      lat: prefs.getDouble(_kLat)!,
      lng: prefs.getDouble(_kLng)!,
      radiusMeters: prefs.getDouble(_kRadius) ?? 100,
      name: prefs.getString(_kName) ?? 'Worksite',
    );
  }

  static Future<void> save(GeoFence fence) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kLat, fence.lat);
    await prefs.setDouble(_kLng, fence.lng);
    await prefs.setDouble(_kRadius, fence.radiusMeters);
    await prefs.setString(_kName, fence.name);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLat);
    await prefs.remove(_kLng);
    await prefs.remove(_kRadius);
    await prefs.remove(_kName);
  }
}
