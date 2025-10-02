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

import '../database_helper.dart';

class ReportDetailPage extends StatefulWidget {
  final Map<String, dynamic> report;
  const ReportDetailPage({super.key, required this.report});

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  final AudioPlayer _player = AudioPlayer();
  late final Future<List<FlSpot>> _waveformFuture;

  @override
  void initState() {
    super.initState();
    _waveformFuture = _loadWaveformData();
    final path = widget.report['file_path'] as String?;
    if (path != null && File(path).existsSync()) {
      _player.setFilePath(path).catchError((_) {
        debugPrint("Could not load audio file for playback.");
        return null;
      });
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
    final pcmBytes = bytes.sublist(44);
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

  @override
  Widget build(BuildContext context) {
    final recordDate = widget.report['record_date'];
    String dateString = 'N/A';
    if (recordDate is String) {
      try {
        dateString =
            DateFormat('MMMM d, yyyy HH:mm').format(DateTime.parse(recordDate));
      } catch (_) {}
    }

    final patientId = widget.report['patient_id'];
    final patientIdFormatted = patientId != null
        ? DatabaseHelper.instance.formatPatientId(patientId as int)
        : 'N/A';

    Map<String, double> probabilities = {};
    final probabilitiesJson = widget.report['probabilities'] as String?;
    if (probabilitiesJson != null) {
      try {
        probabilities = Map<String, double>.from(jsonDecode(probabilitiesJson));
      } catch (e) {
        debugPrint("Error decoding probabilities: $e");
      }
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Report for ${widget.report['name'] ?? 'Unnamed'}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            color: Colors.white,
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Patient Details',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Divider(height: 20),
                    _buildDetailRow('Patient ID:', patientIdFormatted),
                    _buildDetailRow('Name:', widget.report['name'] ?? 'Unnamed'),
                    _buildDetailRow(
                        'Age:', widget.report['age']?.toString() ?? 'N/A'),
                    _buildDetailRow('Gender:', widget.report['gender'] ?? 'N/A'),
                    _buildDetailRow('File:',
                        (widget.report['file_path'] ?? '').split('/').last),
                    _buildDetailRow('Recorded:', dateString),
                  ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.white,
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                      height: 140,
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
                                child: Text('No waveform available'));
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
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.white,
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Analysis',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Divider(height: 20),
                    _buildDetailRow(
                        'Classification:', widget.report['diagnosis'] ?? 'Pending'),
                    if (probabilities.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text("Detailed Breakdown:",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black54)),
                      const SizedBox(height: 8),
                      ...probabilities.entries.map((entry) {
                        return _buildProbabilityRow(entry.key, entry.value);
                      })
                    ]
                  ]),
            ),
          ),
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

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          Expanded(
              flex: 2,
              child:
                  Text(label, style: TextStyle(color: Colors.grey.shade700))),
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
              child: Text("${(value * 100).toStringAsFixed(2)}%",
                  textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.black54))),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ]),
    );
  }
}
