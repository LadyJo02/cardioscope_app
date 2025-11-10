// lib/utils/excel_exporter.dart
import 'dart:convert';
import 'dart:io';

import 'package:cardioscope_app/services/storage_service.dart';
import 'package:cardioscope_app/utils/latency_debug.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../database_helper.dart';
import '../pages/excel_viewer_page.dart';

class ExcelExporter {
  static Future<void> exportReportsToExcel({
    required BuildContext context,
    required List<Map<String, dynamic>> reports,
    required String practitionerName,
    required DateTimeRange dateRange,
  }) async {
    LatencyDebug.start("📊 Excel", "Generating Excel export (${reports.length} records)");
    if (reports.isEmpty) return;

    final excel = Excel.createExcel();
    final Sheet sheet = excel['Cardioscope Records'];

    final headerRow = [
      "Practitioner", "Practitioner Email", "Clinic/Facility", "Patient ID", "Patient Name", "Age", "Gender", "Symptoms",
      "Record Date", "Diagnosis", "Confidence (%)", "MR Prob (%)",
      "MS Prob (%)", "MVP Prob (%)", "N Prob (%)"
    ];
    sheet.appendRow(headerRow);

    for (final report in reports) {
      final probs = (report['probabilities'] is String && (report['probabilities'] as String).isNotEmpty)
          ? jsonDecode(report['probabilities']) as Map<String, dynamic>
          : <String, dynamic>{};

      final diagnosis = report['diagnosis'] ?? "N/A";
      final confidence = (probs[diagnosis] as num?)?.toDouble() ?? 0.0;
      
      final patientId = report['patient_id'];
      final patientIdFormatted = patientId != null
          ? DatabaseHelper.instance.formatPatientId(patientId)
          : 'N/A';

      String recordDateStr = 'N/A';
      if (report['record_date'] != null) {
        try {
          recordDateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.parse(report['record_date']));
        } catch (_) {}
      }

      excel.setDefaultSheet('Cardioscope Records');
      sheet.appendRow([
        practitionerName,                              // Practitioner
        report['practitioner_email'] ?? 'N/A',         // Practitioner Email 
        report['clinic_name'] ?? 'N/A',                // Clinic/Facility 
        patientIdFormatted,                            // Patient ID
        report['name'] ?? 'N/A',                       // Patient Name
        report['age'] ?? '',                           // Age
        report['gender'] ?? 'N/A',                     // Gender
        report['symptoms'] ?? 'N/A',                   // Symptoms
        recordDateStr,                                 // Record Date
        diagnosis,                                     // Diagnosis
        (confidence * 100),                            // Confidence
        ((probs['MR'] as num?)?.toDouble() ?? 0) * 100,
        ((probs['MS'] as num?)?.toDouble() ?? 0) * 100,
        ((probs['MVP'] as num?)?.toDouble() ?? 0) * 100,
        ((probs['N'] as num?)?.toDouble() ?? 0) * 100,
      ]);
    }
    LatencyDebug.mark("📊 Excel", "All rows added");

    final storage = StorageService();
    final basePath = await storage.getOrCreateBaseFolder();
    final excelDir = await storage.getBatchExcelDir(basePath);

    final startDate = DateFormat('yyyy-MM-dd').format(dateRange.start);
    final endDate = DateFormat('yyyy-MM-dd').format(dateRange.end);
    final filename = "CardioScope_Export_${practitionerName.replaceAll(' ', '_')}_${startDate}_to_$endDate.xlsx";
    
    final file = File("$excelDir/$filename");

    final fileBytes = excel.save();
    if (fileBytes != null) {
      await file.writeAsBytes(List<int>.from(fileBytes));
      LatencyDebug.end("📊 Excel", "Excel file saved: ${file.path}");


    if (context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExcelViewerPage(
          filePath: file.path,
          title: 'Excel Export',
        ),
      ),
    );
  }

      await Share.shareXFiles([XFile(file.path)], text: "CardioScope Excel Export");
    }
  }
}
