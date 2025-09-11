import 'dart:async';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late Future<List<FileSystemEntity>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = _loadReports();
  }

  Future<List<FileSystemEntity>> _loadReports() async {
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) return [];

      final storagePath = '${directory.path}/CardioScope/heart_sounds';
      final reportDir = Directory(storagePath);

      if (await reportDir.exists()) {
        final files = reportDir.listSync();
        files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        return files;
      } else {
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error loading reports: $e");
      }
      return [];
    }
  }

  String _getFileName(String path) {
    return path.split('/').last;
  }

  void _refreshReports() {
    setState(() {
      _reportsFuture = _loadReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Saved Results", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshReports,
          ),
        ],
      ),
      body: FutureBuilder<List<FileSystemEntity>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final reports = snapshot.data;

          if (reports == null || reports.isEmpty) {
            return const Center(
              child: Text(
                "No saved reports found.",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final reportFile = reports[index];
              final fileName = _getFileName(reportFile.path);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.audiotrack, color: Color(0xFFC31C42)),
                  title: Text(
                    fileName.replaceAll('.wav', '').replaceAll('_', ' '),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Heart Sound Recording'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => AudioPlayerPage(filePath: reportFile.path),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AudioPlayerPage extends StatefulWidget {
  final String filePath;
  const AudioPlayerPage({super.key, required this.filePath});

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlayerReady = false;
  bool _isPlaying = false;

  StreamSubscription? _playerSubscription;
  List<FlSpot> _spots = [];
  double _timeCounter = 0;
  final int _maxDataPoints = 200;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    _player.setSubscriptionDuration(const Duration(milliseconds: 100));
    setState(() => _isPlayerReady = true);

    _playerSubscription = _player.onProgress?.listen((e) {
      final double amplitude = (e.position.inMilliseconds % 1000) / 1000; // Fake waveform

      setState(() {
        _spots.add(FlSpot(_timeCounter, amplitude));
        _timeCounter++;
        if (_spots.length > _maxDataPoints) {
          _spots = _spots.sublist(_spots.length - _maxDataPoints);
        }
      });
    });
  }

  Future<void> _togglePlay() async {
    if (!_isPlayerReady) return;

    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() {
        _isPlaying = false;
        _spots = [];
        _timeCounter = 0;
      });
    } else {
      await _player.startPlayer(
        fromURI: widget.filePath,
        codec: Codec.pcm16WAV,
        whenFinished: () {
          setState(() => _isPlaying = false);
        },
      );
      setState(() => _isPlaying = true);
    }
  }

  @override
  void dispose() {
    _playerSubscription?.cancel();
    _player.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.filePath.split('/').last;

    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 150,
              width: MediaQuery.of(context).size.width * 0.9,
              padding: const EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.1),
                    blurRadius: 5,
                    offset: Offset(0, 2),
                  )
                ],
              ),
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                      axisNameWidget: Text(
                        'Amplitude',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                      axisNameWidget: Text(
                        'Time',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _spots,
                      isCurved: false,
                      color: const Color(0xFFC31C42),
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  minY: 0,
                  maxY: 1,
                ),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC31C42),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              onPressed: _togglePlay,
              icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
              label: Text(_isPlaying ? "Stop" : "Play"),
            ),
          ],
        ),
      ),
    );
  }
}
