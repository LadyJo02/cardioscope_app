import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cardioscope_app/services/storage_service.dart';
import 'package:cardioscope_app/services/tflite_service.dart';
import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:cardioscope_app/widgets/custom_button.dart';
import 'package:cardioscope_app/widgets/patient_form_dialog.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart' as file_recorder;

import '../database_helper.dart';
import 'report_generated.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  static const int _recordingDurationInSeconds = 5;

  final FlutterSoundRecorder _dataStreamer = FlutterSoundRecorder();
  final file_recorder.AudioRecorder _fileRecorder = file_recorder.AudioRecorder();
  final TfliteService _tfliteService = TfliteService();
  final db = DatabaseHelper.instance;
  final storage = StorageService();

  StreamController<Uint8List>? _recordingDataController;
  StreamSubscription? _dataSubscription;

  bool _isRecording = false;
  bool _isProcessing = false;
  List<FlSpot> _spots = [];
  double _timeCounter = 0;
  final int _maxDataPoints = 500;

  Timer? _timer;
  Timer? _recordingTimer;
  Duration _duration = Duration.zero;

  Map<String, dynamic>? _currentPatient;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _dataStreamer.openRecorder();
    await _tfliteService.loadModel();
    await _loadCurrentPatient();
  }

  Future<void> _loadCurrentPatient() async {
    final patientId = await storage.getCurrentPatient();
    if (patientId != null) {
      final patient = await db.getPatientById(patientId);
      if (patient != null) {
        setState(() => _currentPatient = patient);
      }
    }
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

  // 🔴 Start / Stop Recording Toggle
  Future<void> _toggleRecording() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final hasPermission = await _fileRecorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required.')),
        );
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

  // 🎙️ Start recording
  Future<void> _startRecording() async {
    _recordingDataController = StreamController<Uint8List>();
    _dataSubscription = _recordingDataController!.stream.listen(_updateWaveform);

    await _dataStreamer.startRecorder(
      toStream: _recordingDataController!.sink,
      codec: Codec.pcm16,
    );

    final tempDir = await Directory.systemTemp.createTemp();
    final tempPath = '${tempDir.path}/temp_recording.wav';

    const recordConfig = file_recorder.RecordConfig(
      encoder: file_recorder.AudioEncoder.wav,
      sampleRate: 4000,
      numChannels: 1,
    );

    await _fileRecorder.start(recordConfig, path: tempPath);

    setState(() {
      _isRecording = true;
      _spots = [];
      _timeCounter = 0;
      _duration = Duration.zero;
    });

    _startTimer();
    _startAutoStopTimer();
  }

  void _startAutoStopTimer() {
    _recordingTimer?.cancel();
    const recordingDuration = Duration(seconds: _recordingDurationInSeconds);

    _recordingTimer = Timer(recordingDuration, () {
      if (_isRecording && mounted) {
        _toggleRecording();
      }
    });
  }

  // 🛑 Stop recording
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
          await _handleRecordingSave(path, result);
        }
      } else {
        setState(() => _isProcessing = false);
      }
    }
  }

  // 🧩 Dialog for new patient entry
  Future<Map<String, dynamic>?> _showAnimatedPatientDialog() async {
    return await showGeneralDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Patient Info',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const PatientFormDialog(),
      transitionBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.1), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        );
      },
    );
  }

  // 🧩 Dialog for switching existing patient (locked name)
  Future<void> _switchPatient() async {
    final result = await showGeneralDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Switch Patient',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const PatientFormDialog(isSwitchMode: true),
      transitionBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.1), end: Offset.zero)
                .animate(anim),
            child: child,
          ),
        );
      },
    );

    if (result != null) {
      setState(() => _currentPatient = result);
      await storage.setCurrentPatient(result['patient_id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switched to patient: ${result['name']}')),
      );
    }
  }

  // 💾 Save recording and analysis
  Future<void> _handleRecordingSave(
      String tempPath, Map<String, dynamic>? aiResult) async {
    try {
      Map<String, dynamic>? patient = _currentPatient;
      if (patient == null) {
        patient = await _showAnimatedPatientDialog();
        if (patient == null) {
          final tempFile = File(tempPath);
          if (await tempFile.exists()) await tempFile.delete();
          return;
        }
        setState(() => _currentPatient = patient);
      }

      final patientId = patient['patient_id'] ?? patient['id'];

      // ✅ Ensure folder exists or create it
      String? folderPath = patient['folder_path'];
      if (folderPath == null || folderPath.isEmpty) {
        final basePath = await storage.getSavedPath();
        if (basePath == null) {
          throw Exception("No main CardioScope folder found.");
        }

        folderPath =
            await storage.createPatientFolder(basePath, patient['name']);
        await db.updatePatientFolderPath(patientId, folderPath);
      }

      // ✅ Remember selected patient
      await storage.setCurrentPatient(patientId);

      final patientName = patient['name'];
      final safeName = patientName.replaceAll(RegExp(r'[^a-zA-Z0-9_ ]'), "_");

      final date = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final newFileName = "${safeName}_${patientId}_$date.wav";
      final newPublicPath = "$folderPath/$newFileName";

      final tempFile = File(tempPath);
      await tempFile.copy(newPublicPath);
      await tempFile.delete();

      final recordDate = DateTime.now();
      final recordId = await db.insertRecord({
        "patient_id": patientId,
        "file_path": newPublicPath,
        "record_date": recordDate.toIso8601String(),
      });

      if (aiResult != null) {
        await db.insertAnalysis({
          "record_id": recordId,
          "diagnosis": aiResult['label'] ?? "Error",
          "probabilities": aiResult['probabilities'] != null
              ? jsonEncode(aiResult['probabilities'])
              : "{}",
          "analysis_date": DateTime.now().toIso8601String(),
        });
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReportGeneratedPage(
            patientId: patientId,
            patientName: patientName,
            patientAge: patient?['age'] ?? '-',
            patientGender: patient?['gender'] ?? '-',
            filePath: newPublicPath,
            recordedDate: recordDate,
            classification: aiResult?['label'] ?? 'Error',
            probabilities:
                aiResult?['probabilities'] as Map<String, dynamic>? ?? {},
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving record: $e')),
      );
    }
  }

  // ===== Waveform Logic =====
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

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _duration += const Duration(seconds: 1));
    });
  }

  void _stopTimer() => _timer?.cancel();

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$mm:$ss";
  }

  @override
  Widget build(BuildContext context) {
    final String instructionText = _isRecording
        ? "Recording... (stops in $_recordingDurationInSeconds s)"
        : "Tap to Start";

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Record Heart Sound',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        child: Column(
          children: [
            _buildPatientInfoCard(),
            const SizedBox(height: 8),
            Expanded(
              child: _isRecording
                  ? _buildRecordingView()
                  : _buildGuidelinesView(),
            ),
            Hero(
              tag: 'record_button_hero',
              child: GestureDetector(
                onTap: _toggleRecording,
                child: Container(
                  width: ButtonConstants.micButtonSize,
                  height: ButtonConstants.micButtonSize,
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.white : AppColors.primary,
                    shape: BoxShape.circle,
                    border: _isRecording
                        ? Border.all(color: AppColors.primary, width: 4)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(40),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Center(
                    child: _isProcessing
                        ? const CircularProgressIndicator(
                            color: AppColors.primary)
                        : Icon(
                            _isRecording ? Icons.stop_rounded : Icons.mic,
                            color: _isRecording
                                ? AppColors.primary
                                : Colors.white,
                            size: 50,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              instructionText,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // 🧠 New: Patient Info Card for better UX
  Widget _buildPatientInfoCard() {
    final name = _currentPatient?['name'];
    final hasPatient = name != null && name.isNotEmpty;
    final isDisabled = _isRecording || _isProcessing;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isDisabled ? 0.5 : 1.0,
      child: IgnorePointer(
        ignoring: isDisabled,
        child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                hasPatient ? name : "No patient selected",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: hasPatient ? Colors.black : Colors.grey,
                ),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: isDisabled ? null : _switchPatient,
            icon: Icon(
              Icons.swap_horiz_rounded, 
              color: isDisabled
                  ? Colors.grey 
                  : AppColors.primary,
            ),
            label: Text(
              "Switch",
              style: TextStyle(
                color: isDisabled
                    ? Colors.grey 
                    : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
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
              Icons.mic_off_rounded, 'Ensure a quiet environment.'),
          _buildGuidelineItem(Icons.place_rounded,
              'Place stethoscope at the mitral area (as shown).'),
          _buildGuidelineItem(Icons.timer_rounded,
              'The recording will last $_recordingDurationInSeconds seconds.'),
          _buildGuidelineItem(Icons.person_rounded,
              'Ensure the patient remains still during recording.'),
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
                            color: AppColors.primary,
                            barWidth: 1.5,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                        minY: -1.0,
                        maxY: 1.0,
                        minX: _spots.isNotEmpty ? _spots.first.x : 0,
                        maxX: _spots.isNotEmpty ? _spots.last.x : 0,
                        lineTouchData: const LineTouchData(enabled: false),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _formatDuration(_duration),
          style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w300),
        ),
      ],
    );
  }

  Widget _buildGuidelineItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
