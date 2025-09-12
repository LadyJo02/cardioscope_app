import 'dart:io';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database_helper.dart';

class ReportGeneratedPage extends StatefulWidget {
  final String patientName;
  final String filePath;
  final DateTime recordedDate;

  const ReportGeneratedPage({
    super.key,
    required this.patientName,
    required this.filePath,
    required this.recordedDate,
  });

  @override
  State<ReportGeneratedPage> createState() => _ReportGeneratedPageState();
}

class _ReportGeneratedPageState extends State<ReportGeneratedPage> {
  Future<List<FlSpot>>? _waveformFuture;

  @override
  void initState() {
    super.initState();
    _waveformFuture = _loadWaveformData();
    _saveReportToDatabase();
  }

  Future<void> _saveReportToDatabase() async {
    final report = {
      'patientName': widget.patientName,
      'filePath': widget.filePath,
      'recordedDate': widget.recordedDate.toIso8601String(),
      'classification': 'Pending',
      'confidence': 'N/A',
    };
    await DatabaseHelper.instance.createReport(report);
  }

  Future<List<FlSpot>> _loadWaveformData() async {
    final file = File(widget.filePath);
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes <= 44) return [];

    final pcmBytes = bytes.sublist(44); // skip WAV header
    final byteData = ByteData.view(pcmBytes.buffer);
    final spots = <FlSpot>[];

    const int downsamplingFactor = 50; // avoid too many points
    for (int i = 0; i < pcmBytes.lengthInBytes; i += (2 * downsamplingFactor)) {
      if (i + 2 <= pcmBytes.lengthInBytes) {
        final sample = byteData.getInt16(i, Endian.little) / 32768.0;
        spots.add(FlSpot((i / 2).toDouble(), sample));
      }
    }
    return spots;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Analysis for ${widget.patientName}",
            style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                'Recording Saved!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: Colors.green[800]),
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard("Patient Details", [
              _buildDetailRow("Name:", widget.patientName),
              _buildDetailRow("File Location:", widget.filePath,
                  isSelectable: true),
              _buildDetailRow("Recorded:",
                  DateFormat('MMMM d, yyyy HH:mm').format(widget.recordedDate)),
            ]),
            const SizedBox(height: 16),
            _buildSectionCard("Phonocardiogram (PCG)", [
              SizedBox(
                height: 150,
                child: FutureBuilder<List<FlSpot>>(
                  future: _waveformFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                          child: Text("Could not load waveform."));
                    }

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
                        minY: -1,
                        maxY: 1,
                        lineTouchData: const LineTouchData(enabled: false),
                      ),
                    );
                  },
                ),
              ),
            ]),
            const SizedBox(height: 16),
            _buildSectionCard("AI Analysis (Placeholder)", [
              _buildDetailRow("Classification:", "Pending..."),
              _buildDetailRow("Confidence Score:", "N/A"),
            ]),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
         
        },
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text("Export PDF"),
        backgroundColor: const Color(0xFFC31C42),
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFFFFFFFF),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 20, thickness: 1),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value,
      {bool isSelectable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label ",
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black54)),
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
