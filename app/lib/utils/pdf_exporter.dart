// 📄 lib/utils/pdf_exporter.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cardioscope_app/pages/pdf_viewer_page.dart';
import 'package:cardioscope_app/services/storage_service.dart';
import 'package:cardioscope_app/utils/latency_debug.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../database_helper.dart';
import '../services/tflite_service.dart';

class PdfExporter {
  static final _dateTimeFormat = DateFormat('MMMM d, yyyy, hh:mm a');
  static final _dateOnlyFormat = DateFormat('MMMM d, yyyy');

  // --------------------------------------------------------------------------
  // SINGLE REPORT
  // --------------------------------------------------------------------------
  static Future<void> exportSingleReport({
    required BuildContext context,
    required Map<String, dynamic> report,
    required String practitionerName,
    bool practitionerConsent = false,
  }) async {
    LatencyDebug.start("📄 PDF", "Generating single report for ${report['name'] ?? 'Unknown'}");

    final pdf = pw.Document();
    final logo = pw.MemoryImage(
      (await rootBundle.load('assets/images/app_logo.png')).buffer.asUint8List(),
    );
    final now = _dateTimeFormat.format(DateTime.now());

    // ✅ STEP 1 — use mel_png bytes if already provided
    pw.ImageProvider? melSpecImage;
    if (report['mel_png'] != null && report['mel_png'] is Uint8List) {
      melSpecImage = pw.MemoryImage(report['mel_png']);
    } else {
      melSpecImage = await _generateMelSpectrogramImage(report['file_path']);
    }

    // ✅ STEP 2 — load waveform
    final waveformSamples = await _loadWaveformSamples(report['file_path']);

    // ✅ STEP 3 — normalize probabilities
    if (report['probabilities'] is Map<String, dynamic>) {
      report['probabilities'] = jsonEncode(report['probabilities']);
    }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(
                practitionerName, 
                now, 
                logo,
                practitionerEmail: report['practitioner_email'] ?? '',
                practitionerConsent: practitionerConsent,
                ),
              pw.SizedBox(height: 12),
              _buildReportContent(
                report: report,
                melImage: melSpecImage,
                waveformSamples: waveformSamples,
              ),
              pw.Spacer(),
              _buildFooter(context),
            ],
          ),
        ),
      );

    // ✅ Save inside Downloads/CardioScope/Practitioner/.../Reports
