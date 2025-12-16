// lib\pages\reports_detail.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cardioscope_app/services/storage_service.dart';
import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:cardioscope_app/utils/ui_helpers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';
import '../services/tflite_service.dart';
import '../utils/pdf_exporter.dart';

class ReportDetailPage extends StatefulWidget {
  final Map<String, dynamic> report;
  const ReportDetailPage({super.key, required this.report});

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  final AudioPlayer _player = AudioPlayer();
  late Future<List<FlSpot>> _waveformFuture;
  final TfliteService _tfliteService = TfliteService();

  bool _isReanalyzing = false;
  Uint8List? _melPng;
  late String _currentDiagnosis;
  late Map<String, double> _currentProbabilities;
  String _practitionerName = "Practitioner";

  late Map<String, dynamic> _localReport;

  @override
  void initState() {
    super.initState();

    // ✅ Default so first build is safe
    _waveformFuture = Future.value(<FlSpot>[]);

    _localReport = Map<String, dynamic>.from(widget.report);
    _initializeState();
    _loadPractitionerName();
    Future.delayed(const Duration(milliseconds: 200), _refreshPatientDetails);

    // Resolve path then init player and waveform
    _resolveAndPossiblyRepairPath().then((resolvedPath) async {
      if (resolvedPath != null) {
        _localReport['file_path'] = resolvedPath;
        await _initAudioPlayer(resolvedPath);
      }
      setState(() {
        _waveformFuture = _loadWaveformData();
      });

      if (_melPng == null && resolvedPath != null) {
        _generateMelIfNeeded();
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // -------- Path + Player --------

  Future<String?> _resolveAndPossiblyRepairPath() async {
    String? path = _localReport['file_path'] as String?;
    if (path == null) return null;

    File file = File(path);
    if (await file.exists()) return path;

    try {
      final storage = StorageService();
      final newBase = await storage.getOrCreateBaseFolder();
      final leafName = path.split('/').last;
      final patientId = _localReport['patient_id'];
      final formattedId = DatabaseHelper.instance.formatPatientId(patientId ?? 0);
      final candidate = File('$newBase/Patients/$formattedId/Recordings/$leafName');
      if (await candidate.exists()) {
        debugPrint("🔄 Repaired path: ${candidate.path}");
        return candidate.path;
      }
      debugPrint("❌ Could not repair path for: $path");
      return null;
    } catch (e) {
      debugPrint("⚠️ Path repair failed: $e");
      return null;
    }
  }

  Future<void> _initAudioPlayer(String path) async {
    try {
      await _player.setFilePath(path);
      debugPrint("✅ Audio ready: $path");
    } catch (e) {
      debugPrint("❌ Could not load audio: $e");
    }
  }

  // -------- State helpers --------

  Future<void> _loadPractitionerName() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _practitionerName = prefs.getString('practitioner_name') ?? 'Practitioner';
    });
  }

  void _initializeState() {
    _currentDiagnosis = _localReport['diagnosis'] ?? 'N/A';
    _currentProbabilities = {};
    final probsJson = _localReport['probabilities'] as String?;
    if (probsJson != null) {
      try {
        final decoded = jsonDecode(probsJson) as Map<String, dynamic>;
        decoded.forEach((k, v) => _currentProbabilities[k] = (v as num).toDouble());
      } catch (e) {
        debugPrint("⚠️ Error decoding probabilities: $e");
      }
    }
  }

  Future<void> _refreshPatientDetails() async {
    try {
      final db = DatabaseHelper.instance;
      final raw = _localReport['patient_id'];
      if (raw == null) return;
      final int? patientId = raw is int ? raw : int.tryParse(raw.toString());
      if (patientId == null) return;

      final patient = await db.getPatientById(patientId);
      if (patient != null && mounted) {
        setState(() {
          _localReport['name']      = patient['name']      ?? _localReport['name'];
          _localReport['birthday']  = patient['birthday']  ?? _localReport['birthday'];
          _localReport['gender']    = patient['gender']    ?? _localReport['gender'];
          _localReport['age']       = patient['age']       ?? _localReport['age'];
          _localReport['symptoms']  = patient['symptoms']  ?? _localReport['symptoms'];
        });
      }
    } catch (e) {
      debugPrint("❌ Error refreshing patient details: $e");
    }
  }

  // -------- Waveform --------

  Future<List<FlSpot>> _loadWaveformData() async {
    final path = _localReport['file_path'] as String?;
    if (path == null) return [];
    final file = File(path);
    if (!await file.exists()) return [];

    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes <= 44) return [];

    // find "data" chunk offset
    int dataOffset = 44;
    for (int i = 0; i < bytes.length - 4; i++) {
      if (bytes[i] == 0x64 && bytes[i + 1] == 0x61 && bytes[i + 2] == 0x74 && bytes[i + 3] == 0x61) {
        dataOffset = i + 8;
        break;
      }
    }

    final pcmBytes = bytes.sublist(dataOffset);
    final byteData = ByteData.view(pcmBytes.buffer);
    final spots = <FlSpot>[];
    const downsample = 40;

    for (int i = 0; i + 2 <= pcmBytes.lengthInBytes; i += (2 * downsample)) {
      final sample = byteData.getInt16(i, Endian.little) / 32768.0;
      spots.add(FlSpot((i / 2).toDouble(), sample.toDouble()));
    }
    debugPrint("✅ Waveform loaded: ${spots.length} samples");
    return spots;
  }

