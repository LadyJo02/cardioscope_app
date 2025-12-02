// lib/pages/record.dart
// ✅ Secure internal + anonymized backup + consent + latency trace + 5s rule

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
import 'package:cardioscope_app/widgets/patient_form_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart' as record_lib;
import 'package:shared_preferences/shared_preferences.dart';

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
  final record_lib.AudioRecorder _fileRecorder = record_lib.AudioRecorder();
  final TfliteService _tfliteService = TfliteService();
  final db = DatabaseHelper.instance;
  final storage = StorageService();

  StreamController<Uint8List>? _recordingDataController;
  StreamSubscription? _dataSubscription;
  StreamSubscription<Set<AudioDevice>>? _devicesSubscription;

  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isUsbMicConnected = false;

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
      if (mounted) setState(() => _currentPatient = patient);
    }
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    _devicesSubscription = session.devicesStream.listen((devices) {
      _checkConnectedDevices(devices.toList());
    });
    _checkConnectedDevices((await session.getDevices()).toList());
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

    final changed = _isUsbMicConnected != usbDevice.id.isNotEmpty;

    if (mounted) {
      setState(() => _isUsbMicConnected = usbDevice.id.isNotEmpty);

      if (changed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isUsbMicConnected
                  ? 'CardioScope receiver connected'
                  : 'CardioScope receiver disconnected',
            ),
            backgroundColor:
                _isUsbMicConnected ? AppColors.success : AppColors.warning,
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

  // -------------------------------------------------------------
  // ✅ Clinical popup for early stop (<5s)
  Future<bool> _showMinDurationDialog() async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Recording Too Short"),
        content: const Text(
          "A full 5-second recording is required to capture complete heart sound cycles for accurate clinical analysis.\n\nDo you want to continue recording or restart?",
        ),
        actions: [
          TextButton(
            child: const Text("Continue Recording"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text("Restart"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    return res ?? false;
  }
  // -------------------------------------------------------------

  Future<void> _toggleRecording() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);
    LatencyDebug.start("🎙️ Tap", _isRecording ? "Stopping" : "Starting");

    HapticFeedback.selectionClick();

    if (!_isUsbMicConnected) {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 60));
      _toast("Please connect the CardioScope receiver first.");
      setState(() => _isProcessing = false);
      return;
    }

    final hasPermission = await _fileRecorder.hasPermission();
    if (!hasPermission) {
      _toast("Microphone permission required.");
      setState(() => _isProcessing = false);
      await Future.delayed(const Duration(milliseconds: 600));
      openAppSettings();
      return;
    }

    // ✅ If already recording → user is trying to stop early
// ✅ If already recording → user is trying to stop early
if (_isRecording) {
  // Pause timers + data first
  _stopTimer();
  _recordingTimer?.cancel();
  await _dataStreamer.stopRecorder();
  await _fileRecorder.pause();

  // Ask user
  final restart = await _showMinDurationDialog();
  if (!mounted) return;

  if (restart == false) {
    // Continue recording
    await _dataStreamer.startRecorder(
      toStream: _recordingDataController!.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 4000,
    );
    await _fileRecorder.resume();
    _startTimer();

  // 🧩 FIX: Restart the 5-second auto-stop timer
  _recordingTimer = Timer(
    const Duration(seconds: _recordingDurationInSeconds),
    () async {
      if (_isRecording) {
        HapticFeedback.mediumImpact();
        await _stopRecording();
      }
    },
  );


    setState(() => _isProcessing = false);
    return;
  }

  // User chose restart → discard recording safely
  await _stopRecording(forceDiscard: true);
  _stopTimer();

  setState(() {
    _isProcessing = false;
    _isRecording = false;
    _spots.clear();
    _duration = Duration.zero;
  });

  _toast("Recording reset — tap again to start", success: true);
  return;
}

    // ✅ Ask consent before start
    final consent = await _showConsentDialog();
    if (consent != true) {
      HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 60));
      _toast("Recording cancelled — patient consent required.");
      setState(() => _isProcessing = false);
      return;
    }

    // Persist once per session (best-effort)
