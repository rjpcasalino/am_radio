import 'package:flutter/foundation.dart';

/// In-app logging service that stores logs in memory for viewing.
///
/// Logs are capped at a maximum number of entries to prevent memory issues.
/// Use [log] to add entries and access [entries] to read them.
class LogService extends ChangeNotifier {
  static const _maxEntries = 500;

  final List<LogEntry> _entries = [];

  /// Unmodifiable view of current log entries (newest first).
  List<LogEntry> get entries => List.unmodifiable(_entries.reversed);

  /// Add a log entry. Automatically prunes old entries if limit exceeded.
  void log(String message, {LogLevel level = LogLevel.info}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
    );

    _entries.add(entry);

    // Prune old entries if we exceed the limit
    if (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }

    notifyListeners();

    // Also print to debug console for development
    if (kDebugMode) {
      final prefix = '[${entry.level.name.toUpperCase()}]';
      debugPrint('$prefix ${entry.formattedTimestamp} ${entry.message}');
    }
  }

  /// Clear all log entries.
  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// Export logs as a string (for sharing/reporting).
  String export() {
    return entries
        .map((e) => '${e.formattedTimestamp} [${e.level.name}] ${e.message}')
        .join('\n');
  }
}

/// Log severity level.
enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// A single log entry.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  String get formattedTimestamp {
    return timestamp.toIso8601String();
  }
}