  // -------- Mel Spectrogram --------

  Future<void> _generateMelIfNeeded() async {
    if (_melPng != null) return;
    final filePath = _localReport['file_path'] as String?;
    if (filePath == null) return;

    setState(() => _isReanalyzing = true);
    try {
      final bytes = await _tfliteService.generateMelImageBytes(filePath);
      if (!mounted) return;
      setState(() {
        _melPng = bytes;
        _isReanalyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isReanalyzing = false);
      debugPrint("❌ Mel generation failed: $e");
    }
  }

  // -------- Re-analyze --------

  Future<void> _reAnalyze() async {
    final filePath = _localReport['file_path'] as String?;
    final recordId  = _localReport['record_id'] as int?;
    if (filePath == null || recordId == null) return;

    setState(() => _isReanalyzing = true);
    try {
      final result = await _tfliteService.runInference(filePath: filePath);
      if (result == null) {
        if (!mounted) return;
        setState(() => _isReanalyzing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Re-analysis failed.")),
        );
        return;
      }

      final diagnosis = (result['label'] ?? 'N/A') as String;
      final probs = Map<String, double>.from(
        (result['probabilities'] as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        ),
      );

      final db = DatabaseHelper.instance;
      // ✅ Save full enriched model results
await db.upsertAnalysisByRecordId(
  recordId,
  diagnosis: diagnosis,
  probabilitiesJson: jsonEncode(probs),
  analysisDateIso: DateTime.now().toIso8601String(),
);

// ✅ Update heart_sound_records table with flattened values
await db.database.then((conn) {
  conn.update(
    'heart_sound_records',
    {
      'diagnosis': diagnosis,
      'probabilities': jsonEncode(probs),
      'prob_normal': probs['N'] ?? 0,
      'prob_mr':     probs['MR'] ?? 0,
      'prob_ms':     probs['MS'] ?? 0,
      'prob_mvp':    probs['MVP'] ?? 0,
      'confidence':  (probs[diagnosis] ?? 0),
    },
    where: 'record_id = ?',
    whereArgs: [recordId],
  );
});


      final melBytes = await _tfliteService.generateMelImageBytes(filePath);
      if (!mounted) return;
      setState(() {
        _currentDiagnosis = diagnosis;
        _currentProbabilities = probs;
        _melPng = melBytes;
        _isReanalyzing = false;
        _refreshPatientDetails(); // ✅ Refresh hydrated DB data too
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Re-analysis complete.")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isReanalyzing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Re-analysis failed: $e")));
    }
  }

Future<void> _showEditDialog(
  BuildContext context,
  DatabaseHelper db,
  StorageService storage,
) async {
  final nameCtrl    = TextEditingController(text: _localReport['name'] ?? '');
  final genderCtrl  = TextEditingController(text: _localReport['gender'] ?? '');
  final birthdayCtrl =
      TextEditingController(text: _localReport['birthday'] ?? '');

  bool dirty = false; // local, but will be driven by StatefulBuilder

  int? ageFromBirthday(String ymd) {
    try {
      final b = DateTime.parse(ymd);
      final now = DateTime.now();
      var age = now.year - b.year;
      final notHadBirthdayThisYear =
          (now.month < b.month) ||
          (now.month == b.month && now.day < b.day);
      if (notHadBirthdayThisYear) age--;
      return (age >= 0 && age < 130) ? age : null;
    } catch (_) {
      return null;
    }
  }

  await showDialog(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          void markDirty() {
            if (!dirty) {
              setStateDialog(() {
                dirty = true;
              });
            }
          }

          return AlertDialog(
            title: const Text("Edit Patient Info"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "Name"),
                  onChanged: (_) => markDirty(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: genderCtrl,
                  decoration: const InputDecoration(labelText: "Gender"),
                  onChanged: (_) => markDirty(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: birthdayCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: "Birthday",
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: DateTime.tryParse(birthdayCtrl.text) ??
                          DateTime(2000),
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setStateDialog(() {
                        birthdayCtrl.text =
                            DateFormat('yyyy-MM-dd').format(picked);
                        dirty = true;
                      });
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor:
                      Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: !dirty
                    ? null
                    : () async {
                        final patientId =
                            _localReport['patient_id'] as int?;
                        if (patientId == null) {
                          Navigator.of(dialogContext).pop();
                          return;
                        }

                        final age =
                            ageFromBirthday(birthdayCtrl.text.trim());

                        // 1) Update DB
                        await db.database.then((conn) {
                          conn.update(
                            'patients',
                            {
                              'name': nameCtrl.text.trim(),
                              'gender': genderCtrl.text.trim(),
                              'birthday': birthdayCtrl.text.trim(),
                              'age': age,
                            },
                            where: 'patient_id = ?',
                            whereArgs: [patientId],
                          );
                        });

                        final prefs =
                            await SharedPreferences.getInstance();
                        final practitionerId =
                            prefs.getInt('practitioner_id');

                        if (practitionerId == null) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Practitioner not found — please log in again.",
                              ),
                            ),
                          );
                          Navigator.of(dialogContext).pop();
                          return;
                        }

                        // 2) Save JSON (internal only)
                        final folderPath =
                            _localReport['folder_path'];
                        if (folderPath != null &&
                            folderPath.toString().isNotEmpty) {
                          await storage.savePatientInfoJson({
                            'patient_id': patientId,
                            'practitioner_id': practitionerId,
                            'name': nameCtrl.text.trim(),
                            'birthday': birthdayCtrl.text.trim(),
                            'age': age,
                            'gender': genderCtrl.text.trim(),
                            'folder_path': folderPath,
                            'symptoms':
                                _localReport['symptoms'] ?? '',
                          });
                        }

                        // 3) Update local state on page
                        if (!mounted) return;
                        setState(() {
                          _localReport['name'] =
                              nameCtrl.text.trim();
                          _localReport['gender'] =
                              genderCtrl.text.trim();
                          _localReport['birthday'] =
                              birthdayCtrl.text.trim();
                          _localReport['age'] = age;
                        });

                        if (!context.mounted) return; {
                          Navigator.of(dialogContext).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text("Patient info updated."),
                            ),
                          );
                        }
                      },
                child: const Text("Save"),
              ),
            ],
          );
        },
      );
    },
  );
}

  // -------- Export PDF --------

  Future<void> _handleExportPdf() async {
    if (_melPng == null) {
      await _generateMelIfNeeded();
      if (_melPng == null) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Generate Spectrogram First"),
            content: const Text("Please generate the Mel-Spectrogram before exporting the report to PDF."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
            ],
          ),
        );
        return;
      }
    }

    final practitioner = await DatabaseHelper.instance.getPractitionerByName(_practitionerName);
    if (!mounted) return;
    final consent = practitioner?['consent_agreed'] == 1;
    final email   = practitioner?['email'] ?? '';

    await PdfExporter.exportSingleReport(
      context: context,
      report: {
        'patient_id': _localReport['patient_id'],
        'name': _localReport['name'],
        'birthday': _localReport['birthday'],
        'age': _localReport['age'],
        'gender': _localReport['gender'],
        'symptoms': _localReport['symptoms'] ?? '-',
        'file_path': _localReport['file_path'],
        'record_date': _localReport['record_date'],
        'diagnosis': _currentDiagnosis,
        'probabilities': _currentProbabilities,
        'practitioner_email': email,
        'consent_agreed': consent,
        'mel_png': _melPng,
      },
      practitionerName: _practitionerName,
      practitionerConsent: consent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final recordDate = _localReport['record_date'];
    String dateString = 'N/A';
    if (recordDate is String) {
      try {
        dateString =
            DateFormat('MMMM d, yyyy HH:mm').format(DateTime.parse(recordDate));
      } catch (_) {}
    }

    final patientId = _localReport['patient_id'];
    final patientIdFormatted = patientId != null
        ? DatabaseHelper.instance.formatPatientId(patientId as int)
        : 'N/A';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        iconTheme:
            IconThemeData(color: Theme.of(context).colorScheme.onPrimary),
        title: Text(
          'Report for ${_localReport['name'] ?? 'Unnamed'}',
          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert,
                color: Theme.of(context).colorScheme.surface),
            onSelected: (value) async {
              final db = DatabaseHelper.instance;
              final storage = StorageService();
              if (value == 'reanalyze') {
                _reAnalyze();
              } else if (value == 'edit') {
                await _showEditDialog(context, db, storage);
              } else if (value == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Confirm Delete"),
                    content: const Text("Are you sure you want to delete this report?"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        ),
                        child: const Text("Delete"),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await storage.deleteRecordFiles(_localReport['file_path']);
                  await db.deleteRecordById(_localReport['record_id']);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("🗑 Report deleted.")),
                  );
                  Navigator.pop(context, true);
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'reanalyze',
                child: Row(children: [
                  Icon(Icons.refresh, color: AppColors.deep),
                  SizedBox(width: 8),
                  Text("Re-analyze"),
                ]),
              ),
              PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit, color: AppColors.deep),
                  SizedBox(width: 8),
                  Text("Edit Patient Info"),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete, color: AppColors.warning),
                  SizedBox(width: 8),
                  Text("Delete"),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _isReanalyzing
          ? const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
      : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildDetailSection(patientIdFormatted, dateString),
          const SizedBox(height: 16),
          _buildAnalysisSection(),
          const SizedBox(height: 16),
          _buildSpectrogramSection(),
          const SizedBox(height: 16),
          _buildWaveformSection(),
          const SizedBox(height: 80),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _handleExportPdf,
        backgroundColor: AppColors.primary,
        icon: Icon(Icons.picture_as_pdf,
            color: Theme.of(context).colorScheme.onPrimary),
        label: Text(
          "Export PDF",
          style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // Detail Section
  Widget _buildDetailSection(String patientIdFormatted, String dateString) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Patient Details",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Divider(height: 20),
          _buildRow('Patient ID:', patientIdFormatted),
          _buildRow('Name:', _localReport['name'] ?? 'Unnamed'),
          _buildRow('Birthday:', _localReport['birthday'] ?? 'N/A'),
          _buildRow('Age:', _localReport['age']?.toString() ?? 'N/A'),
          _buildRow('Gender:', _localReport['gender'] ?? 'N/A'),
          _buildRow('Symptoms:', _localReport['symptoms'] ?? 'N/A'),
          _buildRow('File:', (_localReport['file_path'] ?? '').split('/').last),
          _buildRow('Recorded:', dateString),
        ]),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$label ",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white70
                  : Colors.black87,
            ),
          ),
          Expanded(child: SelectableText(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  // AI Analysis Section
  Widget _buildAnalysisSection() {
    final sortedEntries = _currentProbabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("AI Analysis",
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _buildRow('Classification:', _currentDiagnosis),
            const SizedBox(height: 10),
            Text("Detailed Breakdown:",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),

            if (_currentProbabilities.isNotEmpty)
              ...sortedEntries.asMap().entries.map((entry) {
                final isTop = entry.key == 0;
                return _buildProbabilityRow(entry.value.key, entry.value.value,
                    highlight: isTop);
              })
            else
              Text("No probabilities available.",
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }

  // Probability Row
  Widget _buildProbabilityRow(String label, double value,
      {bool highlight = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: TextStyle(
                  fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
                  color: highlight
                      ? AppColors.primaryLight
                      : (isDark ? Colors.white70 : Colors.grey.shade700),
                  fontSize: highlight ? 15 : 14,
                )),
          ),
          Expanded(
            flex: 5,
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
              color: UIHelpers.getStatusColor(label)
                  .withValues(alpha: highlight ? 0.95 : 0.85),
              minHeight: highlight ? 14 : 12,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text("${(value * 100).toStringAsFixed(2)}%",
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                  color: highlight
                      ? AppColors.primaryLight
                      : (isDark ? Colors.white70 : Colors.grey.shade800),
                )),
          ),
        ],
      ),
    );
  }

  // Spectrogram Section
  Widget _buildSpectrogramSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("Model Input (Mel-Spectrogram)",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Divider(height: 20),
          if (_melPng != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_melPng!,
                  width: double.infinity, fit: BoxFit.cover),
            )
          else if (_isReanalyzing)
            const Center(child: CircularProgressIndicator())
          else
            Column(children: [
              const Text('Spectrogram not yet generated.'),
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                onPressed: _generateMelIfNeeded,
                child: const Text('Generate Spectrogram'),
              ),
            ]),
        ]),
      ),
    );
  }

  // Waveform Section
  Widget _buildWaveformSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text("Raw Waveform & Playback",
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Divider(height: 20),
          SizedBox(
            height: 150,
            child: FutureBuilder<List<FlSpot>>(
              future: _waveformFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No waveform available'));
                }
                return LineChart(LineChartData(
                  titlesData: const FlTitlesData(show: false),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  minY: -1,
                  maxY: 1,
                  lineBarsData: [
                    LineChartBarData(
                      spots: snapshot.data!,
                      isCurved: false,
                      color: AppColors.primary,
                      barWidth: 1.2,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  lineTouchData: const LineTouchData(enabled: false),
                ));
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildPlaybackControls(),
        ]),
      ),
    );
  }

  Widget _buildPlaybackControls() {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final playing = playerState?.playing ?? false;
        final processingState = playerState?.processingState;

        IconData icon = Icons.play_arrow_rounded;
        if (playing) {
          icon = Icons.pause_rounded;
        } else if (processingState == ProcessingState.completed) {
          icon = Icons.replay_rounded;
        }

        return IconButton(
          icon: Icon(icon, color: AppColors.primary),
          iconSize: 48,
          onPressed: () {
            if (playing) {
              _player.pause();
            } else if (processingState == ProcessingState.completed) {
              _player.seek(Duration.zero);
              _player.play();
            } else {
              _player.play();
            }
          },
        );
      },
    );
  }
}
