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

  @override
  void initState() {
    super.initState();
    _waveformFuture = _loadWaveformData();
    _initializeState();
    _loadPractitionerName();

    final path = widget.report['file_path'] as String?;
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
        _practitionerName = prefs.getString('practitioner_name') ?? 'Practitioner';
      });
    }
  }

  void _initializeState() {
    _currentDiagnosis = widget.report['diagnosis'] ?? 'N/A';
    _currentProbabilities = {};
    final probsJson = widget.report['probabilities'] as String?;
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
    final path = widget.report['file_path'] as String?;
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

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  Future<void> _generateMelIfNeeded() async {
    if (_melPng != null) return;
    final filePath = widget.report['file_path'] as String?;
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
    final filePath = widget.report['file_path'] as String?;
    final recordId = widget.report['record_id'] as int?;

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Re-analysis failed: $e")),
      );
    }
  }

  Future<void> _showEditDialog() async {
    final nameCtrl = TextEditingController(text: widget.report['name'] ?? '');
    final genderCtrl = TextEditingController(text: widget.report['gender'] ?? '');
    final birthdayCtrl = TextEditingController(text: widget.report['birthday'] ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Patient Info"),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name")),
            const SizedBox(height: 8),
            TextField(controller: genderCtrl, decoration: const InputDecoration(labelText: "Gender")),
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
                  initialDate: DateTime.tryParse(birthdayCtrl.text) ?? DateTime(2000),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  birthdayCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                }
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text("Save"),
            onPressed: () async {
              final db = DatabaseHelper.instance;
              final patientId = widget.report['patient_id'] as int?;
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
                setState(() {
                  widget.report['name'] = nameCtrl.text.trim();
                  widget.report['gender'] = genderCtrl.text.trim();
                  widget.report['birthday'] = birthdayCtrl.text.trim();
                });
              }
              if (!context.mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("✅ Patient info updated.")),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final recordId = widget.report['record_id'] as int?;
    if (recordId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Record"),
        content: const Text("Are you sure you want to delete this record? This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("🗑 Record deleted successfully.")));
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
            TextButton(child: const Text("Cancel"), onPressed: () => Navigator.pop(context)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
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
        'patient_id': widget.report['patient_id'],
        'name': widget.report['name'],
        'birthday': widget.report['birthday'],
        'age': widget.report['age'],
        'gender': widget.report['gender'],
        'file_path': widget.report['file_path'],
        'record_date': widget.report['record_date'],
        'diagnosis': _currentDiagnosis,
        'probabilities': _currentProbabilities,
      },
      practitionerName: _practitionerName,
    );
  }

  Widget _buildCard(BuildContext context, {required String title, required Widget child}) {
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Divider(height: 20),
          child,
        ]),
      ),
    );
  }

  Widget _buildProbabilityRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(children: [
        Expanded(flex: 2, child: Text(label, style: TextStyle(color: Colors.grey.shade700))),
        Expanded(
          flex: 5,
          child: LinearProgressIndicator(
            value: value,
            backgroundColor: Colors.grey.shade300,
            color: UIHelpers.getStatusColor(label),
            minHeight: 12,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text("${(value * 100).toStringAsFixed(2)}%", textAlign: TextAlign.end),
        ),
      ]),
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
          Row(children: [
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                return Text(_formatDuration(position));
              },
            ),
            Expanded(
              child: StreamBuilder<Duration?>(
                stream: _player.durationStream,
                builder: (context, snapshot) {
                  final duration = snapshot.data ?? Duration.zero;
                  return Slider(
                    value: _player.position.inMilliseconds
                        .toDouble()
                        .clamp(0.0, duration.inMilliseconds.toDouble()),
                    onChanged: (value) {
                      _player.seek(Duration(milliseconds: value.toInt()));
                    },
                    min: 0.0,
                    max: duration.inMilliseconds.toDouble(),
                    activeColor: AppColors.primary,
                    inactiveColor: Colors.grey.shade300,
                  );
                },
              ),
            ),
            Text(_formatDuration(_player.duration ?? Duration.zero)),
          ]),
        ]);
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54))),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recordDate = widget.report['record_date'];
    String dateString = 'N/A';
    if (recordDate is String) {
      try {
        dateString = DateFormat('MMMM d, yyyy HH:mm').format(DateTime.parse(recordDate));
      } catch (_) {}
    }

    final patientId = widget.report['patient_id'];
    final patientIdFormatted = patientId != null
        ? DatabaseHelper.instance.formatPatientId(patientId as int)
        : 'N/A';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Report for ${widget.report['name'] ?? 'Unnamed'}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'reanalyze') _reAnalyze();
              if (value == 'edit') _showEditDialog();
              if (value == 'delete') _confirmDelete();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reanalyze',
                child: Row(children: [
                  Icon(Icons.refresh, color: AppColors.deep),
                  SizedBox(width: 8),
                  Text("Re-analyze"),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit, color: AppColors.deep),
                  SizedBox(width: 8),
                  Text("Edit Patient Info"),
                ]),
              ),
              const PopupMenuItem(
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _buildCard(
            context,
            title: 'Patient Details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Patient ID:', patientIdFormatted),
                _buildDetailRow('Name:', widget.report['name'] ?? 'Unnamed'),
                _buildDetailRow(
                    'Birthday:',
                    (() {
                      final bday = widget.report['birthday'];
                      if (bday == null || bday.toString().isEmpty) return 'N/A';
                      try {
                        return DateFormat('MMMM d, yyyy').format(DateTime.parse(bday));
                      } catch (_) {
                        return bday.toString();
                      }
                    })()),
                _buildDetailRow('Age:', widget.report['age']?.toString() ?? 'N/A'),
                _buildDetailRow('Gender:', widget.report['gender'] ?? 'N/A'),
                _buildDetailRow('File:', (widget.report['file_path'] ?? '').split('/').last),
                _buildDetailRow('Recorded:', dateString),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildCard(
            context,
            title: 'AI Analysis',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildDetailRow('Classification:', _currentDiagnosis),
              if (_currentProbabilities.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text("Detailed Breakdown:",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 8),
                ..._currentProbabilities.entries
                    .map((entry) => _buildProbabilityRow(entry.key, entry.value)),
              ] else ...[
                const SizedBox(height: 8),
                const Text("No probabilities available.")
              ]
            ]),
          ),
          const SizedBox(height: 16),
          _buildCard(
            context,
            title: 'Model Input (Mel-Spectrogram)',
            child: Column(children: [
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
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _generateMelIfNeeded,
                    child: const Text('Generate Spectrogram'),
                  )
                ])
            ]),
          ),
          const SizedBox(height: 16),
          _buildCard(
            context,
            title: 'Raw Waveform & Playback',
            child: Column(children: [
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
                            dotData: const FlDotData(show: false)),
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
          const SizedBox(height: 80),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
        label: const Text("Export PDF", style: TextStyle(color: Colors.white)),
        onPressed: _handleExportPdf,
      ),
    );
  }
}
