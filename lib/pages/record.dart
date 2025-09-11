import 'dart:async';
import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'results.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecorderReady = false;
  bool _isRecording = false;

  Timer? _timer;
  Duration _duration = Duration.zero;

  StreamSubscription? _recorderSubscription;
  List<FlSpot> _spots = [];
  double _timeCounter = 0;
  final int _maxDataPoints = 200;

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  @override
  void dispose() {
    _recorderSubscription?.cancel();
    _recorder.closeRecorder();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initRecorder() async {
    final statuses = await [
      Permission.microphone,
      Permission.storage,
    ].request();
    if (!mounted) return;

    if (statuses[Permission.microphone] != PermissionStatus.granted ||
        statuses[Permission.storage] != PermissionStatus.granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Microphone and Storage permissions are required.')),
      );
      return;
    }

    await _recorder.openRecorder();
    _recorder.setSubscriptionDuration(const Duration(milliseconds: 100));

    _recorderSubscription = _recorder.onProgress?.listen((e) {
      if (e.decibels != null) {
        final double amplitude = ((e.decibels! + 60) / 60).clamp(0.0, 1.0);

        setState(() {
          _spots.add(FlSpot(_timeCounter, amplitude));
          _timeCounter++;
          if (_spots.length > _maxDataPoints) {
            _spots = _spots.sublist(_spots.length - _maxDataPoints);
          }
        });
      }
    });

    setState(() => _isRecorderReady = true);
  }

  void _startTimer() {
    _timer?.cancel();
    _duration = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _duration = Duration(seconds: _duration.inSeconds + 1));
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return "${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  Future<void> _toggleRecording() async {
    if (!_isRecorderReady) return;

    if (_isRecording) {
      final tempPath = await _recorder.stopRecorder();
      _stopTimer();
      setState(() => _isRecording = false);

      if (tempPath != null && mounted) {
        await _askPatientNameAndSave(tempPath);
      }
    } else {
      setState(() {
        _spots = [];
        _timeCounter = 0;
      });

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/heart_sound_temp.wav';

      await _recorder.startRecorder(
        toFile: tempPath,
        codec: Codec.pcm16WAV,
        sampleRate: 44100,
        numChannels: 1,
      );
      _startTimer();
      setState(() => _isRecording = true);
    }
  }

  Future<void> _askPatientNameAndSave(String tempPath) async {
    final nameController = TextEditingController();
    final patientName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Save Recording"),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: "Patient Name", border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.of(context).pop(name);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (patientName == null || patientName.isEmpty) return; // User cancelled

    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) throw Exception("Cannot access storage");

      final storagePath = '${directory.path}/CardioScope/heart_sounds';
      final storageDir = Directory(storagePath);
      if (!await storageDir.exists()) {
        await storageDir.create(recursive: true);
      }

      final date = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
      final safeName = patientName.replaceAll(" ", "_");
      final newPath = "$storagePath/${safeName}_$date.wav";

      final tempFile = File(tempPath);
      await tempFile.copy(newPath);
      await tempFile.delete();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ResultsPage(tempAudioPath: newPath),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Heart Sound',
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F5F5),
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
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: LineChart(
                LineChartData(
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                      axisNameWidget: Text(
                        'Amplitude',
                        style:
                            TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                      axisNameWidget: Text(
                        'Time',
                        style:
                            TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                    topTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: false),
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
            Text(
              _formatDuration(_duration),
              style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  color: Colors.black),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 100,
              height: 100,
              child: FloatingActionButton(
                onPressed: _toggleRecording,
                backgroundColor:
                    _isRecording ? Colors.white : const Color(0xFFC31C42),
                foregroundColor:
                    _isRecording ? const Color(0xFFC31C42) : Colors.white,
                shape: const CircleBorder(),
                elevation: 8,
                child: Icon(_isRecording ? Icons.stop : Icons.mic,
                    size: 50),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isRecording ? "Tap to Stop" : "Tap to Start",
              style:
                  const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
