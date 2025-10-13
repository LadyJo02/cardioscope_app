// lib/pages/reports_detail.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  late final Future<List<FlSpot>> _waveformFuture;
  final TfliteService _tfliteService = TfliteService();

  bool _isReanalyzing = false;
  Uint8List? _melPng;
  late String _currentDiagnosis;
  late Map<String, double> _currentProbabilities;
  String _practitionerName = "Practitioner";

  // ✅ Local mutable copy of report
  late Map<String, dynamic> _localReport;

  @override
  void initState() {
    super.initState();
    _localReport = Map<String, dynamic>.from(widget.report);
    _waveformFuture = _loadWaveformData();
    _initializeState();
    _loadPractitionerName();

    final path = _localReport['file_path'] as String?;
    if (path != null && File(path).existsSync()) {
      _player.setFilePath(path).catchError((e) {
        debugPrint("❌ Could not load audio file: $e");
        return null;
      });
    }
  }

  Future<void> _loadPractitionerName() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _practitionerName =
            prefs.getString('practitioner_name') ?? 'Practitioner';
      });
    }
  }

  void _initializeState() {
    _currentDiagnosis = _localReport['diagnosis'] ?? 'N/A';
    _currentProbabilities = {};
    final probsJson = _localReport['probabilities'] as String?;
    if (probsJson != null) {
      try {
        final decoded = jsonDecode(probsJson) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          _currentProbabilities[key] = (value as num).toDouble();
        });
      } catch (e) {
        debugPrint("⚠️ Error decoding probabilities: $e");
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<List<FlSpot>> _loadWaveformData() async {
    final path = _localReport['file_path'] as String?;
    if (path == null) return [];
    final file = File(path);
    if (!await file.exists()) return [];
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes <= 44) return [];

    int dataOffset = 44;
    for (int i = 0; i < bytes.length - 4; i++) {
      if (bytes[i] == 0x64 &&
          bytes[i + 1] == 0x61 &&
          bytes[i + 2] == 0x74 &&
          bytes[i + 3] == 0x61) {
        dataOffset = i + 8;
        break;
      }
    }

    final pcmBytes = bytes.sublist(dataOffset);
    final byteData = ByteData.view(pcmBytes.buffer);
    final spots = <FlSpot>[];
    const downsample = 40;

    for (int i = 0; i < pcmBytes.lengthInBytes; i += (2 * downsample)) {
      if (i + 2 <= pcmBytes.lengthInBytes) {
        final sample = byteData.getInt16(i, Endian.little) / 32768.0;
        spots.add(FlSpot((i / 2).toDouble(), sample));
      }
    }
    return spots;
  }

  Future<void> _generateMelIfNeeded() async {
    if (_melPng != null) return;
    final filePath = _localReport['file_path'] as String?;
    if (filePath == null) return;

    if (!mounted) return;
    setState(() => _isReanalyzing = true);
    debugPrint("🎨 Generating Mel-Spectrogram for: $filePath");

    final bytes = await _tfliteService.generateMelImageBytes(filePath);

    if (!mounted) return;
    setState(() {
      _melPng = bytes;
      _isReanalyzing = false;
    });

    debugPrint("✅ Spectrogram generation complete.");
  }

  Future<void> _reAnalyze() async {
    final filePath = _localReport['file_path'] as String?;
    final recordId = _localReport['record_id'] as int?;
    if (filePath == null || recordId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing file or record ID.")),
      );
      return;
    }

    setState(() => _isReanalyzing = true);
    try {
      final result = await _tfliteService.runInference(filePath: filePath);
      if (result == null) {
        if (!mounted) return;
        setState(() => _isReanalyzing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Re-analysis failed.")));
        return;
      }

      final diagnosis = (result['label'] ?? 'N/A') as String;
      final probs = Map<String, double>.from(
        (result['probabilities'] as Map).map(
          (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
        ),
      );
      final probsJson = jsonEncode(probs);
      final nowIso = DateTime.now().toIso8601String();

      final db = DatabaseHelper.instance;
      await db.upsertAnalysisByRecordId(
        recordId,
        diagnosis: diagnosis,
        probabilitiesJson: probsJson,
        analysisDateIso: nowIso,
      );

      final melBytes = await _tfliteService.generateMelImageBytes(filePath);
      if (!mounted) return;
      setState(() {
        _currentDiagnosis = diagnosis;
        _currentProbabilities = probs;
        _melPng = melBytes;
        _isReanalyzing = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Re-analysis complete.")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isReanalyzing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Re-analysis failed: $e")));
    }
  }

  Future<void> _showEditDialog() async {
    final db = DatabaseHelper.instance;
    final nameCtrl = TextEditingController(text: _localReport['name'] ?? '');
    final genderCtrl = TextEditingController(text: _localReport['gender'] ?? '');
    final birthdayCtrl =
        TextEditingController(text: _localReport['birthday'] ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Patient Info"),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: "Name")),
            const SizedBox(height: 8),
            TextField(
                controller: genderCtrl,
                decoration: const InputDecoration(labelText: "Gender")),
            const SizedBox(height: 8),
            TextField(
              controller: birthdayCtrl,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: "Birthday",
                suffixIcon: Icon(Icons.calendar_today),
              ),
              onTap: () async {
                DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.tryParse(birthdayCtrl.text) ?? DateTime(2000),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  birthdayCtrl.text =
                      DateFormat('yyyy-MM-dd').format(picked);
                }
              },
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Theme.of(context).colorScheme.surface,
            ),
            child: const Text("Save"),
            onPressed: () async {
              final patientId = _localReport['patient_id'] as int?;
              if (patientId != null) {
                await db.database.then((conn) {
                  conn.update(
                    'patients',
                    {
                      'name': nameCtrl.text.trim(),
                      'gender': genderCtrl.text.trim(),
                      'birthday': birthdayCtrl.text.trim(),
                    },
                    where: 'patient_id = ?',
                    whereArgs: [patientId],
                  );
                });

                if (!context.mounted) return;
                final updated = Map<String, dynamic>.from(_localReport);
                updated['name'] = nameCtrl.text.trim();
                updated['gender'] = genderCtrl.text.trim();
                updated['birthday'] = birthdayCtrl.text.trim();

                setState(() {
                  _localReport = updated;
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("✅ Patient info updated.")),
                );
                Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final recordId = _localReport['record_id'] as int?;
    if (recordId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: const Text(
            "Are you sure you want to delete this record? This cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Theme.of(context).colorScheme.surface,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = DatabaseHelper.instance;
      await db.deleteRecordById(recordId);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🗑 Report deleted successfully.")),
      );
    }
  }

  Future<void> _handleExportPdf() async {
    if (_melPng == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Generate Spectrogram First"),
          content: const Text(
              "Please generate the Mel-Spectrogram before exporting the report to PDF."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Theme.of(context).colorScheme.surface,
              ),
              child: const Text("Generate Now"),
              onPressed: () {
                Navigator.pop(context);
                _generateMelIfNeeded();
              },
            ),
          ],
        ),
      );
      return;
    }

    await PdfExporter.exportSingleReport(
      report: {
        'patient_id': _localReport['patient_id'],
        'name': _localReport['name'],
        'birthday': _localReport['birthday'],
        'age': _localReport['age'],
        'gender': _localReport['gender'],
        'file_path': _localReport['file_path'],
        'record_date': _localReport['record_date'],
        'diagnosis': _currentDiagnosis,
        'probabilities': _currentProbabilities,
      },
      practitionerName: _practitionerName,
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
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.surface),
        title: Text(
          'Report for ${_localReport['name'] ?? 'Unnamed'}',
          style: TextStyle(color: Theme.of(context).colorScheme.surface),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: Theme.of(context).colorScheme.surface),
            onSelected: (value) {
              if (value == 'reanalyze') _reAnalyze();
              if (value == 'edit') _showEditDialog();
              if (value == 'delete') _confirmDelete();
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
              PopupMenuDivider(),
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
                  Text("Delete Record"),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDetailSection(patientIdFormatted, dateString),
            const SizedBox(height: 16),
            _buildAnalysisSection(),
            const SizedBox(height: 16),
            _buildSpectrogramSection(),
            const SizedBox(height: 16),
            _buildWaveformSection(),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: Icon(Icons.picture_as_pdf, color: Theme.of(context).colorScheme.surface),
        label:
            Text("Export PDF", style: TextStyle(color: Theme.of(context).colorScheme.surface)),
        onPressed: _handleExportPdf,
      ),
    );
  }

  Widget _buildDetailSection(String patientIdFormatted, String dateString) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
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
          _buildRow('File:', (_localReport['file_path'] ?? '').split('/').last),
          _buildRow('Recorded:', dateString),
        ]),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7)))),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ]),
    );
  }

  Widget _buildAnalysisSection() {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("AI Analysis",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Divider(height: 20),
          _buildRow('Classification:', _currentDiagnosis),
          const SizedBox(height: 10),
          if (_currentProbabilities.isNotEmpty)
            ..._currentProbabilities.entries
                .map((entry) => _buildProbabilityRow(entry.key, entry.value))
          else
            const Text("No probabilities available.")
        ]),
      ),
    );
  }

  Widget _buildProbabilityRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(children: [
        Expanded(
            flex: 2,
            child: Text(label,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)))),
        Expanded(
          flex: 5,
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            color: UIHelpers.getStatusColor(label),
            minHeight: 12,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        Expanded(
            flex: 2,
            child: Text("${(value * 100).toStringAsFixed(2)}%",
                textAlign: TextAlign.end)),
      ]),
    );
  }

  Widget _buildSpectrogramSection() {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Text("Model Input (Mel-Spectrogram)",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Divider(height: 20),
          if (_melPng != null)
            ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _melPng!, 
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
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
                    foregroundColor: Theme.of(context).colorScheme.surface),
                onPressed: _generateMelIfNeeded,
                child: const Text('Generate Spectrogram'),
              ),
            ]),
        ]),
      ),
    );
  }

  Widget _buildWaveformSection() {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text("Raw Waveform & Playback",
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
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
        final processingState = playerState?.processingState;
        final playing = playerState?.playing ?? false;

        IconData icon = Icons.play_arrow_rounded;
        if (playing) {
          icon = Icons.pause_rounded;
        } else if (processingState == ProcessingState.completed) {
          icon = Icons.replay_rounded;
        }

        return Column(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
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
          ),
        ]);
      },
    );
  }
}
