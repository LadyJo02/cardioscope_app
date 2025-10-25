// 📁 lib/pages/record.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:cardioscope_app/pages/report_generated.dart';
import 'package:cardioscope_app/services/storage_service.dart';
import 'package:cardioscope_app/services/tflite_service.dart';
import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:cardioscope_app/utils/latency_debug.dart';
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
  static const int _recordingDurationInSeconds = 5;
  static const int _visiblePoints = 1000;
  static const double _smoothAlpha = 0.15;

  final FlutterSoundRecorder _dataStreamer = FlutterSoundRecorder();
  final file_recorder.AudioRecorder _fileRecorder = file_recorder.AudioRecorder();
  final TfliteService _tfliteService = TfliteService();
  final db = DatabaseHelper.instance;
  final storage = StorageService();

  StreamController<Uint8List>? _recordingDataController;
  StreamSubscription? _dataSubscription;

  bool _isRecording = false;
  bool _isProcessing = false;

  // Receiver connection status
  StreamSubscription<Set<AudioDevice>>? _devicesSubscription;
  bool _isUsbMicConnected = false;

  // Waveform state
  List<FlSpot> _spots = [];
  double _timeCounter = 0;
  double _displayGain = 1.0;

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
    await _tfliteService.loadModels(loadClassifier: false);
    await _loadCurrentPatient();
    await _initAudioSession();
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

  Future<void> _initAudioSession() async {
    LatencyDebug.start("🔌 TXRX", "Initializing USB-C audio session");
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    LatencyDebug.mark("🔌 TXRX", "AudioSession configured");
    _devicesSubscription = session.devicesStream.listen((devices) {
      _checkConnectedDevices(devices.toList());
    });
    _checkConnectedDevices((await session.getDevices()).toList());
    LatencyDebug.end("🔌 TXRX", "Session + device stream initialized");
  }
    

  void _checkConnectedDevices(List<AudioDevice> devices) {
    final usbDevice = devices.firstWhere(
      (d) => d.name.toLowerCase().contains('usb'),
      orElse: () => AudioDevice(
        id: '',
        name: '',
        type: AudioDeviceType.unknown,
        isInput: false,
        isOutput: false,
      ),
    );

    if (mounted) {
      final wasConnected = _isUsbMicConnected;
      setState(() {
        _isUsbMicConnected = usbDevice.id.isNotEmpty;
      });

      // 🔔 show small toast if status changes
      if (_isUsbMicConnected != wasConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isUsbMicConnected
                  ? 'CardioScope receiver connected'
                  : 'CardioScope receiver disconnected',
            ),
            backgroundColor: _isUsbMicConnected ? AppColors.success : AppColors.warning,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordingTimer?.cancel();
    _dataSubscription?.cancel();
    _devicesSubscription?.cancel();
    _recordingDataController?.close();
    _dataStreamer.closeRecorder();
    _fileRecorder.dispose();
    super.dispose();
  }

  // === Main recording logic ===
  Future<void> _toggleRecording() async {
    LatencyDebug.start("🎙 Record", _isRecording ? "Stopping recording" : "User tapped record");
    if (_isProcessing) return;
    LatencyDebug.mark("🎙 Record", _isRecording ? "Stopped command issued" : "Started command issued");
    setState(() => _isProcessing = true);

    if (!_isUsbMicConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect the CardioScope receiver first.')),
      );
      setState(() => _isProcessing = false);
      return;
    }

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
    LatencyDebug.mark("🎙 Record", "Recorder initializing");
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
    LatencyDebug.mark("🎙 Record", "Recorder fully started (file + stream ready)");

    setState(() {
      _isRecording = true;
      _spots = [];
      _timeCounter = 0;
      _duration = Duration.zero;
      _displayGain = 1.0;
    });

    LatencyDebug.end("🎙 Record", "Recording officially running");
    _startTimer();
    _startAutoStopTimer();
  }

  // 🕒 Automatically stops recording after the defined duration
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
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    LatencyDebug.resetSession(sessionId);
    LatencyDebug.start("🎙 Stop", "Stopping recording session");
    _recordingTimer?.cancel();
    if (!_dataStreamer.isRecording) return;

    await _dataStreamer.stopRecorder();
    final path = await _fileRecorder.stop();
    LatencyDebug.mark("🎙 Stop", "File saved at $path");

    if (path == null) return;

    _dataSubscription?.cancel();
    _recordingDataController?.close();
    _stopTimer();

    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });

    final aiResult = await _tfliteService.runInference(filePath: path);
    final melPng = await _tfliteService.generateMelImageBytes(path);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    await _handleRecordingSave(path, aiResult, melPng);
    LatencyDebug.end("🎙 Stop", "Recording + postprocessing complete");
  } 

  Future<void> _handleRecordingSave(
      String tempPath, Map<String, dynamic>? aiResult, Uint8List? melPng) async {
      LatencyDebug.start("📦 Save", "Begin saving & DB pipeline");
    try {
      Map<String, dynamic>? patient = _currentPatient;
      if (patient == null) {
        patient = await _showPatientDialog();
        if (patient == null) return;
        setState(() => _currentPatient = patient);
      }

      final patientId = patient['patient_id'] ?? patient['id'];
      String? folderPath = patient['folder_path'];
      

      if (folderPath == null || folderPath.isEmpty) {
        final basePath = await storage.getSavedPath();
        folderPath = await storage.createPatientFolder(basePath!, patient['name']);
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
      LatencyDebug.mark("📦 Save", "WAV copied to $newPublicPath");
      await tempFile.delete();

      final recordDate = DateTime.now();
      final recordId = await db.insertRecord({
        "patient_id": patientId,
        "file_path": newPublicPath,
        "record_date": recordDate.toIso8601String(),
      });
      LatencyDebug.mark("📦 Save", "Record inserted into heart_sound_records");

      if (aiResult != null) {
        await db.insertAnalysis({
          "record_id": recordId,
          "diagnosis": aiResult['label'] ?? "Error",
          "probabilities":
              aiResult['probabilities'] != null ? jsonEncode(aiResult['probabilities']) : "{}",
          "analysis_date": DateTime.now().toIso8601String(),
        });
      }
      LatencyDebug.mark("📦 Save", "AI result stored in mitral_valve_analysis");

      if (!mounted) return;
      LatencyDebug.end("📦 Save", "Pipeline finished — report ready for display");
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
            symptoms: patient?['symptoms']?.toString(),
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

  // ✅ Updated _showPatientDialog — allows editing symptoms before recording
// ✅ Simplified and fixed _showPatientDialog using showDialog (returns proper result)
Future<Map<String, dynamic>?> _showPatientDialog({bool switchMode = false}) async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: switchMode,
    builder: (_) => PatientFormDialog(isSwitchMode: switchMode),
  );

  if (result != null) {
    final db = DatabaseHelper.instance;
    final patientId = result['patient_id'];
    await db.database.then((conn) {
      conn.update(
        'patients',
        {'symptoms': result['symptoms'] ?? ''},
        where: 'patient_id = ?',
        whereArgs: [patientId],
      );
    });

    await _loadCurrentPatient();
  }

  return result;
}


  // 🩺 Smart patient logic: "Add" for first-time, "Switch" if existing
Future<void> _switchPatient() async {
  final hasExisting = _currentPatient != null;
  final isSwitchMode = hasExisting;

  final result = await _showPatientDialog(switchMode: isSwitchMode);
  if (result == null) return;

  if (!mounted) return;

  final fresh = await db.getPatientById(result['patient_id']);
  setState(() => _currentPatient = fresh ?? result);
  await storage.setCurrentPatient(result['patient_id']);

  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(isSwitchMode
          ? 'Switched to patient: ${result['name']}'
          : 'Added new patient: ${result['name']}'),
      backgroundColor: AppColors.primary,
      duration: const Duration(seconds: 2),
    ),
  );
}


  // === waveform visualisation ===
  void _updateWaveform(Uint8List rawData) {
    if (_spots.isEmpty) {
  LatencyDebug.mark("🎙 Record", "First waveform chunk received (${rawData.lengthInBytes} bytes)");
}
    if (!mounted) return;
    final bd = rawData.buffer.asByteData();
    final tmp = <double>[];
    for (int i = 0; i < rawData.lengthInBytes; i += 2) {
      tmp.add(bd.getInt16(i, Endian.little) / 32768.0);
    }

    const int step = 100;
    const double timeStep = 0.007;
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
      final smoothed = prev + _smoothAlpha * (avg - prev);
      prev = smoothed;
      reduced.add(smoothed);
    }

    final peak = reduced.fold(1e-6, (double m, e) => math.max(m, e.abs()));
    double targetGain = 1 / (peak * 1.2);
    targetGain = targetGain.clamp(0.8, 6.0);
    _displayGain = 0.9 * _displayGain + 0.1 * targetGain;

    setState(() {
      for (final s in reduced) {
        _timeCounter += timeStep;
        final value = (s * _displayGain).clamp(-1.0, 1.0);
        _spots.add(FlSpot(_timeCounter, value));
      }
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

  // === UI ===
  @override
  Widget build(BuildContext context) {
    final instructionText =
        _isRecording ? "Recording... (stops in $_recordingDurationInSeconds s)" : "Tap to Start";

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        title: Text(
          'Record Heart Sound',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary, // ✅ consistent white text
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          children: [
            _buildReceiverStatusBanner(),
            const SizedBox(height: 6),
            _buildPatientInfoCard(),
            const SizedBox(height: 8),
            Expanded(
              child: _isRecording ? _buildRecordingView() : _buildGuidelinesView(),
            ),
            Hero(
              tag: 'record_button_hero',
              child: GestureDetector(
                onTap: _toggleRecording,
                child: Opacity(
                  opacity: _isUsbMicConnected ? 1 : 0.6,
                  child: Container(
                    width: ButtonConstants.micButtonSize,
                    height: ButtonConstants.micButtonSize,
                    decoration: BoxDecoration(
                      color: _isRecording 
                          ? AppColors.primary
                          :Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
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
                              color: _isRecording ? AppColors.primary : Theme.of(context).colorScheme.onSurface,
                              size: 50,
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(instructionText, style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // === Small receiver banner ===
  Widget _buildReceiverStatusBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: _isUsbMicConnected
            ? AppColors.success.withValues(alpha: 0.15)
            : AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isUsbMicConnected ? AppColors.success : AppColors.warning,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isUsbMicConnected ? Icons.usb_rounded : Icons.usb_off_rounded,
            color: _isUsbMicConnected ? AppColors.success : AppColors.warning,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            _isUsbMicConnected ? "Receiver Connected" : "Receiver Disconnected",
            style: TextStyle(
              color: _isUsbMicConnected ? AppColors.success : AppColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // === Reuse of old UI cards (patient + waveform) ===
  Widget _buildPatientInfoCard() {
    final name = _currentPatient?['name'];
    final hasPatient = name != null && name.isNotEmpty;
    final isDisabled = _isRecording || _isProcessing;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final symptoms = _currentPatient?['symptoms']?.toString() ?? '';

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isDisabled ? 0.5 : 1.0,
      child: IgnorePointer(
        ignoring: isDisabled,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12.0),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ]),
                  TextButton.icon(
                    onPressed: isDisabled ? null : _switchPatient,
                    icon: Icon(
                      Icons.swap_horiz_rounded,
                      color: isDisabled
                          ? Theme.of(context).colorScheme.onSurface
                          : AppColors.primary,
                    ),
                    label: Text(
                      hasPatient ? "Switch" : "Add",
                      style: TextStyle(
                        color: isDisabled
                            ? Theme.of(context).colorScheme.onSurface
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              if (symptoms.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  "Symptoms: $symptoms",
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
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
          _buildGuidelineItem(
              Icons.timer_rounded, 'Recording will last $_recordingDurationInSeconds seconds.'),
          _buildGuidelineItem(Icons.person_rounded,
              'Ensure the patient remains still during recording.'),
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
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: _spots.isEmpty
                ? Center(
                    child:
                        Text('Waiting for audio data...', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LineChart(
                      LineChartData(
                        titlesData: const FlTitlesData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 0.5,
                          getDrawingHorizontalLine: (v) => FlLine(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
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
