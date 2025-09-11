// lib/pages/record.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as file_recorder;

import 'results.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final FlutterSoundRecorder _dataStreamer = FlutterSoundRecorder();
  final file_recorder.AudioRecorder _fileRecorder = file_recorder.AudioRecorder();
  StreamController<Uint8List>? _recordingDataController;
  StreamSubscription? _dataSubscription;

  bool _isRecording = false;
  bool _isProcessing = false;
  List<FlSpot> _spots = [];
  double _timeCounter = 0;
  final int _maxDataPoints = 500;

  Timer? _timer;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _dataStreamer.openRecorder();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dataSubscription?.cancel();
    _recordingDataController?.close();
    _dataStreamer.closeRecorder();
    _fileRecorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final hasPermission = await _fileRecorder.hasPermission();
    if (!mounted) {
      setState(() => _isProcessing = false);
      return;
    }

    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission required.')));
      setState(() => _isProcessing = false);
      return;
    }

    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }

    if (mounted) setState(() => _isProcessing = false);
  }

  Future<void> _startRecording() async {
    _recordingDataController = StreamController<Uint8List>();
    _dataSubscription = _recordingDataController!.stream.listen((data) {
      _updateWaveform(data);
    });

    await _dataStreamer.startRecorder(
      toStream: _recordingDataController!.sink,
      codec: Codec.pcm16,
    );

    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/temp_recording.wav';
    await _fileRecorder.start(const file_recorder.RecordConfig(encoder: file_recorder.AudioEncoder.wav), path: tempPath);

    setState(() {
      _isRecording = true;
      _spots = [];
      _timeCounter = 0;
    });
    _startTimer();
  }

  Future<void> _stopRecording() async {
    if (!_dataStreamer.isRecording) return;
    await _dataStreamer.stopRecorder();
    final path = await _fileRecorder.stop();
    _dataSubscription?.cancel();
    _recordingDataController?.close();
    _stopTimer();

    if (mounted) {
      setState(() => _isRecording = false);
      if (path != null) await _askPatientNameAndSave(path);
    }
  }

  void _updateWaveform(Uint8List rawData) {
    final byteData = rawData.buffer.asByteData();
    final samples = <double>[];
    for (int i = 0; i < rawData.lengthInBytes; i += 2) {
      samples.add(byteData.getInt16(i, Endian.little) / 32768.0);
    }
    
    if (mounted) {
      setState(() {
        for (var sample in samples) {
          _spots.add(FlSpot(_timeCounter, sample));
          _timeCounter++;
        }
        while (_spots.length > _maxDataPoints) {
          _spots.removeAt(0);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Heart Sound', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Container(
              height: 150,
              width: MediaQuery.of(context).size.width * 0.9,
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:
0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LineChart(
                  LineChartData(
                    titlesData: const FlTitlesData(show: false),
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
                    minY: -1.0, maxY: 1.0,
                    minX: _spots.isNotEmpty ? _spots.first.x : 0,
                    maxX: _spots.isNotEmpty ? _spots.last.x : 0,
                    lineTouchData: const LineTouchData(enabled: false),
                  ),
                ),
              ),
            ),
            Text(_formatDuration(_duration), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300)),
            Hero(
              tag: 'record_button_hero',
              child: GestureDetector(
                onTap: _toggleRecording,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.white : const Color(0xFFC31C42),
                    shape: BoxShape.circle,
                    border: _isRecording ? Border.all(color: const Color(0xFFC31C42), width: 4) : null,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.15), blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: Center(
                    child: _isProcessing
                        ? const CircularProgressIndicator(color: Color(0xFFC31C42))
                        : Icon(
                            _isRecording ? Icons.stop_rounded : Icons.mic,
                            color: _isRecording ? const Color(0xFFC31C42) : Colors.white,
                            size: 40,
                          ),
                  ),
                ),
              ),
            ),
            Text(_isRecording ? "Tap to Stop" : "Tap to Start", style: const TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _duration = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _duration += const Duration(seconds: 1));
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
        backgroundColor: const Color(0xFFFFFFFF),
        title: const Text("Save Recording"),
        content: TextField(controller: nameController, autofocus: true, decoration: const InputDecoration(labelText: "Patient Name")),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text("Cancel")),
          ElevatedButton(onPressed: () {
            final name = nameController.text.trim();
            if (name.isNotEmpty) Navigator.of(context).pop(name);
          }, child: const Text("Save")),
        ],
      ),
    );

    if (patientName == null || patientName.isEmpty) {
      final tempFile = File(tempPath);
      if (await tempFile.exists()) await tempFile.delete();
      return;
    }

    try {
      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Please select a folder to save the report:');
      if (selectedDirectory == null) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save operation cancelled.')));
        return;
      }
      final storagePath = '$selectedDirectory/CardioScope/heart_sounds';
      final storageDir = Directory(storagePath);
      if (!await storageDir.exists()) await storageDir.create(recursive: true);

      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final time = DateFormat('HHmmss').format(DateTime.now());
      final safeName = patientName.replaceAll(RegExp(r'\s+'), "_");
      final newFileName = "${safeName}_${date}_$time.wav";
      final newPath = "$storagePath/$newFileName";

      final tempFile = File(tempPath);
      await tempFile.copy(newPath);
      await tempFile.delete();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => ResultsPage(filePath: newPath, patientName: patientName)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving file: $e')));
    }
  }
}