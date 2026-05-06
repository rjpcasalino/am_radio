import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../models/station.dart';
import '../services/player_service.dart';
import '../widgets/frequency_dial.dart';
import '../widgets/on_air_lamp.dart';
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
  bool _loFi = false;

  /// True when showing the default station list; false after a search.
  bool _isDefaultMode = true;

  // ── Helpers ────────────────────────────────────────────────────────────────

  int _stationIndex(PlayerService player) {
    if (player.currentStation == null) return -1;
    return _stations.indexWhere((s) => s.url == player.currentStation!.url);
  }

  void _playStation(int index) {
    if (index >= 0 && index < _stations.length) {
      context.read<PlayerService>().play(_stations[index]);
    }
  }

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
    });
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
    final currentIdx = _stationIndex(player);

    return Scaffold(
      backgroundColor: const Color(0xFF1A0F00),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(player),
            _buildDisplayPanel(player, currentIdx),
            Expanded(child: _buildMiddle(player, currentIdx)),
            _buildBottomControls(player, currentIdx),
          ],
        ),
      ),
    );
  }

  // ── A. Header / brand strip ────────────────────────────────────────────────

  Widget _buildHeader(PlayerService player) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          OnAirLamp(isOn: player.isPlaying),
          const Expanded(child: Center(child: RadioLogo(width: 90))),
          _LoFiToggle(
            isOn: _loFi,
            onToggle: () => setState(() => _loFi = !_loFi),
          ),
        ],
      ),
    );
  }

  // ── B. Dial display panel ──────────────────────────────────────────────────

  Widget _buildDisplayPanel(PlayerService player, int currentIdx) {
    final freq = currentIdx >= 0
        ? fakeFreqKHz(currentIdx, _stations.length)
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
              Text(
                '► ',
                style: _monoStyle(
                  color: const Color(0xFFE8A020),
                  bold: true,
                ),
              ),
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
                child: _loading
                    ? const _BlinkingText('… searching …')
                    : (player.isBuffering
                        ? const _BlinkingText('… tuning in …')
                        : _MarqueeText(
                            text: player.currentTrack ?? '',
                            style: _monoStyle(
                              color: const Color(0xFFE8A020),
                            ),
                          )),
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

  // ── C + D. Frequency dial + presets (default mode) ─────────────────────────

  Widget _buildMiddle(PlayerService player, int currentIdx) {
    return _isDefaultMode
        ? _buildDialView(player, currentIdx)
        : _buildSearchResults(player);
  }

  Widget _buildDialView(PlayerService player, int currentIdx) {
    final dialIndex = currentIdx >= 0 ? currentIdx : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'TUNE',
              style: _monoStyle(dim: true, fontSize: 10, letterSpacing: 2),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _StationWheelPicker(
          stations: _stations,
          currentIndex: dialIndex,
          onStationChanged: _playStation,
        ),
      ],
    );
  }

  // ── E. Search results list ─────────────────────────────────────────────────

  Widget _buildSearchResults(PlayerService player) {
    if (_stations.isEmpty) {
      return Center(
        child: Text('No stations found.', style: _monoStyle()),
      );
    }
    return ListView.builder(
      itemCount: _stations.length,
      itemBuilder: (context, index) {
        final station = _stations[index];
        final isPlaying =
            player.isPlaying && player.currentStation?.url == station.url;
        return _StationTile(station: station, isPlaying: isPlaying);
      },
    );
  }

  // ── F. Bottom control strip ────────────────────────────────────────────────

  Widget _buildBottomControls(PlayerService player, int currentIdx) {
    return ColoredBox(
      color: const Color(0xFF0A0500),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                symbol: '◀',
                label: 'prev',
                enabled: currentIdx > 0,
                onPressed: () => _playStation(currentIdx - 1),
              ),
              _ControlButton(
                symbol: '■',
                label: 'stop',
                enabled: player.isPlaying,
                onPressed: () => context.read<PlayerService>().stop(),
              ),
              _ControlButton(
                symbol: '▶',
                label: 'next',
                enabled:
                    currentIdx >= 0 && currentIdx < _stations.length - 1,
                onPressed: () => _playStation(currentIdx + 1),
              ),
              _ControlButton(
                symbol: '↺',
                label: 'defaults',
                enabled: !_isDefaultMode,
                onPressed: _resetToDefaults,
              ),
              _ControlButton(
                symbol: '🔍',
                label: 'find',
                enabled: true,
                onPressed: _showSearchDialog,
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

// ── Lo-Fi toggle button ────────────────────────────────────────────────────

class _LoFiToggle extends StatelessWidget {
  final bool isOn;
  final VoidCallback onToggle;

  const _LoFiToggle({required this.isOn, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Opacity(
        opacity: isOn ? 1.0 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: isOn
                  ? const Color(0xFFE8A020)
                  : const Color(0xFF4A2800),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Lo-Fi',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: isOn
                  ? const Color(0xFFE8A020)
                  : const Color(0xFF6B4400),
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom control strip button ────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final String symbol;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.symbol,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? const Color(0xFFF0E0B0)
        : const Color(0xFF4A2800);
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(symbol, style: TextStyle(fontSize: 18, color: color)),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
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
      trailing: isPlaying
          ? IconButton(
              icon: Icon(Icons.stop_circle_outlined, color: amber),
              tooltip: 'Stop',
              onPressed: () => context.read<PlayerService>().stop(),
            )
          : IconButton(
              icon: Icon(Icons.play_circle_outline, color: dim),
              tooltip: 'Play',
              onPressed: () => context.read<PlayerService>().play(station),
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

// ── Touch-friendly station wheel picker ───────────────────────────────────

// Minimum opacity for off-centre station cards in the wheel.
const _kMinCardOpacity = 0.38;

class _StationWheelPicker extends StatefulWidget {
  final List<Station> stations;
  final int currentIndex;
  final ValueChanged<int> onStationChanged;

  const _StationWheelPicker({
    required this.stations,
    required this.currentIndex,
    required this.onStationChanged,
  });

  @override
  State<_StationWheelPicker> createState() => _StationWheelPickerState();
}

class _StationWheelPickerState extends State<_StationWheelPicker> {
  late PageController _controller;
  late int _displayIndex;

  @override
  void initState() {
    super.initState();
    _displayIndex = widget.stations.isEmpty
        ? 0
        : widget.currentIndex.clamp(0, widget.stations.length - 1);
    _controller = PageController(
      initialPage: _displayIndex,
      viewportFraction: 0.65,
    );
  }

  @override
  void didUpdateWidget(_StationWheelPicker old) {
    super.didUpdateWidget(old);
    if (widget.stations.isEmpty) return;
    final newIdx = widget.currentIndex.clamp(0, widget.stations.length - 1);
    if (newIdx != _displayIndex) {
      _displayIndex = newIdx;
      if (_controller.hasClients) {
        _controller.animateToPage(
          newIdx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Centre notch / tuning pointer
        CustomPaint(
          size: const Size(double.infinity, 10),
          painter: const _TuningNotchPainter(),
        ),
        SizedBox(
          height: 130,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.stations.length,
            onPageChanged: (i) {
              setState(() => _displayIndex = i);
              widget.onStationChanged(i);
            },
            itemBuilder: (_, i) => AnimatedBuilder(
              animation: _controller,
              builder: (_, child) {
                final page = _controller.hasClients
                    ? (_controller.page ?? i.toDouble())
                    : i.toDouble();
                final delta = (page - i).abs().clamp(0.0, 1.0);
                final scale = 1.0 - delta * 0.28;
                final opacity = 1.0 - delta * 0.62;
                return Transform.scale(
                  scale: scale,
                  child: Opacity(opacity: opacity.clamp(_kMinCardOpacity, 1.0), child: child),
                );
              },
              child: _StationCard(
                station: widget.stations[i],
                number: i + 1,
                isActive: i == _displayIndex,
              ),
            ),
          ),
        ),
        // Swipe hint arrows
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                _displayIndex > 0 ? '◀' : '',
                style: const TextStyle(
                  color: Color(0xFF6B4400),
                  fontSize: 13,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Text(
                _displayIndex < widget.stations.length - 1 ? '▶' : '',
                style: const TextStyle(
                  color: Color(0xFF6B4400),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Individual station card inside the wheel ───────────────────────────────

class _StationCard extends StatelessWidget {
  final Station station;
  final int number;
  final bool isActive;

  const _StationCard({
    required this.station,
    required this.number,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0500),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? const Color(0xFFE8A020)
              : const Color(0xFF3A1E00),
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFFE8A020).withOpacity(0.22),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$number',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFF6B4400),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              station.name,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: isActive
                    ? const Color(0xFFE8A020)
                    : const Color(0xFFF0E0B0),
                fontWeight:
                    isActive ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (station.genre != null && station.genre!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              station.genre!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Color(0xFF6B4400),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Tuning notch painter ───────────────────────────────────────────────────

class _TuningNotchPainter extends CustomPainter {
  const _TuningNotchPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final path = Path()
      ..moveTo(cx - 5, 0)
      ..lineTo(cx + 5, 0)
      ..lineTo(cx, 9)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFE8A020));
  }

  @override
  bool shouldRepaint(_TuningNotchPainter _) => false;
}