try {
  final prefs = await SharedPreferences.getInstance();
  final pid = prefs.getInt('practitioner_id');
  if (pid != null) {
    await db.updatePractitionerConsent(pid, true);
  }
} catch (_) {}

    await Future.delayed(const Duration(milliseconds: 120));
    HapticFeedback.lightImpact();
    _toast("Consent logged.", success: true);

    await _startRecording();
    LatencyDebug.end("🎙️ Tap", "Started");
    setState(() => _isProcessing = false);
  }

  Future<bool?> _showConsentDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Patient Consent Required"),
        content: const Text(
          "Before recording, confirm the patient has been informed and consented.",
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text("Yes, I Confirm"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }

  Future<void> _startRecording() async {
    _recordingDataController = StreamController<Uint8List>();
    _dataSubscription = _recordingDataController!.stream.listen(_updateWaveform);

   try {
      await _dataStreamer.startRecorder(
        toStream: _recordingDataController!.sink,
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 4000,
      );
    } catch (e) {
      debugPrint("Waveform recorder unavailable: $e");
    }

    final tempDir = await Directory.systemTemp.createTemp();
    final tempPath = '${tempDir.path}/temp_recording.wav';

    await _fileRecorder.start(
      const record_lib.RecordConfig(
        encoder: record_lib.AudioEncoder.wav,
        sampleRate: 4000,
        numChannels: 1,
      ),
      path: tempPath,
    );

    setState(() {
      _isRecording = true;
      _spots = [];
      _timeCounter = 0;
      _duration = Duration.zero;
    });

    _startTimer();

    _recordingTimer = Timer(
      const Duration(seconds: _recordingDurationInSeconds),
      () async {
        if (_isRecording) {
          HapticFeedback.mediumImpact();
          await _stopRecording();
        }
      },
    );
  }

  Future<void> _stopRecording({bool forceDiscard = false}) async {
    if (!_isRecording) return;

    setState(() => _isProcessing = true);
    _recordingTimer?.cancel();
    await _dataStreamer.stopRecorder();
    final path = await _fileRecorder.stop();

    _dataSubscription?.cancel();
    _recordingDataController?.close();
    _stopTimer();

    setState(() => _isRecording = false);

    if (forceDiscard) {
      if (path != null) File(path).delete();
      setState(() => _isProcessing = false);
      return;
    }

    if (path == null) {
      setState(() => _isProcessing = false);
      return;
    }

try {
  final len = await File(path).length();
  // ~2KB is a safe minimum for 5s @ 4 kHz mono PCM16 WAV headers+data
  if (len < 2000) {
    debugPrint("❌ Corrupted/empty audio file discarded (size: $len)");
    await File(path).delete().catchError((_) async => File(path));
    setState(() => _isProcessing = false);
    _toast("Recording failed. Please try again.");
    return;
  }
} catch (_) {
  setState(() => _isProcessing = false);
  _toast("Recording failed. Please try again.");
  return;
}

    final session = DateTime.now().millisecondsSinceEpoch.toString();
    Map<String, dynamic>? aiResult;
    Uint8List? melPng;

    try {
      aiResult = await _tfliteService.runInference(filePath: path, session: session);
      melPng = await _tfliteService.generateMelImageBytes(path, session: session);
    } catch (_) {}

    await _handleRecordingSave(path, aiResult, melPng);
    setState(() => _isProcessing = false);
  }

  Future<void> _handleRecordingSave(
      String tempPath, Map<String, dynamic>? aiResult, Uint8List? melPng) async {
    try {
      Map<String, dynamic>? patient =
          _currentPatient ?? await _showPatientDialog();
      if (patient == null) return;

      setState(() => _currentPatient = patient);

      final patientId = patient['patient_id'];
      String? folderPath = patient['folder_path'];

      if (folderPath == null || folderPath.isEmpty) {
        final basePath = await storage.getOrCreateBaseFolder();
        folderPath =
            await storage.createPatientSubfolders(basePath, patientId);
        await db.updatePatientFolderPath(patientId, folderPath);
      }

      await storage.setCurrentPatient(patientId);

      final formattedId = db.formatPatientId(patientId);
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final newFileName = "${formattedId}_$ts.wav";
      final internalPath = "$folderPath/Recordings/$newFileName";

      await Directory("$folderPath/Recordings").create(recursive: true);
      await File(tempPath).copy(internalPath);
      await File(tempPath).delete();

      final prefs = await SharedPreferences.getInstance();
      final pid = prefs.getInt("practitioner_id")!;
      final email = prefs.getString("practitioner_email")!;

      await storage.mirrorWavToExternal(
        practitionerId: pid,
        practitionerEmail: email,
        patientId: patientId,
        wavPathInternal: internalPath,
      );

      final recordDate = DateTime.now();
      final recordId = await db.insertRecord({
        "patient_id": patientId,
        "file_path": internalPath,
        "record_date": recordDate.toIso8601String(),
      });

      if (aiResult != null) {
        await db.insertAnalysis({
          "record_id": recordId,
          "diagnosis": aiResult['label'] ?? "Error",
          "probabilities": jsonEncode(aiResult['probabilities'] ?? {}),
          "analysis_date": DateTime.now().toIso8601String(),
        });
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReportGeneratedPage(
            patientId: patientId,
            patientName: patient['name'],
            patientAge: patient['age'] ?? '-',
            patientGender: patient['gender'] ?? '-',
            filePath: internalPath,
            recordedDate: recordDate,
            classification: aiResult?['label'] ?? 'Error',
            probabilities: aiResult?['probabilities'] ?? {},
            patientBirthday: patient['birthday'],
            symptoms: patient['symptoms'],
            melPngBytes: melPng,
          ),
        ),
      );
    } catch (e) {
      _toast("Error saving record: $e");
    }
  }

  Future<Map<String, dynamic>?> _showPatientDialog(
      {bool switchMode = false}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: switchMode,
      builder: (_) => PatientFormDialog(isSwitchMode: switchMode),
    );

    if (result != null) {
      final id = result['patient_id'];
      await db.database.then((c) {
        c.update(
          "patients",
          {"symptoms": result['symptoms'] ?? ''},
          where: "patient_id = ?",
          whereArgs: [id],
        );
      });
      await _loadCurrentPatient();
    }
    return result;
  }

  Future<void> _switchPatient() async {
    final res =
        await _showPatientDialog(switchMode: _currentPatient != null);
    if (res == null) return;
    final fresh = await db.getPatientById(res['patient_id']);
    setState(() => _currentPatient = fresh ?? res);
    await storage.setCurrentPatient(res['patient_id']);
    _toast("Switched patient", success: true);
  }

  void _updateWaveform(Uint8List rawData) {
    final bd = rawData.buffer.asByteData();
    final tmp = <double>[];

    for (int i = 0; i < rawData.lengthInBytes; i += 2) {
      tmp.add(bd.getInt16(i, Endian.little) / 32768.0);
    }

    const int step = 100;
    double prev = 0;
    final reduced = <double>[];

    for (int i = 0; i < tmp.length; i += step) {
      final slice = tmp.sublist(i, math.min(i + step, tmp.length));
      final avg = slice.reduce((a, b) => a + b) / slice.length;
      final smoothed = prev + _smoothAlpha * (avg - prev);
      prev = smoothed;
      reduced.add(smoothed);
    }

    final peak = reduced.fold(1e-6, (m, e) => math.max(m, e.abs()));
    double targetGain = 1 / (peak * 1.2);
    targetGain = targetGain.clamp(0.8, 6.0);
    _displayGain = 0.9 * _displayGain + 0.1 * targetGain;

    setState(() {
      for (final s in reduced) {
        _timeCounter += 0.007;
        _spots.add(FlSpot(_timeCounter, (s * _displayGain).clamp(-1, 1)));
      }
      if (_spots.length > _visiblePoints) {
        _spots = _spots.sublist(_spots.length - _visiblePoints);
      }
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _duration += const Duration(seconds: 1)),
    );
  }

  void _stopTimer() => _timer?.cancel();

  String _formatDuration(Duration d) =>
      "${d.inMinutes.remainder(60).toString().padLeft(2, "0")}:${d.inSeconds.remainder(60).toString().padLeft(2, "0")}";

