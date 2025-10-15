// lib\pages\report_generated.dart
import 'dart:async';
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
import '../utils/pdf_exporter.dart';

class ReportGeneratedPage extends StatefulWidget {
  final int patientId;
  final String patientName;
  final dynamic patientAge;
  final String patientGender;
  final String? symptoms;
  final String filePath;
  final DateTime recordedDate;
  final String classification;
  final Map<String, dynamic> probabilities;
  final String? patientBirthday;
  final Uint8List? melPngBytes;

  const ReportGeneratedPage({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.patientAge,
    required this.patientGender,
    required this.filePath,
    required this.recordedDate,
    required this.classification,
    required this.probabilities,
    this.patientBirthday,
    this.melPngBytes,
    this.symptoms,
  });

  @override
  State<ReportGeneratedPage> createState() => _ReportGeneratedPageState();
}

class _ReportGeneratedPageState extends State<ReportGeneratedPage> {
  final AudioPlayer _player = AudioPlayer();
  late final Future<List<FlSpot>> _waveformFuture;
  String _practitionerName = "Practitioner";

  @override
  void initState() {
    super.initState();
    _waveformFuture = _loadWaveformData();
    _initAudioPlayer();
    _loadPractitionerName();
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

  Future<void> _initAudioPlayer() async {
    try {
      if (await File(widget.filePath).exists()) {
        await _player.setFilePath(widget.filePath);
      }
    } catch (e) {
      debugPrint("Error loading audio file: $e");
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<List<FlSpot>> _loadWaveformData() async {
    final file = File(widget.filePath);
    if (!await file.exists()) return [];
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes <= 44) return [];
    final pcmBytes = bytes.sublist(44);
    final byteData = ByteData.view(pcmBytes.buffer);
    final spots = <FlSpot>[];
    const int downsamplingFactor = 50;
    for (int i = 0; i < pcmBytes.lengthInBytes; i += (2 * downsamplingFactor)) {
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

  @override
  Widget build(BuildContext context) {
    final patientIdFormatted =
        DatabaseHelper.instance.formatPatientId(widget.patientId);

    String birthdayDisplay = "-";
    if (widget.patientBirthday != null && widget.patientBirthday!.isNotEmpty) {
      try {
        final parsed = DateTime.parse(widget.patientBirthday!);
        birthdayDisplay = DateFormat('MMMM d, yyyy').format(parsed);
      } catch (_) {
        birthdayDisplay = widget.patientBirthday!;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Analysis for ${widget.patientName}",
            style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
        backgroundColor: AppColors.primary,
        leading: IconButton(
          icon: Icon(Icons.close, color: Theme.of(context).colorScheme.surface),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Text('Analysis Complete!',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800])),
          ),
          const SizedBox(height: 16),

          // 1️⃣ 🩺 Patient Details
          _buildCard(
            title: 'Patient Details',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildDetailRow("Patient ID:", patientIdFormatted),
              _buildDetailRow("Name:", widget.patientName),
              _buildDetailRow("Birthday:", birthdayDisplay),
              _buildDetailRow("Age:", widget.patientAge.toString()),
              _buildDetailRow("Gender:", widget.patientGender),
              _buildDetailRow("Symptoms:", widget.symptoms ?? "-"),
              _buildDetailRow("File:", widget.filePath.split('/').last),
              _buildDetailRow("Recorded:",
                  DateFormat('MMMM d, yyyy HH:mm').format(widget.recordedDate)),
            ]),
          ),
          const SizedBox(height: 16),

          // 2️⃣ 🤖 AI Analysis
          _buildCard(
            title: 'AI Analysis',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _buildDetailRow("Classification:", widget.classification),
              const SizedBox(height: 10),
              Text("Detailed Breakdown:",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              if (widget.probabilities.isEmpty)
                Text("No probabilities available",
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface))
              else
                ...widget.probabilities.entries.map((entry) {
                  return _buildProbabilityRow(
                      entry.key, (entry.value as num).toDouble());
                }),
            ]),
          ),
          const SizedBox(height: 16),

          // 3️⃣ 🎨 Model Input (Mel-Spectrogram)
          _buildCard(
            title: 'Model Input (Mel-Spectrogram)',
            child: widget.melPngBytes != null
                ? Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF1E1E1E)
                        : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    widget.melPngBytes!,
                    width: double.infinity,
                    fit: BoxFit.contain, // 🔹 stretch width but keep proportions
                  ),
                )
              )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Text("Spectrogram not generated."),
                    ),
                  ),
          ),
          const SizedBox(height: 16),

          // 4️⃣ 🔊 Raw Waveform & Playback
          _buildCard(
            title: 'Raw Waveform & Playback',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 150,
                child: FutureBuilder<List<FlSpot>>(
                  future: _waveformFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                          child: Text("Could not load waveform."));
                    }
                    return LineChart(LineChartData(
                      titlesData: const FlTitlesData(show: false),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: snapshot.data!,
                          isCurved: false,
                          color: AppColors.primary,
                          barWidth: 1.2,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                      minY: -1,
                      maxY: 1,
                      lineTouchData:
                          const LineTouchData(enabled: false),
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
        onPressed: () async {
          await PdfExporter.exportSingleReport(
            report: {
              'patient_id': widget.patientId,
              'name': widget.patientName,
              'birthday': widget.patientBirthday ?? '',
              'age': widget.patientAge,
              'gender': widget.patientGender,
              'symptoms': widget.symptoms ?? '-',
              'file_path': widget.filePath,
              'record_date': widget.recordedDate.toIso8601String(),
              'diagnosis': widget.classification,
              'probabilities': widget.probabilities,
              'mel_png': widget.melPngBytes,
            },
            practitionerName: _practitionerName,
          );
        },
        backgroundColor: AppColors.primary,
        icon: Icon(
          Icons.picture_as_pdf,
          color: Theme.of(context).colorScheme.onPrimary, // ✅ match reports_detail.dart
        ),
        label: Text(
          "Export PDF",
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

  Widget _buildProbabilityRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(children: [
        Expanded(flex: 2, child: Text(label, style: TextStyle(color: Colors.grey.shade700))),
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
              textAlign: TextAlign.end),
        ),
      ]),
    );
  }

  Widget _buildDetailRow(String label, String value,
      {bool isSelectable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("$label ",
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
        Expanded(
            child: isSelectable
                ? SelectableText(value, textAlign: TextAlign.end)
                : Text(value, textAlign: TextAlign.end)),
      ]),
    );
  }
}
