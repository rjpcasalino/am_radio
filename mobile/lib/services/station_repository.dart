import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/station.dart';

/// Persists user-saved stations to [SharedPreferences].
///
/// Call [load] once at startup before the widget tree is built.
/// Saved stations survive app restarts, mirroring the behaviour of
/// the `~/.radio_stations` file used by `am_radio.pl`.
class StationRepository extends ChangeNotifier {
  static const _key = 'saved_stations';

  List<Station> _saved = [];

  /// Unmodifiable view of the currently saved stations.
  List<Station> get saved => List.unmodifiable(_saved);

  /// Load persisted stations from [SharedPreferences].
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _saved =
          list.map((e) => Station.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (_) {
      // Ignore corrupt data — start with an empty saved list.
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _saved
        .map((s) => {
              'name': s.name,
              'url_resolved': s.url,
              'tags': s.genre ?? '',
              // Omit bitrate entirely when absent so fromJson receives null
              // rather than the integer 0, matching the original data model.
              if (s.bitrate != null) 'bitrate': '${s.bitrate}',
            })
        .toList();
    await prefs.setString(_key, jsonEncode(data));
  }

  /// Add [station] to the saved list (no-op if already saved).
  Future<void> save(Station station) async {
    if (isSaved(station)) return;
    _saved = [..._saved, station];
    notifyListeners();
    await _persist();
  }

  /// Remove [station] from the saved list (no-op if not saved).
  Future<void> remove(Station station) async {
    if (!isSaved(station)) return;
    _saved = _saved.where((s) => s.url != station.url).toList();
    notifyListeners();
    await _persist();
  }

  /// Returns true if a station with the same URL is in the saved list.
  bool isSaved(Station station) => _saved.any((s) => s.url == station.url);
}
