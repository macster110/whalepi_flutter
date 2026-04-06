/// Represents channel audio data
class ChannelData {
  final int index;
  final double mean;
  final double peakdB;
  final double rmsdB;

  ChannelData({
    required this.index,
    this.mean = 0.0,
    this.peakdB = -100.0,
    this.rmsdB = -100.0,
  });

  /// Get signal level category
  String get levelCategory {
    if (peakdB > -40) return 'HIGH';
    if (peakdB > -60) return 'MED';
    return 'LOW';
  }

  /// Normalize dB to 0-1 range for progress bars (assuming -100 to 0 range)
  double get rmsNormalized => ((rmsdB + 100) / 100).clamp(0.0, 1.0);
  double get peakNormalized => ((peakdB + 100) / 100).clamp(0.0, 1.0);
}

/// GPS data summary
class GpsSummary {
  final String status;
  final DateTime? timestamp;
  final double latitude;
  final double longitude;
  final double headingDeg;

  GpsSummary({
    this.status = 'unknown',
    this.timestamp,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.headingDeg = 0.0,
  });

  String get formattedLat {
    final dir = latitude >= 0 ? 'N' : 'S';
    return '$dir ${latitude.abs().toStringAsFixed(6)}°';
  }

  String get formattedLon {
    final dir = longitude >= 0 ? 'E' : 'W';
    return '$dir ${longitude.abs().toStringAsFixed(6)}°';
  }

  String get headingCardinal {
    const cardinals = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final index = ((headingDeg + 22.5) / 45).floor() % 8;
    return cardinals[index];
  }
}

/// Sound recorder summary
class RecorderSummary {
  final String button;
  final String state;
  final double freeSpaceMB;
  final double fileSizeMB;
  final List<double> channelAmplitudesdB;

  RecorderSummary({
    this.button = '',
    this.state = 'unknown',
    this.freeSpaceMB = 0.0,
    this.fileSizeMB = 0.0,
    this.channelAmplitudesdB = const [],
  });

  double get freeSpaceGB => freeSpaceMB / 1024;
  double get fileSizeGB => fileSizeMB / 1024;

  bool get isRecording => state.toLowerCase() == 'recording';

  /// Estimate disk usage fraction (assuming 500GB total, adjust as needed)
  double get diskUsageFraction {
    const estimatedTotalGB = 500.0;
    return 1.0 - (freeSpaceGB / estimatedTotalGB).clamp(0.0, 1.0);
  }
}

/// Analog sensor data
class AnalogSensorData {
  final String name;
  final double calibratedValue;
  final double voltage;

  AnalogSensorData({
    required this.name,
    this.calibratedValue = 0.0,
    this.voltage = 0.0,
  });
}

/// PAMGuard database summary
class DatabaseSummary {
  final String dbName;
  final int autoCommit;
  final int writes;
  final int fails;

  DatabaseSummary({
    this.dbName = '',
    this.autoCommit = 0,
    this.writes = 0,
    this.fails = 0,
  });

  bool get hasFailures => fails > 0;
}

/// Main PAMGuard summary container
class PamGuardSummary {
  final DateTime receivedAt;
  final List<ChannelData> audioChannels;
  final GpsSummary gps;
  final RecorderSummary recorder;
  final String nmeaSentence;
  final List<AnalogSensorData> analogSensors;
  final double piTemperature;
  final DateTime? pamGuardTime;
  final DatabaseSummary? database;

  PamGuardSummary({
    DateTime? receivedAt,
    this.audioChannels = const [],
    GpsSummary? gps,
    RecorderSummary? recorder,
    this.nmeaSentence = '',
    this.analogSensors = const [],
    this.piTemperature = 0.0,
    this.pamGuardTime,
    this.database,
  }) : receivedAt = receivedAt ?? DateTime.now(),
       gps = gps ?? GpsSummary(),
       recorder = recorder ?? RecorderSummary();

