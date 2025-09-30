// lib/pages/record.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cardioscope_app/services/tflite_service.dart';
import 'package:cardioscope_app/widgets/custom_button.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart' as file_recorder;

import 'report_generated.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});
  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final FlutterSoundRecorder _dataStreamer = FlutterSoundRecorder();
  final file_recorder.AudioRecorder _fileRecorder = file_recorder.AudioRecorder();
  final TfliteService _tfliteService = TfliteService();

  StreamController<Uint8List>? _recordingDataController;
  StreamSubscription? _dataSubscription;

  bool _isRecording = false;
  bool _isProcessing = false;
  List<FlSpot> _spots = [];
  double _timeCounter = 0;
  final int _maxDataPoints = 500;

  Timer? _timer;
  Duration _duration = Duration.zero;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _dataStreamer.openRecorder();
    await _tfliteService.loadModel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordingTimer?.cancel();
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
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required.')));
      }
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
    _dataSubscription = _recordingDataController!.stream.listen(_updateWaveform);

    await _dataStreamer.startRecorder(
        toStream: _recordingDataController!.sink, codec: Codec.pcm16);

    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/temp_recording.wav';

    const recordConfig = file_recorder.RecordConfig(
      encoder: file_recorder.AudioEncoder.wav,
      sampleRate: 4000,
      numChannels: 1,
    );

    await _fileRecorder.start(recordConfig, path: tempPath);

    setState(() {
      _isRecording = true;
      _spots = []; // This clears the spots, causing the error before the fix
      _timeCounter = 0;
    });

    _startTimer();
    _startAutoStopTimer();
  }

  void _startAutoStopTimer() {
    _recordingTimer?.cancel();
    const recordingDuration = Duration(seconds: 4);
    
    _recordingTimer = Timer(recordingDuration, () {
      if (_isRecording && mounted) {
        _toggleRecording();
      }
    });
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    if (!_dataStreamer.isRecording) return;

    await _dataStreamer.stopRecorder();
    final path = await _fileRecorder.stop();

    _dataSubscription?.cancel();
    _recordingDataController?.close();
    _stopTimer();

    if (mounted) {
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });

      if (path != null) {
        final result = await _tfliteService.runInference(filePath: path);
        
        if (mounted) {
          setState(() => _isProcessing = false);
          await _askPatientNameAndSave(path, result);
        }
      } else {
        setState(() => _isProcessing = false);
      }
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
          _timeCounter += 1;
        }
        while (_spots.length > _maxDataPoints) {
          _spots.removeAt(0);
        }
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final String instructionText = _isRecording 
        ? "Recording... (stops in 4s)" 
        : "Tap to Start";

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Heart Sound',
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: _isRecording ? _buildRecordingView() : _buildGuidelinesView(),
            ),
            
            Hero(
              tag: 'record_button_hero',
              child: GestureDetector(
                onTap: _toggleRecording,
                child: Container(
                  width: ButtonConstants.micButtonSize,
                  height: ButtonConstants.micButtonSize,
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.white : const Color(0xFFC31C42),
                    shape: BoxShape.circle,
                    border: _isRecording
                        ? Border.all(color: const Color(0xFFC31C42), width: 4)
                        : null,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withAlpha(40),
                          blurRadius: 8,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Center(
                    child: _isProcessing
                        ? const CircularProgressIndicator(color: Color(0xFFC31C42))
                        : Icon(
                            _isRecording ? Icons.stop_rounded : Icons.mic,
                            color:
                                _isRecording ? const Color(0xFFC31C42) : Colors.white,
                            size: 50),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(instructionText,
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidelinesView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Recording Guidelines',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: Image.asset('assets/images/mitral_area_guide.png'),
          ),
          const SizedBox(height: 24),
          _buildGuidelineItem(
            context,
            Icons.mic_off_rounded,
            'Ensure a quiet environment.',
          ),
          _buildGuidelineItem(
            context,
            Icons.place_rounded,
            'Place stethoscope at the mitral area (as shown).',
          ),
          _buildGuidelineItem(
            context,
            Icons.timer_rounded,
            'The recording will last 4 seconds for a complete analysis.',
          ),
          _buildGuidelineItem(
            context,
            Icons.person_rounded,
            'Ensure the patient remains still during recording.',
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 24.0),
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(20),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            // **CHART FIX: Check if _spots is empty before building the chart**
            child: _spots.isEmpty
                ? const Center(
                    child: Text(
                      'Waiting for audio data...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ClipRRect(
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
                        minY: -1.0,
                        maxY: 1.0,
                        minX: _spots.first.x,
                        maxX: _spots.last.x,
                        lineTouchData: const LineTouchData(enabled: false),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        Text(_formatDuration(_duration),
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300)),
      ],
    );
  }

  Widget _buildGuidelineItem(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).primaryColor, size: 24),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4))),
        ],
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

  void _stopTimer() => _timer?.cancel();

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$mm:$ss";
  }

  Future<void> _askPatientNameAndSave(String tempPath, Map<String, dynamic>? aiResult) async {
    final nameController = TextEditingController();
    final patientName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text("Save Recording"),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Patient Name"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(null), child: const Text("Cancel")),
          ElevatedButton(onPressed: () {
            final n = nameController.text.trim();
            if (n.isNotEmpty) Navigator.of(c).pop(n);
          }, child: const Text("Save")),
        ],
      ),
    );

    if (patientName == null || patientName.isEmpty) {
      final t = File(tempPath);
      if (await t.exists()) await t.delete();
      return;
    }

    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Please select a folder to save the report:',
      );

      if (selectedDirectory == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Save operation cancelled.')));
        }
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
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (c) => ReportGeneratedPage(
          patientName: patientName,
          filePath: newPath,
          recordedDate: DateTime.now(),
          classification: aiResult?['label'] ?? 'Error',
          confidence: aiResult?['confidence'] ?? 0.0,
        ),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error saving file: $e')));
      }
    }
  }
}