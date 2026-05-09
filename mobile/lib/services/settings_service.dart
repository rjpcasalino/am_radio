import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App settings and preferences.
///
/// Use [load] once at startup, then access settings via getters.
class SettingsService extends ChangeNotifier {
  static const _keyMinimalMode = 'minimal_mode';

  bool _minimalMode = false;

  /// Minimal mode reduces visual effects for better performance on older devices.
  /// - Disables animations and transitions
  /// - Reduces shadow effects
  /// - Simplifies visual elements
  /// - Uses flat, paper-like UI design
  bool get minimalMode => _minimalMode;

  /// Load settings from SharedPreferences.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _minimalMode = prefs.getBool(_keyMinimalMode) ?? false;
    notifyListeners();
  }

  /// Enable or disable minimal mode.
  Future<void> setMinimalMode(bool enabled) async {
    if (_minimalMode == enabled) return;
    _minimalMode = enabled;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMinimalMode, enabled);
  }
}