  /// Parse raw summary data from the device
  static PamGuardSummary? parse(String rawData) {
    try {
      final channels = <ChannelData>[];
      GpsSummary? gps;
      RecorderSummary? recorder;
      String nmeaSentence = '';
      final analogSensors = <AnalogSensorData>[];
      double piTemp = 0.0;

      // Parse Sound Acquisition / Raw Data Summary
      // The closing tag may be split across BLE packets, so also accept the
      // outer block boundary (<\Data Acquisition>) as a terminator.
      final rawDataMatch = RegExp(
        r'<RawDataSummary>(.*?)(?:</RawDataSummary>|<\\Data Acquisition>)',
        dotAll: true,
      ).firstMatch(rawData);

      if (rawDataMatch != null) {
        final channelMatches = RegExp(
          r'<channel index="(\d+)">\s*<mean>([-\d.]+)</mean>(?:\s*<peakdB>([-\d.]+)</peakdB>)?(?:\s*<rmsdB>([-\d.]+)</rmsdB>)?\s*</channel>',
          dotAll: true,
        ).allMatches(rawDataMatch.group(1) ?? '');

        for (final match in channelMatches) {
          channels.add(
            ChannelData(
              index: int.parse(match.group(1) ?? '0'),
              mean: double.tryParse(match.group(2) ?? '0') ?? 0.0,
              peakdB: double.tryParse(match.group(3) ?? '-100') ?? -100.0,
              rmsdB: double.tryParse(match.group(4) ?? '-100') ?? -100.0,
            ),
          );
        }
      }

      // Parse GPS Summary
      final gpsMatch = RegExp(
        r'<GPSSummary>(.*?)</GPSSummary>',
        dotAll: true,
      ).firstMatch(rawData);

      if (gpsMatch != null) {
        final gpsData = gpsMatch.group(1) ?? '';
        final status = _extractTag(gpsData, 'status') ?? 'unknown';
        final timestampStr = _extractTag(gpsData, 'timestamp');
        final lat =
            double.tryParse(_extractTag(gpsData, 'latitude') ?? '0') ?? 0.0;
        final lon =
            double.tryParse(_extractTag(gpsData, 'longitude') ?? '0') ?? 0.0;
        final heading =
            double.tryParse(_extractTag(gpsData, 'headingDeg') ?? '0') ?? 0.0;

        DateTime? timestamp;
        if (timestampStr != null) {
          timestamp = DateTime.tryParse(timestampStr.replaceAll(' ', 'T'));
        }

        gps = GpsSummary(
          status: status,
          timestamp: timestamp,
          latitude: lat,
          longitude: lon,
          headingDeg: heading,
        );
      }

      // Parse Recorder Summary
      final recorderMatch = RegExp(
        r'<RecorderSummary>(.*?)</RecorderSummary>',
        dotAll: true,
      ).firstMatch(rawData);

      if (recorderMatch != null) {
        final recData = recorderMatch.group(1) ?? '';
        final button = _extractTag(recData, 'button') ?? '';
        final state = _extractTag(recData, 'state') ?? 'unknown';
        final freeSpace =
            double.tryParse(_extractTag(recData, 'freeSpaceMB') ?? '0') ?? 0.0;
        final fileSize =
            double.tryParse(_extractTag(recData, 'fileSizeMB') ?? '0') ?? 0.0;

        final channelAmps = <double>[];
        final ampMatches = RegExp(
          r'<channel index="\d+">([-\d.]+)</channel>',
        ).allMatches(recData);
        for (final match in ampMatches) {
          channelAmps.add(double.tryParse(match.group(1) ?? '-100') ?? -100.0);
        }

        recorder = RecorderSummary(
          button: button,
          state: state,
          freeSpaceMB: freeSpace,
          fileSizeMB: fileSize,
          channelAmplitudesdB: channelAmps,
        );
      }

      // Parse NMEA
      final nmeaMatch = RegExp(
        r'<NMEA Data>.*?:(\$[A-Z].*?)<\\NMEA Data>',
        dotAll: true,
      ).firstMatch(rawData);
      if (nmeaMatch != null) {
        nmeaSentence = nmeaMatch.group(1) ?? '';
      }

      // Parse Analog Sensors
      final analogMatch = RegExp(
        r'<AnalogSensorsSummary>(.*?)</AnalogSensorsSummary>',
        dotAll: true,
      ).firstMatch(rawData);

      if (analogMatch != null) {
        final analogData = analogMatch.group(1) ?? '';
        // Parse Depth sensor
        final depthMatch = RegExp(
          r'<Depth>\s*<calVal>([-\d.]+)</calVal>\s*<voltage>([-\d.]+)</voltage>\s*</Depth>',
          dotAll: true,
        ).firstMatch(analogData);
        if (depthMatch != null) {
          analogSensors.add(
            AnalogSensorData(
              name: 'Depth',
              calibratedValue:
                  double.tryParse(depthMatch.group(1) ?? '0') ?? 0.0,
              voltage: double.tryParse(depthMatch.group(2) ?? '0') ?? 0.0,
            ),
          );
        }
      }

      // Parse Pi Temperature
      final tempMatch = RegExp(r'temp=([\d.]+)').firstMatch(rawData);
      if (tempMatch != null) {
        piTemp = double.tryParse(tempMatch.group(1) ?? '0') ?? 0.0;
      }

      // Parse PAMGUARD section (optional, for backward compatibility)
      DateTime? pamGuardTime;
      final pamguardMatch = RegExp(
        r'<PAMGUARD>(.*?)<\\PAMGUARD>',
        dotAll: true,
      ).firstMatch(rawData);
      if (pamguardMatch != null) {
        final pamData = pamguardMatch.group(1) ?? '';
        final sysTimeMatch = RegExp(
          r'<SYSTIME>(.*?)<\\SYSTIME>',
          dotAll: true,
        ).firstMatch(pamData);
        if (sysTimeMatch != null) {
          final timeStr = sysTimeMatch.group(1)?.trim();
          if (timeStr != null) {
            pamGuardTime = DateTime.tryParse(
              timeStr.replaceAll(' ', 'T'),
            );
          }
        }
      }

      // Parse Pamguard Database (optional, for backward compatibility)
      DatabaseSummary? database;
      final dbMatch = RegExp(
        r'<Pamguard Database>(.*?)<\\Pamguard Database>',
        dotAll: true,
      ).firstMatch(rawData);
      if (dbMatch != null) {
        final dbData = dbMatch.group(1) ?? '';
        final dbName = _extractTag(dbData, 'DBNAME') ?? '';
        final autoCommit =
            int.tryParse(_extractTag(dbData, 'AUTOCOMMIT') ?? '0') ?? 0;
        final writes =
            int.tryParse(_extractTag(dbData, 'WRITES') ?? '0') ?? 0;
        final fails =
            int.tryParse(_extractTag(dbData, 'FAILS') ?? '0') ?? 0;
        database = DatabaseSummary(
          dbName: dbName,
          autoCommit: autoCommit,
          writes: writes,
          fails: fails,
        );
      }

      return PamGuardSummary(
        audioChannels: channels,
        gps: gps,
        recorder: recorder,
        nmeaSentence: nmeaSentence,
        analogSensors: analogSensors,
        piTemperature: piTemp,
        pamGuardTime: pamGuardTime,
        database: database,
      );
    } catch (e) {
      return null;
    }
  }

  static String? _extractTag(String data, String tag) {
    final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(data);
    return match?.group(1);
  }
}
