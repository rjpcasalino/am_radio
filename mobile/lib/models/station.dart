/// A radio station.
class Station {
  final String name;
  final String url;
  final String? genre;
  final int? bitrate;

  const Station({
    required this.name,
    required this.url,
    this.genre,
    this.bitrate,
  });

  /// Parse a line in the `Name::URL` format used by `~/.radio_stations`.
  factory Station.fromConfigLine(String line) {
    final parts = line.split('::');
    if (parts.length != 2) {
      throw FormatException('Invalid station line: $line');
    }
    return Station(name: parts[0].trim(), url: parts[1].trim());
  }

  /// Parse a result object from the radio-browser.info JSON API.
  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      name: (json['name'] as String? ?? 'Unknown').trim(),
      url: (json['url_resolved'] as String? ?? json['url'] as String? ?? '')
          .trim(),
      genre: json['tags'] as String?,
      bitrate: int.tryParse(json['bitrate']?.toString() ?? ''),
    );
  }

  /// Serialise back to the `Name::URL` config format.
  @override
  String toString() => '$name::$url';
}
