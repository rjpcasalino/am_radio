import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../models/station.dart';
import '../services/player_service.dart';
import '../services/station_repository.dart';
import '../widgets/frequency_dial.dart';
import '../widgets/radio_logo.dart';
import '../widgets/signal_meter.dart';

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

  /// True when showing the default station list; false after a search.
  bool _isDefaultMode = true;

  /// True while the inline search bar is visible.
  bool _searchMode = false;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

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
          _isDefaultMode = false;
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
    setState(() {
      _stations = List.of(_defaultStations);
      _isDefaultMode = true;
      _searchMode = false;
      _searchController.clear();
    });
  }

  /// Stations shown in the wheel: saved stations merged with defaults
  /// (deduped by URL), so user-saved stations appear at the top.
  List<Station> _effectiveStations(StationRepository repo) {
    final saved = repo.saved;
    final seen = <String>{};
    final merged = <Station>[];
    for (final s in [...saved, ..._defaultStations]) {
      if (seen.add(s.url)) merged.add(s);
    }
    return merged;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final repo = context.watch<StationRepository>();
    final stations =
        _isDefaultMode ? _effectiveStations(repo) : _stations;
    final currentIdx =
        stations.indexWhere((s) => s.url == player.currentStation?.url);

    return Scaffold(
      backgroundColor: const Color(0xFF1A0F00),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildDisplayPanel(player, currentIdx, stations),
            Expanded(child: _buildMiddle(player, currentIdx, stations)),
          ],
        ),
      ),
    );
  }

  // ── A. Header / brand strip ────────────────────────────────────────────────

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Center(child: RadioLogo(width: 90)),
    );
  }

  // ── B. Dial display panel ──────────────────────────────────────────────────

  Widget _buildDisplayPanel(
      PlayerService player, int currentIdx, List<Station> wheelStations) {
    final freq = currentIdx >= 0
        ? fakeFreqKHz(currentIdx, wheelStations.length)
        : 1020;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0500),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4A2800), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE8A020).withOpacity(0.12),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Station name row
          Row(
            children: [
              Icon(
                player.isPlaying ? Icons.radio : Icons.radio_outlined,
                size: 14,
                color: player.isPlaying
                    ? const Color(0xFFE8A020)
                    : const Color(0xFF6B4400),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  player.currentStation?.name ?? '─── off air ───',
                  style: _monoStyle(bold: player.isPlaying),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (player.isPlaying)
                Text(
                  '$freq kHz',
                  style: _monoStyle(color: const Color(0xFFE8A020)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Track / signal row
          Row(
            children: [
              Text(
                '♪ ',
                style: _monoStyle(color: const Color(0xFF4CAF50)),
              ),
              Expanded(
                child: player.isBuffering
                    ? const _BlinkingText('… tuning in …')
                    : _MarqueeText(
                        text: player.currentTrack ?? '',
                        style: _monoStyle(
                          color: const Color(0xFFE8A020),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              SignalMeter(
                isPlaying: player.isPlaying,
                isBuffering: player.isBuffering,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── C. Search bar / tune label + station list + transport controls ────────

  Widget _buildMiddle(
      PlayerService player, int currentIdx, List<Station> stations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchOrTuneRow(),
        Expanded(child: _buildStationList(player, stations)),
        _buildTransportControls(player, currentIdx, stations),
      ],
    );
  }

  // ── Inline search bar or TUNE label row ───────────────────────────────────

  Widget _buildSearchOrTuneRow() {
    final bool showSearchBar = _searchMode || !_isDefaultMode;

    if (showSearchBar) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                // Only autofocus when the bar first opens (default mode).
                // After results are showing we must not steal focus again.
                autofocus: _searchMode && _isDefaultMode,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: Color(0xFFF0E0B0),
                ),
                decoration: InputDecoration(
                  hintText: 'Search radio-browser.info…',
                  hintStyle: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFF6B4400),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF0A0500),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF4A2800)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFF4A2800)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                      color: Color(0xFFE8A020),
                      width: 1.5,
                    ),
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (v) {
                  final q = v.trim();
                  if (q.isNotEmpty) _findStations(q);
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.search, color: Color(0xFFE8A020)),
              iconSize: 22,
              tooltip: 'Search',
              onPressed: () {
                final q = _searchController.text.trim();
                if (q.isNotEmpty) _findStations(q);
              },
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Color(0xFF6B4400)),
              iconSize: 20,
              tooltip: 'Back to defaults',
              onPressed: _resetToDefaults,
            ),
          ],
        ),
      );
    }

    // Default mode: TUNE label + find button
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
      child: Row(
        children: [
          Text(
            'TUNE',
            style: _monoStyle(dim: true, fontSize: 10, letterSpacing: 2),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _searchMode = true),
            icon: const Icon(
              Icons.search,
              size: 16,
              color: Color(0xFF6B4400),
            ),
            label: Text(
              'find',
              style: _monoStyle(dim: true, fontSize: 10, letterSpacing: 1),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  // ── D. Unified vertical station list ─────────────────────────────────────

  Widget _buildStationList(PlayerService player, List<Station> stations) {
    if (_loading) {
      return const Center(
        child: _BlinkingText('… searching …'),
      );
    }
    if (stations.isEmpty) {
      return Center(
        child: Text('No stations found.', style: _monoStyle()),
      );
    }
    return ListView.builder(
      itemCount: stations.length,
      itemBuilder: (context, index) {
        final station = stations[index];
        final isPlaying =
            player.isPlaying && player.currentStation?.url == station.url;
        return _StationTile(station: station, isPlaying: isPlaying);
      },
    );
  }

  // ── E. Transport controls (◀  ■  ▶) ──────────────────────────────────────

  Widget _buildTransportControls(
      PlayerService player, int currentIdx, List<Station> stations) {
    return ColoredBox(
      color: const Color(0xFF0A0500),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _TransportButton(
                symbol: '◀',
                enabled: currentIdx > 0,
                onPressed: () =>
                    context.read<PlayerService>().play(stations[currentIdx - 1]),
              ),
              _TransportButton(
                symbol: '■',
                enabled: stations.isNotEmpty,
                onPressed: () {
                  final ps = context.read<PlayerService>();
                  if (ps.isPlaying) {
                    ps.stop();
                  } else {
                    // Play the first station (or re-play the last tuned one).
                    final target = currentIdx >= 0
                        ? stations[currentIdx]
                        : stations[0];
                    ps.play(target);
                  }
                },
              ),
              _TransportButton(
                symbol: '▶',
                enabled:
                    currentIdx >= 0 && currentIdx < stations.length - 1,
                onPressed: () =>
                    context.read<PlayerService>().play(stations[currentIdx + 1]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Style helpers ──────────────────────────────────────────────────────────

  static TextStyle _monoStyle({
    bool bold = false,
    bool dim = false,
    Color? color,
    double fontSize = 13,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      color: color ??
          (dim ? const Color(0xFF6B4400) : const Color(0xFFF0E0B0)),
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      letterSpacing: letterSpacing,
    );
  }
}

// ── Blinking text for the "tuning in" / "searching" indicator ─────────────

class _BlinkingText extends StatefulWidget {
  final String text;

  const _BlinkingText(this.text);

  @override
  State<_BlinkingText> createState() => _BlinkingTextState();
}

class _BlinkingTextState extends State<_BlinkingText> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (mounted) setState(() => _visible = !_visible);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _visible ? 1.0 : 0.3,
      child: Text(
        widget.text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: Color(0xFFE8A020),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ── Station list tile (used in search-results mode) ────────────────────────

class _StationTile extends StatelessWidget {
  final Station station;
  final bool isPlaying;

  const _StationTile({required this.station, required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFE8A020);
    const cream = Color(0xFFF0E0B0);
    const dim = Color(0xFF6B4400);

    final repo = context.watch<StationRepository>();
    final saved = repo.isSaved(station);

    return ListTile(
      leading: Icon(
        isPlaying ? Icons.radio : Icons.radio_outlined,
        color: isPlaying ? amber : dim,
      ),
      title: Text(
        station.name,
        style: TextStyle(
          fontFamily: 'monospace',
          color: isPlaying ? amber : cream,
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: station.genre != null
          ? Text(
              station.genre!,
              style: TextStyle(
                fontFamily: 'monospace',
                color: dim,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            )
          : (station.bitrate != null
              ? Text(
                  '${station.bitrate} kbps',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: dim,
                    fontSize: 11,
                  ),
                )
              : null),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Save / unsave toggle
          IconButton(
            icon: Icon(
              saved ? Icons.star : Icons.star_border,
              color: saved ? amber : dim,
              size: 20,
            ),
            tooltip: saved ? 'Unsave' : 'Save station',
            onPressed: () => saved
                ? context.read<StationRepository>().remove(station)
                : context.read<StationRepository>().save(station),
          ),
          // Play / stop toggle
          isPlaying
              ? IconButton(
                  icon: Icon(Icons.stop_circle_outlined, color: amber),
                  tooltip: 'Stop',
                  onPressed: () => context.read<PlayerService>().stop(),
                )
              : IconButton(
                  icon: Icon(Icons.play_circle_outline, color: dim),
                  tooltip: 'Play',
                  onPressed: () =>
                      context.read<PlayerService>().play(station),
                ),
        ],
      ),
      onTap: () => isPlaying
          ? context.read<PlayerService>().stop()
          : context.read<PlayerService>().play(station),
    );
  }
}

// ── Auto-scrolling (marquee) text ──────────────────────────────────────────

// Milliseconds of scroll animation per pixel of overflow.
const _kScrollMsPerPixel = 30;

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> {
  final ScrollController _scroll = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleScroll());
  }

  void _scheduleScroll() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), _doScroll);
  }

  Future<void> _doScroll() async {
    if (!mounted || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return; // text fits — nothing to scroll
    await _scroll.animateTo(
      max,
      duration: Duration(milliseconds: (max * _kScrollMsPerPixel).round()),
      curve: Curves.linear,
    );
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    _scroll.jumpTo(0);
    _scheduleScroll();
  }

  @override
  void didUpdateWidget(_MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _timer?.cancel();
      if (_scroll.hasClients) _scroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleScroll());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, style: widget.style, maxLines: 1),
    );
  }
}

// ── Transport button (◀  ■  ▶) ────────────────────────────────────────────

class _TransportButton extends StatelessWidget {
  final String symbol;
  final bool enabled;
  final VoidCallback onPressed;

  const _TransportButton({
    required this.symbol,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Text(
          symbol,
          style: TextStyle(
            fontSize: 22,
            color:
                enabled ? const Color(0xFFF0E0B0) : const Color(0xFF4A2800),
          ),
        ),
      ),
    );
  }
}
