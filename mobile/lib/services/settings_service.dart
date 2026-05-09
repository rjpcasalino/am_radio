import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App settings and preferences.
///
/// Use [load] once at startup, then access settings via getters.
class SettingsService extends ChangeNotifier {
  static const _keyMinimalMode = 'minimal_mode';
  static const _keyListView = 'list_view';

  bool _minimalMode = false;
  bool _listView = false;

  /// Minimal mode: A4-paper aesthetic — white background, black text, no logo.
  bool get minimalMode => _minimalMode;

  /// List view: show a simple station list instead of the frequency-dial radio view.
  bool get listView => _listView;

  /// Load settings from SharedPreferences.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _minimalMode = prefs.getBool(_keyMinimalMode) ?? false;
    _listView = prefs.getBool(_keyListView) ?? false;
    notifyListeners();
  }

  /// Enable or disable minimal (A4-paper) mode.
  Future<void> setMinimalMode(bool enabled) async {
    if (_minimalMode == enabled) return;
    _minimalMode = enabled;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMinimalMode, enabled);
  }

  /// Toggle between frequency-dial (radio) view and simple list view.
  Future<void> setListView(bool enabled) async {
    if (_listView == enabled) return;
    _listView = enabled;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyListView, enabled);
  }
}
