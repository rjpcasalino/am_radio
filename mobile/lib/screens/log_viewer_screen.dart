import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/log_service.dart';

/// In-app log viewer screen for debugging and issue reporting.
class LogViewerScreen extends StatelessWidget {
  const LogViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final logService = context.watch<LogService>();
    final entries = logService.entries;

    return Scaffold(
      backgroundColor: const Color(0xFF1A0F00),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E1A00),
        title: const Text(
          'Debug Logs',
          style: TextStyle(
            fontFamily: 'monospace',
            color: Color(0xFFF0E0B0),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFFE8A020)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy logs',
            onPressed: () async {
              final text = logService.export();
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Logs copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: () {
              logService.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Logs cleared'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Text(
                'No logs yet',
                style: _monoStyle(dim: true),
              ),
            )
          : ListView.builder(
              itemCount: entries.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _LogEntryTile(entry: entry);
              },
            ),
    );
  }

  static TextStyle _monoStyle({bool dim = false}) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: dim ? const Color(0xFF6B4400) : const Color(0xFFF0E0B0),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;

  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final levelColor = _getLevelColor(entry.level);
    final timeStr = _formatTime(entry.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0500),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: levelColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: levelColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  entry.level.name.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: levelColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeStr,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Color(0xFF6B4400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.message,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFFF0E0B0),
            ),
          ),
        ],
      ),
    );
  }

  Color _getLevelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return const Color(0xFF6B4400); // dim
      case LogLevel.info:
        return const Color(0xFFE8A020); // amber
      case LogLevel.warning:
        return const Color(0xFFFF6B35); // orange
      case LogLevel.error:
        return const Color(0xFFFF3333); // red
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
