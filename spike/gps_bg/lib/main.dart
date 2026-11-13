// Spike Arcline: bukti rekam GPS + suara tetap jalan saat layar mati.
// Kode buang-pakai. Bukan kode produksi. Lihat docs/spike-gps.md.
import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arcline Spike',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const SpikePage(),
    );
  }
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  static const gapLimit = Duration(seconds: 10);

  final tts = FlutterTts();
  StreamSubscription<Position>? _sub;
  Timer? _ticker;
  Timer? _ttsTimer;
  IOSink? _sink;
  String? _path;

  bool running = false;
  String status = 'Siap. Tekan Mulai, kunci layar, lalu jalan.';
  int points = 0;
  int gaps = 0;
  int ttsCount = 0;
  Duration maxGap = Duration.zero;
  double accSum = 0;
  DateTime? startedAt;
  DateTime? _lastAt;
  Position? last;
  Duration elapsed = Duration.zero;

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => status = 'Layanan lokasi mati. Nyalakan di pengaturan HP.');
      return false;
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      setState(() => status = 'Izin lokasi ditolak. Buka pengaturan dan izinkan.');
      return false;
    }
    if (p == LocationPermission.whileInUse) {
      // Spike tetap jalan dengan "saat dipakai" + mode background, tapi catat.
      status = 'Izin: saat dipakai. Untuk hasil terbaik pilih "Selalu".';
    }
    return true;
  }

  LocationSettings _settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Arcline merekam',
          notificationText: 'Uji GPS background sedang berjalan',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      activityType: ActivityType.automotiveNavigation,
      distanceFilter: 0,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
      allowBackgroundLocationUpdates: true,
    );
  }

  Future<void> _start() async {
    if (!await _ensurePermission()) return;

    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    _path = '${dir.path}/arcline_gps_$stamp.csv';
    _sink = File(_path!).openWrite();
    _sink!.writeln('jenis,waktu_hp,lat,lon,akurasi_m,kecepatan_ms');

    await tts.setLanguage('id-ID');
    if (Platform.isIOS) {
      await tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [IosTextToSpeechAudioCategoryOptions.mixWithOthers],
      );
    }

    points = 0;
    gaps = 0;
    ttsCount = 0;
    maxGap = Duration.zero;
    accSum = 0;
    last = null;
    startedAt = DateTime.now();
    _lastAt = startedAt;

    _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
      _onPosition,
      onError: (Object e) => setState(() => status = 'Error GPS: $e'),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || startedAt == null) return;
      setState(() => elapsed = DateTime.now().difference(startedAt!));
    });
    _ttsTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      ttsCount++;
      _sink?.writeln('tts,${DateTime.now().toIso8601String()},,,,');
      await tts.speak('Tes suara, menit ke $ttsCount');
    });

    setState(() {
      running = true;
      status = 'Merekam. Kunci layar sekarang.';
    });
  }

  void _onPosition(Position p) {
    final now = DateTime.now();
    final gap = now.difference(_lastAt ?? now);
    if (points > 0) {
      if (gap > maxGap) maxGap = gap;
      if (gap > gapLimit) gaps++;
    }
    _lastAt = now;
    points++;
    accSum += p.accuracy;
    last = p;
    _sink?.writeln('gps,${now.toIso8601String()},${p.latitude},${p.longitude},'
        '${p.accuracy.toStringAsFixed(1)},${p.speed.toStringAsFixed(2)}');
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _ticker?.cancel();
    _ttsTimer?.cancel();
    await _sink?.flush();
    await _sink?.close();
    _sub = null;
    _ticker = null;
    _ttsTimer = null;
    _sink = null;
    if (mounted) {
      setState(() {
        running = false;
        status = 'Berhenti. Log: ${_path ?? '-'}';
      });
    }
  }

  Future<void> _share() async {
    final path = _path;
    if (path == null || !File(path).existsSync()) {
      setState(() => status = 'Belum ada log. Mulai rekam dulu.');
      return;
    }
    await _sink?.flush();
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: 'Log GPS Arcline spike'),
    );
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final avgAcc = points == 0 ? 0 : accSum / points;
    final rate = elapsed.inSeconds == 0 ? 0 : points / elapsed.inSeconds;
    final ok = gaps == 0 && maxGap <= gapLimit;
    final rows = <(String, String)>[
      ('Durasi', _fmt(elapsed)),
      ('Titik GPS', '$points  (${rate.toStringAsFixed(2)}/detik)'),
      ('Celah terpanjang', '${(maxGap.inMilliseconds / 1000).toStringAsFixed(1)} detik'),
      ('Celah > 10 detik', '$gaps'),
      ('Akurasi rata-rata', '${avgAcc.toStringAsFixed(1)} m'),
      ('Suara terkirim', '$ttsCount'),
      ('Posisi terakhir',
          last == null ? '-' : '${last!.latitude.toStringAsFixed(5)}, ${last!.longitude.toStringAsFixed(5)}'),
      ('Kecepatan', last == null ? '-' : '${(last!.speed * 3.6).toStringAsFixed(1)} km/jam'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Arcline · Spike GPS')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(status),
            const SizedBox(height: 12),
            if (points > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: ok ? Colors.greenAccent : Colors.redAccent),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  ok ? 'LOLOS sejauh ini: tidak ada celah > 10 detik' : 'GAGAL: ada celah > 10 detik',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ok ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(r.$1), Text(r.$2, style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))],
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: running ? _stop : _start,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: Text(running ? 'Berhenti' : 'Mulai'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _share,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Bagikan log (CSV)'),
            ),
          ],
        ),
      ),
    );
  }
}
