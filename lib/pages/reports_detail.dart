// lib/pages/report_detail.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

class ReportDetailPage extends StatefulWidget {
  final Map<String, dynamic> report;

  const ReportDetailPage({super.key, required this.report});

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  final AudioPlayer _player = AudioPlayer();
  Future<List<FlSpot>>? _waveformFuture;

  @override
  void initState() {
    super.initState();
    _waveformFuture = _loadWaveformData();
    _player.setFilePath(widget.report['filePath']);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<List<FlSpot>> _loadWaveformData() async {
    final file = File(widget.report['filePath']);
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes <= 44) return [];
    
    final pcmBytes = bytes.sublist(44);
    final byteData = ByteData.view(pcmBytes.buffer);

    final spots = <FlSpot>[];
    for (int i = 0; i < pcmBytes.lengthInBytes; i += 2) {
      spots.add(FlSpot((i / 2).toDouble(), byteData.getInt16(i, Endian.little) / 32768.0));
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    final date = DateTime.parse(widget.report['recordedDate']);
    return Scaffold(
      appBar: AppBar(
        title: Text('Report for ${widget.report['patientName']}', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionCard("Playback & Waveform", [
              SizedBox(
                height: 150,
                child: FutureBuilder<List<FlSpot>>(
                  future: _waveformFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Could not load waveform."));
                    
                    return LineChart(
                      LineChartData(
                        titlesData: const FlTitlesData(show: false),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: snapshot.data!,
                            isCurved: false,
                            color: const Color(0xFFC31C42),
                            barWidth: 1,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                        minY: -1, maxY: 1,
                        lineTouchData: const LineTouchData(enabled: false),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, snapshot) {
                  final playerState = snapshot.data;
                  final processingState = playerState?.processingState;
                  final playing = playerState?.playing;
                  
                  IconData icon = Icons.play_arrow;
                  if (playing == true) {
                    icon = Icons.pause;
                  } else if (processingState == ProcessingState.completed) {
                    icon = Icons.replay;
                  }

                  return Center(
                    child: IconButton(
                      iconSize: 48,
                      icon: Icon(icon, color: const Color(0xFFC31C42)),
                      onPressed: () {
                        if (playing == true) {
                          _player.pause();
                        } else if (processingState == ProcessingState.completed) {
                          _player.seek(Duration.zero);
                        } else {
                          _player.play();
                        }
                      },
                    ),
                  );
                },
              ),
            ]),
            const SizedBox(height: 16),
            _buildSectionCard("Report Details", [
              _buildDetailRow("Name:", widget.report['patientName']),
              _buildDetailRow("File:", widget.report['filePath'].split('/').last),
              _buildDetailRow("Recorded:", DateFormat('MMMM d, yyyy HH:mm').format(date)),
              _buildDetailRow("Classification:", widget.report['classification'] ?? 'N/A'),
              _buildDetailRow("Confidence:", widget.report['confidence'] ?? 'N/A'),
            ]),
          ],
        ),
      ),
    );
  }

  // --- Complete Helper Methods ---
  Widget _buildSectionCard(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 20, thickness: 1),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isSelectable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
          Expanded(
            child: isSelectable
                ? SelectableText(value, textAlign: TextAlign.end)
                : Text(value, textAlign: TextAlign.end, softWrap: true),
          ),
        ],
      ),
    );
  }
}