import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../models/station.dart';
import '../services/player_service.dart';

/// The same default stations that ship with `am_radio.pl`.
const List<Station> _defaultStations = [
  Station(
    name: 'NPR News (US)',
    url: 'https://npr-ice.streamguys1.com/live.mp3',
    genre: 'News',
  ),
  Station(
    name: 'KEXP Seattle',
    url: 'https://kexp-mp3-128.streamguys1.com/kexp128.mp3',
    genre: 'Music / Talk',
  ),
  Station(
    name: 'WFMU Freeform Radio (NJ)',
    url: 'https://stream0.wfmu.org/freeform-high.aac',
    genre: 'Freeform',
  ),
  Station(
    name: 'WWOZ New Orleans',
    url: 'https://wwoz-sc.streamguys1.com/wwoz-hi.mp3',
    genre: 'Community / Jazz',
  ),
  Station(
    name: 'KUSC Classical (Los Angeles)',
    url: 'http://128.mp3.kusc.live/',
    genre: 'Classical',
  ),
];

/// Radio-browser.info search endpoint — same one used by `am_radio.pl -f`.
const _radioBrowserApi =
    'https://de1.api.radio-browser.info/json/stations/search';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Station> _stations = List.of(_defaultStations);
  bool _loading = false;

  // ── Radio-browser.info search ──────────────────────────────────────────────

  Future<void> _findStations(String query) async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(_radioBrowserApi).replace(queryParameters: {
        'name': query,
        'limit': '30',
        'hidebroken': 'true',
        'order': 'votes',
        'reverse': 'true',
      });
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'am_radio/0.1'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        setState(() {
          _stations = data
              .map((j) => Station.fromJson(j as Map<String, dynamic>))
              .where((s) => s.url.isNotEmpty)
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resetToDefaults() {
    setState(() => _stations = List.of(_defaultStations));
  }

  // ── Search dialog ──────────────────────────────────────────────────────────

  void _showSearchDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Find Stations'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search radio-browser.info…',
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (value) {
            Navigator.of(ctx).pop();
            if (value.isNotEmpty) _findStations(value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text;
              Navigator.of(ctx).pop();
              if (value.isNotEmpty) _findStations(value);
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('📻  AM Radio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset to defaults',
            onPressed: _resetToDefaults,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Find stations',
            onPressed: _showSearchDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: _stations.isEmpty
                ? const Center(child: Text('No stations found.'))
                : ListView.builder(
                    itemCount: _stations.length,
                    itemBuilder: (context, index) {
                      final station = _stations[index];
                      final isPlaying = player.isPlaying &&
                          player.currentStation?.url == station.url;
                      return _StationTile(
                        station: station,
                        isPlaying: isPlaying,
                      );
                    },
                  ),
          ),
          if (player.isPlaying && player.currentStation != null)
            _NowPlayingBar(station: player.currentStation!),
        ],
      ),
    );
  }
}

// ── Station list tile ──────────────────────────────────────────────────────

class _StationTile extends StatelessWidget {
  final Station station;
  final bool isPlaying;

  const _StationTile({required this.station, required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    final color =
        isPlaying ? Theme.of(context).colorScheme.primary : null;

    return ListTile(
      leading: Icon(
        isPlaying ? Icons.radio : Icons.radio_outlined,
        color: color,
      ),
      title: Text(
        station.name,
        style: isPlaying ? TextStyle(color: color, fontWeight: FontWeight.bold) : null,
      ),
      subtitle: station.genre != null
          ? Text(station.genre!, overflow: TextOverflow.ellipsis)
          : (station.bitrate != null
              ? Text('${station.bitrate} kbps')
              : null),
      trailing: isPlaying
          ? IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Stop',
              onPressed: () => context.read<PlayerService>().stop(),
            )
          : IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Play',
              onPressed: () => context.read<PlayerService>().play(station),
            ),
      onTap: () => isPlaying
          ? context.read<PlayerService>().stop()
          : context.read<PlayerService>().play(station),
    );
  }
}

// ── Now-playing bar ────────────────────────────────────────────────────────

class _NowPlayingBar extends StatelessWidget {
  final Station station;

  const _NowPlayingBar({required this.station});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.graphic_eq),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Now playing',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    station.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.stop_circle),
              tooltip: 'Stop',
              onPressed: () => context.read<PlayerService>().stop(),
            ),
          ],
        ),
      ),
    );
  }
}