Future<void> _pickWavFile() async {
  try {
    // Pick only WAV files
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav'],
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path!;
    final file = File(path);
    if (!await file.exists()) return;

    setState(() => _isProcessing = true);
    _toast("Analyzing selected WAV...", success: true);

// ✅ Ensure models loaded (avoid redundant reload)
if (!_tfliteService.isLoaded) {
  await _tfliteService.loadModels();
}


// ✅ Trim to 5 s (20 000 samples @ 4 kHz, 16 bit mono)
final bytes = await file.readAsBytes();
if (bytes.length < 44) {
  _toast("Invalid WAV file.");
  setState(() => _isProcessing = false);
  return;
}

if (!mounted) return;

// 🧠 If file longer than 5 s (~40000 samples @ 4 kHz), ask confirmation
final pcmAll = bytes.sublist(44);
if (pcmAll.length > 40000) {
  final cont = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Trim Long Recording?"),
      content: const Text(
          "Only the first 5 seconds will be analyzed.\n\nDo you want to continue?"),
      actions: [
        TextButton(
          child: const Text("Cancel"),
          onPressed: () => Navigator.pop(context, false),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text("Continue"),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (cont != true) {
    setState(() => _isProcessing = false);
    return;
  }
}

// ✅ Define `fiveSecBytes` properly here
final fiveSecBytes = pcmAll.length > 40000 ? pcmAll.sublist(0, 40000) : pcmAll;

// ✅ Create trimmed file
final trimmed = Uint8List(44 + fiveSecBytes.length);
trimmed.setRange(0, 44, bytes.sublist(0, 44));
trimmed.setRange(44, 44 + fiveSecBytes.length, fiveSecBytes);

// 🔒 Fix header fields for strict WAV parsers (insert below)
final bd = trimmed.buffer.asByteData();
bd.setUint32(4, trimmed.lengthInBytes - 8, Endian.little); // total file size
bd.setUint32(40, fiveSecBytes.length, Endian.little);      // data chunk size

    final tempDir = await Directory.systemTemp.createTemp();
    final tempPath = '${tempDir.path}/import_trimmed.wav';
    await File(tempPath).writeAsBytes(trimmed);

    // ✅ Run AI analysis
    final session = DateTime.now().millisecondsSinceEpoch.toString();
    final aiResult =
        await _tfliteService.runInference(filePath: tempPath, session: session);
    final melPng =
        await _tfliteService.generateMelImageBytes(tempPath, session: session);

    await _handleRecordingSave(tempPath, aiResult, melPng);
  } catch (e) {
    _toast("Import failed: $e");
} finally {
  // 🧹 Cleanup temporary directory (safe, optional)
  try {
    final tempDir = Directory.systemTemp;
    await for (final entity in tempDir.list()) {
      if (entity is Directory && entity.path.contains('import_trimmed')) {
        await entity.delete(recursive: true);
      }
    }
  } catch (_) {}
  setState(() => _isProcessing = false);
}
}

  @override
  Widget build(BuildContext context) {
  return Scaffold( // ← return Scaffold, not just body:
    appBar: AppBar(
  backgroundColor: AppColors.primary,
  foregroundColor: Colors.white,
  title: const Text("Record Heart Sound"),
actions: [
Padding(
  padding: const EdgeInsets.only(right: 14),
  child: AnimatedContainer(
    duration: const Duration(milliseconds: 400),
    curve: Curves.easeInOut,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: _isUsbMicConnected
          ? (Theme.of(context).brightness == Brightness.dark
              ? AppColors.success.withValues(alpha: 0.25)
              : AppColors.success.withValues(alpha: 0.9))
          : (Theme.of(context).brightness == Brightness.dark
              ? AppColors.warning.withValues(alpha: 0.25)
              : AppColors.warning.withValues(alpha: 0.9)),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(
        color: Colors.white.withValues(alpha: 
          Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.6,
        ),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: _isUsbMicConnected
              ? AppColors.success.withValues(alpha: 0.4)
              : AppColors.warning.withValues(alpha: 0.4),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _isUsbMicConnected ? Icons.usb_rounded : Icons.usb_off_rounded,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.white,
          size: 18,
        ),
        const SizedBox(width: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: Text(
            _isUsbMicConnected ? "Connected" : "Disconnected",
            key: ValueKey(_isUsbMicConnected),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.3,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha:
                    Theme.of(context).brightness == Brightness.dark ? 0.9 : 0.3,
                  ),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
),
],
),

    
  body: SafeArea(
    child: SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPatientInfoCard(),
            const SizedBox(height: 8),

            // ✅ Dynamic area (either waveform or guidelines)
            _isRecording
                ? SizedBox(height: MediaQuery.of(context).size.height * 0.45, child: _buildRecordingView())
                : _buildGuidelinesView(),

            SizedBox(height: MediaQuery.of(context).size.height * 0.02),

            // ✅ Mic Button
            Hero(
              tag: "record_button_hero",
              child: Opacity(
                opacity: _isProcessing ? 0.5 : 1,
                child: GestureDetector(
                  onTap: _isProcessing ? null : _toggleRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 125,
                    height: 125,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isProcessing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Icon(
                              _isRecording
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              size: 60,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: MediaQuery.of(context).size.height * 0.012),

            Text(
              _isRecording ? "Recording... (5s)" : "Tap to record",
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),

            SizedBox(height: MediaQuery.of(context).size.height * 0.04),

          ],
        ),
      ),
    ),
  ),
);
  }


Widget _buildGuidelinesView() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🩺 Title (centered for symmetry)
        Center(
          child: Text(
            "Recording Guidelines",
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.deep,
                ),
          ),
        ),
        Center(
  child: TextButton.icon(
    icon: const Icon(Icons.upload_file_rounded),
    label: const Text("Import existing WAV"),
    onPressed: _isProcessing ? null : _pickWavFile,
  ),
),


        SizedBox(height: MediaQuery.of(context).size.height * 0.018),

        // Diagram
        Center(
          child: Image.asset(
            'assets/images/mitral_area_guide.png',
            height: 160,
            fit: BoxFit.contain,
          ),
        ),

        SizedBox(height: MediaQuery.of(context).size.height * 0.018),

        // Guideline bullets
        _buildGuidelineItem(Icons.mic_off_rounded, "Quiet environment"),
        _buildGuidelineItem(Icons.place_rounded, "Place at mitral area"),
        _buildGuidelineItem(Icons.timer_rounded, "Record for 5 seconds"),
        _buildGuidelineItem(Icons.person_rounded, "Patient remains still"),

        SizedBox(height: MediaQuery.of(context).size.height * 0.012),

        // Clinical notes box (aligned left, simple and readable)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "For patients with prominent breast tissue, assistance may help accurate placement.",
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "For dextrocardia or situs inversus, mirror placement to right side.",
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}


  Widget _buildRecordingView() {
    final minX =
        _spots.isNotEmpty ? math.max(0, _spots.last.x - _visiblePoints) : 0;
    final maxX =
        _spots.isNotEmpty ? _spots.last.x : _visiblePoints.toDouble();

    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: _spots.isEmpty
                ? const Center(child: Text("Waiting for audio..."))
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LineChart(
                      LineChartData(
                        titlesData: const FlTitlesData(show: false),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        clipData: const FlClipData.all(),
                        minY: -1.2,
                        maxY: 1.2,
                        minX: minX.toDouble(),
                        maxX: maxX.toDouble(),
                        lineTouchData:
                            const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _spots,
                            isCurved: true,
                            color: AppColors.primary,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        SizedBox(height: MediaQuery.of(context).size.height * 0.02),

        Text(
          _formatDuration(_duration),
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }

  Widget _buildGuidelineItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildPatientInfoCard() {
    final name = _currentPatient?['name'] ?? "";
    final symptoms = _currentPatient?['symptoms'] ?? "";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).cardColor,
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
                  name.isNotEmpty ? name : "No patient selected",
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ]),
              TextButton.icon(
                onPressed: _switchPatient,
                icon: const Icon(Icons.swap_horiz_rounded,
                    color: AppColors.primary),
                label: Text(name.isNotEmpty ? "Switch" : "Add"),
              ),
            ],
          ),
          if (symptoms.toString().isNotEmpty)
            Text(
              "Symptoms: $symptoms",
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
        ],
      ),
    );
  }

  void _toast(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            success ? AppColors.success : AppColors.warning,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
