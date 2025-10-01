// lib/pages/report_generated.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../database_helper.dart';

class ReportGeneratedPage extends StatefulWidget {
  final String patientName;
  final int patientAge;
  final String patientGender;
  final String filePath;
  final DateTime recordedDate;
  final String classification;
  final double confidence;

  const ReportGeneratedPage({
    super.key,
    required this.patientName,
    required this.patientAge,
    required this.patientGender,
    required this.filePath,
    required this.recordedDate,
    required this.classification,
    required this.confidence,
  });

  @override
  State<ReportGeneratedPage> createState() => _ReportGeneratedPageState();
}

class _ReportGeneratedPageState extends State<ReportGeneratedPage> {
  Future<List<FlSpot>>? _waveformFuture;
  int? _patientId;

  @override
  void initState() {
    super.initState();
    _waveformFuture = _loadWaveformData();
    _saveReportToDatabase();
  }

  Future<void> _saveReportToDatabase() async {
    final nameToSave =
        widget.patientName.trim().isEmpty ? 'Unnamed' : widget.patientName;

    // Insert user (returns ID)
    final userId = await DatabaseHelper.instance.insertUser({
      'name': nameToSave,
      'age': widget.patientAge,
      'gender': widget.patientGender,
    });

    setState(() => _patientId = userId);

    // Insert record
    final recordId = await DatabaseHelper.instance.insertRecord({
      'user_id': userId,
      'file_path': widget.filePath,
    });

    // Insert analysis
    await DatabaseHelper.instance.insertAnalysis({
      'record_id': recordId,
      'diagnosis': widget.classification,
      'confidence': widget.confidence,
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
    final confidencePercent = (widget.confidence * 100).toStringAsFixed(1);

    final patientIdFormatted = _patientId != null
        ? DatabaseHelper.instance.formatPatientId(_patientId!)
        : 'N/A';

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

          // Patient Details
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

          // Waveform
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
                    Text('Phonocardiogram (PCG)',
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
                    _buildDetailRow(
                        "Confidence Score:", "$confidencePercent%"),
                  ]),
            ),
          ),
          const SizedBox(height: 80),
        ]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: implement export PDF
        },
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text("Export PDF"),
        backgroundColor: const Color(0xFFC31C42),
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