try {
  final storage = StorageService();
  final basePath = await storage.getOrCreateBaseFolder();

  final patientId = report['patient_id'] ?? 0;
  final formattedId = DatabaseHelper.instance.formatPatientId(patientId);
  final pdfDir = await storage.getSinglePdfDir(basePath, formattedId);

  final patientName = (report['name'] ?? 'Patient').toString().replaceAll(RegExp(r'\s+'), '_');
  final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final filePath = '$pdfDir/Report_${formattedId}_${patientName}_$ts.pdf';

  final file = File(filePath);
  await file.writeAsBytes(await pdf.save());

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ Saved to: $filePath')),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerPage(
          filePath: file.path,
          title: 'Report for ${report['name'] ?? 'Patient'}',
        ),
      ),
    );
  }

  await Share.shareXFiles([XFile(file.path)], text: "CardioScope Report");
} catch (e) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ Failed to save PDF: $e')),
    );
  }
}
}

  // --------------------------------------------------------------------------
  // ✅ BATCH REPORTS 
  // --------------------------------------------------------------------------
  static Future<void> exportBatchReports({
    required BuildContext context,
    required List<Map<String, dynamic>> reports,
    required String practitionerName,
    bool practitionerConsent = false,
    required DateTimeRange dateRange,
  }) async {
    LatencyDebug.start("📄 PDF-Batch", "Batch export for ${reports.length} reports");

    final pdf = pw.Document();
    final logo = pw.MemoryImage(
      (await rootBundle.load('assets/images/app_logo.png')).buffer.asUint8List(),
    );
    final now = _dateTimeFormat.format(DateTime.now());

    for (final report in reports) {
      final melSpecImage = await _generateMelSpectrogramImage(report['file_path']);
      final waveformSamples = await _loadWaveformSamples(report['file_path']);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(
                practitionerName, 
                now, 
                logo,
                practitionerEmail: report['practitioner_email'] ?? '',
                practitionerConsent: practitionerConsent,
                ),
              pw.SizedBox(height: 12),
              _buildReportContent(
                report: report,
                melImage: melSpecImage,
                waveformSamples: waveformSamples,
              ),
              pw.Spacer(),
              _buildFooter(context),
            ],
          ),
        ),
      );
    }

    LatencyDebug.mark("📄 PDF-Batch", "All ${reports.length} pages built");

    // ✅ Save inside Downloads/CardioScope/Practitioner/.../Batch_Report
    try {
      final storage = StorageService();
      final basePath = await storage.getOrCreateBaseFolder();

      final pdfDir = await storage.getBatchPdfDir(basePath);

      final startDate = DateFormat('yyyyMMdd').format(dateRange.start);
      final endDate = DateFormat('yyyyMMdd').format(dateRange.end);
      final filename =
          "Batch_Report_${startDate}_to_$endDate.pdf";

      final file = File("$pdfDir/$filename");
      await file.writeAsBytes(await pdf.save());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Batch PDF saved to: ${file.path}')),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PdfViewerPage(
              filePath: file.path,
              title: 'Batch Reports (${reports.length})',
            ),
          ),
        );
      }

      await Share.shareXFiles([XFile(file.path)], text: "CardioScope Batch Reports");
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Failed to save batch PDF: $e')),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // HEADER
  // --------------------------------------------------------------------------
  static pw.Widget _buildHeader(
    String practitionerName,
    String now,
    pw.MemoryImage logo, {
    String? practitionerEmail,
    bool practitionerConsent = false,
  }) {
    final consentText = practitionerConsent
        ? "Patient Consent: Verified"
        : "Patient Consent: Not Verified";

    final consentColor = practitionerConsent
        ? const PdfColor.fromInt(0xFF2E7D32)
        : const PdfColor.fromInt(0xFFA03232);

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              "CardioScope Report",
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF2C3E50),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text("Generated by: $practitionerName",
                style: const pw.TextStyle(color: PdfColors.grey700)),
            if (practitionerEmail != null && practitionerEmail.isNotEmpty)
              pw.Text("Email: $practitionerEmail",
                  style: const pw.TextStyle(color: PdfColors.grey700)),
            pw.Text("Date Generated: $now",
                style: const pw.TextStyle(color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text(
              consentText,
              style: pw.TextStyle(
                color: consentColor,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 65, width: 65, child: pw.Image(logo)),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // BODY CONTENT
  // --------------------------------------------------------------------------
  static pw.Widget _buildReportContent({
    required Map<String, dynamic> report,
    required pw.ImageProvider? melImage,
    required List<double>? waveformSamples,
  }) {
    Map<String, dynamic> probs = {};
    if (report['probabilities'] is String &&
        (report['probabilities'] as String).isNotEmpty) {
      try {
        probs = jsonDecode(report['probabilities']);
      } catch (_) {}
    } else if (report['probabilities'] is Map<String, dynamic>) {
      probs = report['probabilities'];
    }

    final patientId = report['patient_id'] != null
        ? DatabaseHelper.instance.formatPatientId(report['patient_id'])
        : 'N/A';

    String recordDateStr = 'N/A';
    if (report['record_date'] != null) {
      try {
        recordDateStr =
            _dateTimeFormat.format(DateTime.parse(report['record_date']));
      } catch (_) {}
    }

    String birthdayStr = 'N/A';
    if (report['birthday'] != null && report['birthday'].toString().isNotEmpty) {
      try {
        birthdayStr =
            _dateOnlyFormat.format(DateTime.parse(report['birthday']));
      } catch (_) {
        birthdayStr = report['birthday'].toString();
      }
    }

    const double contentWidth = 420;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Patient Details"),
        _buildDetailRow("Patient ID:", patientId),
        _buildDetailRow("Name:", report['name'] ?? 'N/A'),
        _buildDetailRow("Birthday:", birthdayStr),
        _buildDetailRow("Age:", report['age']?.toString() ?? 'N/A'),
        _buildDetailRow("Gender:", report['gender'] ?? 'N/A'),
        _buildDetailRow("Symptoms:", report['symptoms']?.toString() ?? 'N/A'),
        pw.SizedBox(height: 6),
        _buildSectionHeader("Recording Details"),
        _buildDetailRow("Record Date:", recordDateStr),
        _buildDetailRow("File Path:", report['file_path'] ?? 'N/A'),
        pw.SizedBox(height: 8),
        _buildSectionHeader("Raw Waveform & Spectrogram"),
        pw.Center(
          child: pw.Column(
            children: [
              pw.Container(
                width: contentWidth,
                height: 120,
                margin: const pw.EdgeInsets.only(top: 6, bottom: 8),
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFF0F8F4),
                  borderRadius: pw.BorderRadius.circular(5),
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
                ),
                child: (waveformSamples != null && waveformSamples.isNotEmpty)
                    ? _waveformCanvas(waveformSamples)
                    : _waveformEmptyHint(),
              ),
              pw.Container(
                width: contentWidth,
                height: 160,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: melImage != null
                    ? pw.ClipRRect(
                        horizontalRadius: 5,
                        verticalRadius: 5,
                        child: pw.Image(
                          melImage,
                          fit: pw.BoxFit.fill,
                          alignment: pw.Alignment.topCenter,
                        ),
                      )
                    : pw.Center(
                        child: pw.Text("Spectrogram unavailable",
                            style: const pw.TextStyle(color: PdfColors.grey))),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        _buildSectionHeader("AI Analysis"),
        _buildDetailRow("Classification:",report['diagnosis'] ?? 'N/A'),
        if (probs.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          pw.Text("Detailed Probabilities:",
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
          pw.SizedBox(height: 2),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: probs.entries.map((e) {
              final pct = ((e.value as num?)?.toDouble() ?? 0.0) * 100;
              return pw.Text("- ${e.key}: ${pct.toStringAsFixed(2)}%",
                  style: const pw.TextStyle(color: PdfColors.black));
            }).toList(),
          ),
        ],
      ],
    );
  }

  // --------------------------------------------------------------------------
  // FOOTER
  // --------------------------------------------------------------------------
  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            "*This AI analysis is a preliminary screening tool and is not a substitute for a professional medical diagnosis.*",
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
          pw.Text(
            "Page ${context.pageNumber} of ${context.pagesCount}",
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // WAVEFORM + LOAD + MEL GENERATION (same)
  // --------------------------------------------------------------------------
  static pw.Widget _waveformCanvas(List<double> samples) {
    return pw.CustomPaint(
      painter: (canvas, size) {
        final w = size.x;
        final h = size.y;
        final midY = h / 2;
        if (samples.isEmpty) return;
        final maxAmp = samples.map((e) => e.abs()).reduce(max);
        final normalized =
            maxAmp > 0 ? samples.map((v) => v / maxAmp).toList() : samples;
        const int downsample = 50;
        final reduced = [
          for (int i = 0; i < normalized.length; i += downsample) normalized[i]
        ];
        if (reduced.length < 2) return;
        final stepX = w / (reduced.length - 1);
        canvas
          ..setStrokeColor(const PdfColor.fromInt(0xFFB2DFDB))
          ..setLineWidth(0.5)
          ..moveTo(0, midY)
          ..lineTo(w, midY)
          ..strokePath();
        canvas
          ..setStrokeColor(const PdfColor.fromInt(0xFF00796B))
          ..setLineWidth(1.0);
        double x = 0;
        double y = midY - (reduced[0] * midY);
        canvas.moveTo(x, y);
        for (int i = 1; i < reduced.length; i++) {
          x = i * stepX;
          y = midY - (reduced[i] * midY);
          canvas.lineTo(x, y);
        }
        canvas.strokePath();
      },
    );
  }

  static pw.Widget _waveformEmptyHint() => pw.Center(
        child: pw.Text("Waveform unavailable",
            style: const pw.TextStyle(color: PdfColors.grey)),
      );

  static Future<List<double>?> _loadWaveformSamples(String? path) async {
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length < 44) return null;
    final pcm = bytes.sublist(44);
    final byteData = ByteData.sublistView(pcm);
    final samples = <double>[];
    for (int i = 0; i < pcm.length; i += 2) {
      samples.add(byteData.getInt16(i, Endian.little) / 32768.0);
    }
    return samples;
  }

  static Future<pw.ImageProvider?> _generateMelSpectrogramImage(String? wavPath) async {
    if (wavPath == null) return null;
    try {
      final melBytes = await TfliteService().generateMelImageBytes(
        wavPath,
        forPdf: true,
      );
      if (melBytes == null) return null;
      return pw.MemoryImage(melBytes);
    } catch (e) {
      debugPrint("❌ Spectrogram load error: $e");
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // HELPERS
  // --------------------------------------------------------------------------
  static pw.Widget _buildSectionHeader(String title) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF34495E))),
          pw.Divider(height: 8, color: PdfColors.black, thickness: 0.4),
        ],
      );

  static pw.Widget _buildDetailRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 120,
              child: pw.Text(label,
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
            ),
            pw.Expanded(child: pw.Text(value)),
          ],
        ),
      );
}
