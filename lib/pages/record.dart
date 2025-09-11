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
  bool? _hasPermissions; // null = checking, true = granted, false = denied

  Timer? _timer;
  Duration _duration = Duration.zero;

  StreamSubscription? _recorderSubscription;
  List<FlSpot> _spots = [];
  double _timeCounter = 0;
  final int _maxDataPoints = 200;

  @override
  void initState() {
    super.initState();
    _initAndRequestPermissions();
  }

  @override
  void dispose() {
    _recorderSubscription?.cancel();
    if (_recorder.isRecording) {
      _recorder.stopRecorder();
    }
    _recorder.closeRecorder();
    _timer?.cancel();
    super.dispose();
  }

  /// 🔹 Requests ONLY the microphone permission and initializes the recorder.
  Future<void> _initAndRequestPermissions() async {
    final micStatus = await Permission.microphone.request();

    // We only need to check for microphone status now.
    if (micStatus.isGranted) {
      await _initRecorder();
      if (mounted) {
        setState(() {
          _hasPermissions = true;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _hasPermissions = false;
        });
      }
    }
  }
  
  Future<void> _initRecorder() async {
    await _recorder.openRecorder();
    _recorder.setSubscriptionDuration(const Duration(milliseconds: 100));

    _recorderSubscription = _recorder.onProgress?.listen((e) {
      if (e.decibels != null && mounted) {
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

    if (mounted) {
       setState(() => _isRecorderReady = true);
    }
  }

  Future<void> _toggleRecording() async {
    if (!_isRecorderReady) {
      await _initAndRequestPermissions();
      return;
    }

    if (_isRecording) {
      final tempPath = await _recorder.stopRecorder();
      _stopTimer();
      if(mounted) {
        setState(() => _isRecording = false);
        if (tempPath != null) {
          _askPatientNameAndSave(tempPath);
        }
      }
    } else {
      if(mounted) {
        setState(() {
          _spots = [];
          _timeCounter = 0;
        });
      }
      // This directory does NOT require special permissions on modern Android
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/heart_sound_temp.wav';
      await _recorder.startRecorder(
        toFile: tempPath,
        codec: Codec.pcm16WAV,
      );
      _startTimer();
      if(mounted) {
        setState(() => _isRecording = true);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Heart Sound', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: Center(
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_hasPermissions == null) {
      return const CircularProgressIndicator(color: Color(0xFFC31C42));
    }
    if (_hasPermissions == false) {
      return _buildPermissionsDeniedUI();
    }
    return _buildRecordingUI();
  }

  Widget _buildRecordingUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                color: Colors.black.withValues(alpha:0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: LineChart(
            LineChartData(
              titlesData: const FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: _spots,
                  isCurved: true,
                  color: const Color(0xFFC31C42),
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
              minY: 0,
              maxY: 1,
              minX: _spots.length > _maxDataPoints ? (_timeCounter - _maxDataPoints) : 0,
              maxX: _spots.length > _maxDataPoints ? _timeCounter : _maxDataPoints.toDouble(),
            ),
          ),
        ),
        Text(_formatDuration(_duration), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300)),
        Column(
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: FloatingActionButton(
                onPressed: _toggleRecording,
                backgroundColor: _isRecording ? Colors.white : const Color(0xFFC31C42),
                foregroundColor: _isRecording ? const Color(0xFFC31C42) : Colors.white,
                shape: const CircleBorder(),
                elevation: 8,
                child: Icon(_isRecording ? Icons.stop : Icons.mic, size: 50),
              ),
            ),
            const SizedBox(height: 20),
            Text(_isRecording ? "Tap to Stop" : "Tap to Start", style: const TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      ],
    );
  }

  Widget _buildPermissionsDeniedUI() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text('Microphone Permission Required', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          const Text(
            'CardioScope needs access to your microphone to record heart sounds.',
            style: TextStyle(fontSize: 16, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Open App Settings'),
            onPressed: openAppSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC31C42),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
          ),
        ],
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _duration = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _duration = Duration(seconds: _duration.inSeconds + 1));
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
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
            labelText: "Patient Name",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) Navigator.of(context).pop(name);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (patientName == null || patientName.isEmpty) {
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return;
    }

    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) throw Exception("Cannot access storage");
      
      final storagePath = '${directory.path}/CardioScope/heart_sounds';
      final storageDir = Directory(storagePath);
      if (!await storageDir.exists()) await storageDir.create(recursive: true);

      final date = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
      final safeName = patientName.replaceAll(RegExp(r'\s+'), "_");
      final newPath = "$storagePath/${safeName}_$date.wav";
      final tempFile = File(tempPath);
      await tempFile.copy(newPath);
      await tempFile.delete();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ResultsPage(filePath: newPath, patientName: patientName),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving file: $e')));
    }
  }
}