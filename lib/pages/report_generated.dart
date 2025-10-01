// lib/pages/report_generated.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cardioscope_app/utils/ui_helpers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

import '../database_helper.dart';

class ReportGeneratedPage extends StatefulWidget {
  final String patientName;
  final int patientAge;
  final String patientGender;
  final String filePath;
  final DateTime recordedDate;
  final String classification;
  final double confidence;
  final Map<String, double> probabilities;

  const ReportGeneratedPage({
    super.key,
    required this.patientName,
    required this.patientAge,
    required this.patientGender,
    required this.filePath,
    required this.recordedDate,
    required this.classification,
    required this.confidence,
    required this.probabilities,
  });

  @override
  State<ReportGeneratedPage> createState() => _ReportGeneratedPageState();
}

class _ReportGeneratedPageState extends State<ReportGeneratedPage> {
  final AudioPlayer _player = AudioPlayer();
  Future<List<FlSpot>>? _waveformFuture;
  int? _patientId;

  @override
  void initState() {
    super.initState();
    _waveformFuture = _loadWaveformData();
    _saveReportToDatabase();
    _initAudioPlayer();
  }

  Future<void> _initAudioPlayer() async {
    try {
      if (await File(widget.filePath).exists()) {
        await _player.setFilePath(widget.filePath);
      }
    } catch (e) {
      debugPrint("Error loading audio file for playback: $e");
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _saveReportToDatabase() async {
    final nameToSave =
        widget.patientName.trim().isEmpty ? 'Unnamed' : widget.patientName;

    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      var existingPatient = await txn.query('users',
          where: 'name = ? AND age = ? AND gender = ?',
          whereArgs: [nameToSave, widget.patientAge, widget.patientGender],
          limit: 1);

      int userId;
      if (existingPatient.isNotEmpty) {
        userId = existingPatient.first['id'] as int;
      } else {
        userId = await txn.insert('users', {
          'name': nameToSave,
          'age': widget.patientAge,
          'gender': widget.patientGender,
        });
      }

      if (mounted) {
        setState(() => _patientId = userId);
      }

      final recordId = await txn.insert('heart_sound_records', {
        'user_id': userId,
        'file_path': widget.filePath,
        'record_date': widget.recordedDate.toIso8601String(),
      });

      await txn.insert('mitral_valve_analysis', {
        'record_id': recordId,
        'diagnosis': widget.classification,
        'confidence': widget.confidence,
        'probabilities': jsonEncode(widget.probabilities),
        'analysis_date': DateTime.now().toIso8601String(),
      });
    });
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
    for (int i = 0;
        i < pcmBytes.lengthInBytes;
        i += (2 * downsamplingFactor)) {
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
    final confidencePercent = (widget.confidence * 100).toStringAsFixed(2);
    final patientIdFormatted = _patientId != null
        ? DatabaseHelper.instance.formatPatientId(_patientId!)
        : 'Generating...';

    return Scaffold(
      appBar: AppBar(
        title: Text("Analysis for ${widget.patientName}",
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
              child: Text('Analysis Complete!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold, color: Colors.green[800]))),
          const SizedBox(height: 16),
          Card(
            color: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Patient Details',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Divider(height: 20),
                    _buildDetailRow("Patient ID:", patientIdFormatted),
                    _buildDetailRow("Name:", widget.patientName),
                    _buildDetailRow("Age:", widget.patientAge.toString()),
                    _buildDetailRow("Gender:", widget.patientGender),
                    _buildDetailRow("File Location:", widget.filePath,
                        isSelectable: true),
                    _buildDetailRow("Recorded:",
                        DateFormat('MMMM d, yyyy HH:mm').format(widget.recordedDate)),
                  ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Playback & Waveform',
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
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
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
                                  color: const Color(0xFFC31C42),
                                  barWidth: 1,
                                  dotData: const FlDotData(show: false))
                            ],
                            minY: -1,
                            maxY: 1,
                            lineTouchData: const LineTouchData(enabled: false),
                          ));
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildPlaybackControls(),
                  ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Analysis',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Divider(height: 20),
                  _buildDetailRow("Classification:", widget.classification),
                  _buildDetailRow("Confidence Score:", "$confidencePercent%"),
                  const SizedBox(height: 10),
                  const Text("Detailed Breakdown:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 8),
                  ...widget.probabilities.entries.map((entry) {
                    return _buildProbabilityRow(entry.key, entry.value);
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: implement export PDF
        },
        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
        label: const Text("Export PDF", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
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

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(icon, color: const Color(0xFFC31C42)),
              iconSize: 48,
              onPressed: () {
                if (playing) {
                  _player.pause();
                } else if (processingState == ProcessingState.completed) {
                  _player.seek(Duration.zero);
                } else {
                  _player.play();
                }
              },
            ),
            Row(
              children: [
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
                        value: _player.position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble()),
                        onChanged: (value) {
                          _player.seek(Duration(milliseconds: value.toInt()));
                        },
                        min: 0.0,
                        max: duration.inMilliseconds.toDouble(),
                        activeColor: const Color(0xFFC31C42),
                        inactiveColor: Colors.grey.shade300,
                      );
                    },
                  ),
                ),
                Text(_formatDuration(_player.duration ?? Duration.zero)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildProbabilityRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
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
          Expanded(flex: 2, child: Text("${(value * 100).toStringAsFixed(2)}%", textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value,
      {bool isSelectable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("$label ",
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.black54)),
        Expanded(
            child: isSelectable
                ? SelectableText(value, textAlign: TextAlign.end)
                : Text(value, textAlign: TextAlign.end)),
      ]),
    );
  }
}