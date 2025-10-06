import 'dart:io';

import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:cardioscope_app/utils/ui_helpers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';
import '../utils/excel_exporter.dart';
import '../utils/pdf_exporter.dart';
import 'reports_detail.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => ReportsPageState();
}

class ReportsPageState extends State<ReportsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _reports = [];
  String _practitionerName = "";
  int? _practitionerId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    _practitionerId = prefs.getInt('practitioner_id');
    _practitionerName = prefs.getString('practitioner_name') ?? "Practitioner";

    if (_practitionerId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final data = await db.getAllReports(_practitionerId!);
    if (mounted) {
      setState(() {
        _reports = data;
        _isLoading = false;
      });
    }
  }

  // ✅ ADDED: New function to handle the actual sharing of filtered files.
  Future<void> _exportWavFiles(
      List<Map<String, dynamic>> filteredReports, DateTimeRange dateRange) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final List<XFile> filesToShare = [];
      for (final report in filteredReports) {
        final filePath = report['file_path'] as String?;
        if (filePath != null) {
          final file = File(filePath);
          if (await file.exists()) {
            filesToShare.add(XFile(filePath));
          } else {
            debugPrint("File not found for sharing: $filePath");
          }
        }
      }

      if (mounted) Navigator.of(context).pop();

      if (filesToShare.isNotEmpty) {
        await Share.shareXFiles(filesToShare,
            text:
                'CardioScope WAV files from ${DateFormat('yyyy-MM-dd').format(dateRange.start)} to ${DateFormat('yyyy-MM-dd').format(dateRange.end)}');
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
              content: Text("No WAV files found in this date range.")),
        );
      }
    } catch (e) {
      debugPrint("Error exporting WAV files: $e");
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _handleExport(
      Future<void> Function(List<Map<String, dynamic>>, DateTimeRange)
          exportFunction) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currentContext = context;

    final picked = await showDateRangePicker(
      context: currentContext,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now(),
      ),
    );

    if (!mounted || picked == null || _practitionerId == null) return;

    final filteredReports = await db.getAllReports(
      _practitionerId!,
      startDate: picked.start,
      endDate: picked.end,
    );

    if (!mounted) return;

    if (filteredReports.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text("No reports found in this date range.")),
      );
      return;
    }

    await exportFunction(filteredReports, picked);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Results', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // ✅ CHANGED: The share button is now a permanent export feature
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: "Export WAV Files",
            onPressed: () => _handleExport(
              (filteredList, dateRange) =>
                  _exportWavFiles(filteredList, dateRange),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: "Export to PDF",
            onPressed: () => _handleExport((filteredList, dateRange) =>
                PdfExporter.exportBatchReports(
                  reports: filteredList,
                  practitionerName: _practitionerName,
                  dateRange: dateRange,
                )),
          ),
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: "Export to Excel",
            onPressed: () => _handleExport((filteredList, dateRange) =>
                ExcelExporter.exportReportsToExcel(
                  reports: filteredList,
                  practitionerName: _practitionerName,
                  dateRange: dateRange,
                )),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _reports.isEmpty
                ? const Center(child: Text('No reports found.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _reports.length,
                    itemBuilder: (_, i) {
                      final r = _reports[i];
                      final patientId = r['patient_id'] as int?;
                      final patientIdFormatted = patientId != null
                          ? db.formatPatientId(patientId)
                          : 'N/A';

                      String dateString = '';
                      try {
                        final raw = r['analysis_date'] ?? r['record_date'];
                        if (raw is String) {
                          final dt = DateTime.parse(raw);
                          dateString =
                              DateFormat('yyyy-MM-dd HH:mm').format(dt);
                        }
                      } catch (_) {}

                      return Card(
                        color: Colors.white,
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: UIHelpers.getStatusIndicator(r['diagnosis'],
                              size: 12.0),
                          tileColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          title: Text(
                            '${r['name'] ?? 'Unnamed'}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'ID: $patientIdFormatted • ${r['diagnosis'] ?? 'Pending'} • $dateString',
                          ),
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      ReportDetailPage(report: r)),
                            );
                            if (result == true) {
                              load();
                            }
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}