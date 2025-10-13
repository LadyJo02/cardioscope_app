// 📁 lib/pages/record.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cardioscope_app/pages/report_generated.dart';
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

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  // === Recording config ===
  static const int _recordingDurationInSeconds = 5;
  static const int _visiblePoints = 1000; // ~ rolling window width (affects scroll speed)
  static const double _smoothAlpha = 0.15; // EMA smoothing strength for samples

  final FlutterSoundRecorder _dataStreamer = FlutterSoundRecorder();
  final file_recorder.AudioRecorder _fileRecorder = file_recorder.AudioRecorder();
  final TfliteService _tfliteService = TfliteService();
  final db = DatabaseHelper.instance;
  final storage = StorageService();

  StreamController<Uint8List>? _recordingDataController;
  StreamSubscription? _dataSubscription;

  bool _isRecording = false;
  bool _isProcessing = false;

  // Rolling chart data
  List<FlSpot> _spots = [];
  double _timeCounter = 0; // we treat this like an index; not seconds
  double _displayGain = 1.0; // soft auto-gain with decay for stable visual amplitude

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
    // Load only preprocessor for visualization; classifier loads dynamically in runInference
    await _tfliteService.loadModels(loadClassifier: false);
    await _loadCurrentPatient();
  }

  Future<void> _loadCurrentPatient() async {
    final patientId = await storage.getCurrentPatient();
    if (patientId != null) {
      final patient = await db.getPatientById(patientId);
      if (patient != null && mounted) {
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

  Future<void> _toggleRecording() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final hasPermission = await _fileRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission required.')),
      );
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
      _displayGain = 1.0;
    });

    _startTimer();
    _startAutoStopTimer();
  }

  void _startAutoStopTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer(
      const Duration(seconds: _recordingDurationInSeconds),
      () {
        if (_isRecording && mounted) _toggleRecording();
      },
    );
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    if (!_dataStreamer.isRecording) return;

    await _dataStreamer.stopRecorder();
    final path = await _fileRecorder.stop();

    // 🚫 Restrict short recordings (under 5 seconds)
    if (_duration.inSeconds < _recordingDurationInSeconds) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Recording Too Short"),
          content: const Text(
            "Please record at least $_recordingDurationInSeconds seconds "
            "to ensure accurate heart sound analysis.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      if (!mounted) return;

      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      setState(() {
        _isProcessing = false;
        _isRecording = false;
      });
      return;
    }

    _dataSubscription?.cancel();
    _recordingDataController?.close();
    _stopTimer();

    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });

    if (path != null) {
      // Generate both outputs
      final aiResult = await _tfliteService.runInference(filePath: path);
      final melPng = await _tfliteService.generateMelImageBytes(path);

      if (!mounted) return;
      setState(() => _isProcessing = false);

      await _handleRecordingSave(path, aiResult, melPng);
    } else {
      setState(() => _isProcessing = false);
    }
  }

  Future<Map<String, dynamic>?> _showPatientDialog({bool switchMode = false}) async {
    if (!mounted) return null;
    return await showGeneralDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: switchMode,
      barrierLabel: switchMode ? 'Switch Patient' : 'Patient Info',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => PatientFormDialog(isSwitchMode: switchMode),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.1), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
    );
  }

  Future<void> _switchPatient() async {
    final result = await _showPatientDialog(switchMode: true);
    if (!mounted) return;

    if (result != null) {
      setState(() => _currentPatient = result);
      await storage.setCurrentPatient(result['patient_id']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Switched to patient: ${result['name']}')),
      );
    }
  }

  Future<void> _handleRecordingSave(
    String tempPath,
    Map<String, dynamic>? aiResult,
    Uint8List? melPng,
  ) async {
    try {
      Map<String, dynamic>? patient = _currentPatient;
      if (patient == null) {
        patient = await _showPatientDialog();
        if (patient == null) {
          final tempFile = File(tempPath);
          if (await tempFile.exists()) await tempFile.delete();
          return;
        }
        if (!mounted) return;
        setState(() => _currentPatient = patient);
      }

      final patientId = patient['patient_id'] ?? patient['id'];
      String? folderPath = patient['folder_path'];

      if (folderPath == null || folderPath.isEmpty) {
        final basePath = await storage.getSavedPath();
        if (basePath == null) throw Exception("No main CardioScope folder found.");
        folderPath = await storage.createPatientFolder(basePath, patient['name']);
        await db.updatePatientFolderPath(patientId, folderPath);
      }

      await storage.setCurrentPatient(patientId);
      final patientName = patient['name'] ?? 'Unknown';
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
            probabilities: aiResult?['probabilities'] as Map<String, dynamic>? ?? {},
            patientBirthday: patient?['birthday']?.toString(),
            melPngBytes: melPng,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error saving record: $e')));
    }
  }

  // === Real-time rolling PCG waveform ===
  void _updateWaveform(Uint8List rawData) {
    if (!mounted) return;

    // PCM16 -> double [-1, 1]
    final bd = rawData.buffer.asByteData();
    final tmp = <double>[];
    for (int i = 0; i < rawData.lengthInBytes; i += 2) {
      tmp.add(bd.getInt16(i, Endian.little) / 32768.0);
    }

    // Downsample with simple average + EMA smoothing to reduce jitter
    const int step = 100; // larger = slower scroll (~25ms per point at 4kHz)
    const double timeStep = 0.007; // seconds per plotted point (7 ms visual rate)
    
    final reduced = <double>[];
    double prev = 0.0;
    for (int i = 0; i < tmp.length; i += step) {
      double avg = 0;
      int count = 0;
      for (int j = i; j < i + step && j < tmp.length; j++) {
        avg += tmp[j];
        count++;
      }
      avg /= (count == 0 ? 1 : count);

      // Exponential smoothing (softens sharp transitions)
      final smoothed = prev + _smoothAlpha * (avg - prev);
      prev = smoothed;
      reduced.add(smoothed);
    }

    // Soft auto-gain with slow response (prevents jumpy scaling)
    final peak = reduced.fold(1e-6, (double m, e) => math.max(m, e.abs()));
    double targetGain = 1 / (peak * 1.2); // leave headroom
    targetGain = targetGain.clamp(0.8, 6.0); // keep within sensible bounds
    _displayGain = 0.90 * _displayGain + 0.10 * targetGain;
    

    setState(() {
      for (final s in reduced) {
        _timeCounter += timeStep;
        final value = (s * _displayGain).clamp(-1.0, 1.0);
        _spots.add(FlSpot(_timeCounter, value));
      }

       // Keep last few seconds visible (like hospital monitor)
      const int maxVisible = 1000;
      if (_spots.length > _visiblePoints) {
        _spots = _spots.sublist(_spots.length - maxVisible);
      }
    });
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _duration += const Duration(seconds: 1));
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
    final instructionText = _isRecording
        ? "Recording... (stops in $_recordingDurationInSeconds s)"
        : "Tap to Start";

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Heart Sound', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          children: [
            _buildPatientInfoCard(),
            const SizedBox(height: 8),
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
                        ? const CircularProgressIndicator(color: AppColors.primary)
                        : Icon(
                            _isRecording ? Icons.stop_rounded : Icons.mic,
                            color: _isRecording ? AppColors.primary : Colors.white,
                            size: 50,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(instructionText,
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

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
          margin: const EdgeInsets.symmetric(horizontal: 12.0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(8),
                blurRadius: 8,
                offset: const Offset(0, 3),
              )
            ],
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
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
              ]),
              TextButton.icon(
                onPressed: isDisabled ? null : _switchPatient,
                icon: Icon(Icons.swap_horiz_rounded,
                    color: isDisabled ? Colors.grey : AppColors.primary),
                label: Text(
                  hasPatient ? "Switch" : "Add",
                  style: TextStyle(color: isDisabled ? Colors.grey : AppColors.primary),
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
          Text('Recording Guidelines',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(height: 180, child: Image.asset('assets/images/mitral_area_guide.png')),
          const SizedBox(height: 24),
          _buildGuidelineItem(Icons.mic_off_rounded, 'Ensure a quiet environment.'),
          _buildGuidelineItem(Icons.place_rounded,
              'Place stethoscope at the mitral area (as shown).'),
          _buildGuidelineItem(Icons.timer_rounded,
              'Recording will last $_recordingDurationInSeconds seconds.'),
          _buildGuidelineItem(
              Icons.person_rounded, 'Ensure the patient remains still during recording.'),
        ],
      ),
    );
  }

  Widget _buildRecordingView() {
    final double minX = _spots.isNotEmpty ? math.max(0, _spots.last.x - _visiblePoints) : 0;
    final double maxX = _spots.isNotEmpty ? _spots.last.x : _visiblePoints.toDouble();

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
                    child: Text('Waiting for audio data...',
                        style: TextStyle(color: Colors.grey)))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LineChart(
                      LineChartData(
                        titlesData: const FlTitlesData(show: false),
                        // Subtle horizontal grid for medical look
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 0.5,
                          getDrawingHorizontalLine: (v) => FlLine(
                            color: Colors.grey.withValues(alpha: 0.12),
                            strokeWidth: 0.6,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        clipData: const FlClipData.all(),
                        minY: -1.2,
                        maxY: 1.2,
                        minX: minX,
                        maxX: maxX,
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _spots,
                            isCurved: true,
                            color: AppColors.primary,
                            barWidth: 2.0,
                            isStrokeCapRound: true,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
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

  Widget _buildGuidelineItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4))),
        ],
      ),
    );
  }
}
