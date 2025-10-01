// lib/pages/reports_detail.dart
import 'dart:io';
import 'dart:typed_data';

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

  @override
  Widget build(BuildContext context) {
    final recordDate = widget.report['record_date'];
    String dateString = 'N/A';
    if (recordDate is String) {
      try {
        dateString = DateFormat('MMMM d, yyyy HH:mm')
            .format(DateTime.parse(recordDate));
      } catch (_) {}
    }

    final confidenceValue = widget.report['confidence'];
    String confidenceString = 'N/A';
    if (confidenceValue is num) {
      confidenceString = '${(confidenceValue * 100).toStringAsFixed(1)}%';
    }

    final userId = widget.report['user_id'];
    final patientId = userId != null
        ? DatabaseHelper.instance.formatPatientId(userId as int)
        : 'N/A';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFC31C42),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Report for ${widget.report['name'] ?? 'Unnamed'}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Patient Details
          Card(
            color: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Patient Details',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Divider(height: 20),
                _buildDetailRow('Patient ID:', patientId),
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

          // Playback & Waveform
          Card(
            color: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                            color: const Color(0xFFC31C42),
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
                StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, snap) {
                    final state = snap.data;
                    final playing = state?.playing == true;
                    final processingState = state?.processingState;
                    IconData icon = Icons.play_arrow;
                    if (playing) {
                      icon = Icons.pause;
                    } else if (processingState ==
                        ProcessingState.completed) {
                      icon = Icons.replay;
                    }

                    return Center(
                      child: IconButton(
                        iconSize: 48,
                        icon: Icon(icon, color: const Color(0xFFC31C42)),
                        onPressed: () async {
                          try {
                            if (playing) {
                              await _player.pause();
                            } else if (processingState ==
                                ProcessingState.completed) {
                              await _player.seek(Duration.zero);
                              await _player.play();
                            } else {
                              await _player.play();
                            }
                          } catch (e) {
                            if (!mounted) return;
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Playback error: $e')),
                              );
                            }
                          }
                        },
                      ),
                    );
                  },
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // AI Analysis
          Card(
            color: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI Analysis',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Divider(height: 20),
                _buildDetailRow('Classification:',
                    widget.report['diagnosis'] ?? 'Pending'),
                _buildDetailRow('Confidence:', confidenceString),
              ]),
            ),
          ),
        ]),
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
