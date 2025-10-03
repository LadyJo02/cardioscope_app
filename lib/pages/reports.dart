// lib/pages/reports.dart
import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:cardioscope_app/utils/ui_helpers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';
import '../utils/excel_exporter.dart';
import '../utils/pdf_exporter.dart';
import 'reports_detail.dart';

class ReportsPage extends StatefulWidget {
  // The key is now correctly handled by the super constructor
  const ReportsPage({super.key});

  @override
  // ✅ FIXED: Renamed to use the public state class
  State<ReportsPage> createState() => ReportsPageState();
}

// ✅ FIXED: Renamed _ReportsPageState to ReportsPageState (made it public)
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

  // ✅ FIXED: Renamed _load to load (made it public)
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

  Future<void> _handleExport(Future<void> Function(List<Map<String, dynamic>>, DateTimeRange) exportFunction) async {
    if (!mounted) return;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now(),
      ),
    );

    if (picked == null || _practitionerId == null) return;

    final filteredReports = await db.getAllReports(
      _practitionerId!,
      startDate: picked.start,
      endDate: picked.end,
    );

    if (filteredReports.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No reports found in this date range.")),
        );
      }
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
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: "Export to PDF",
            onPressed: () => _handleExport((filteredList, dateRange) =>
              PdfExporter.exportBatchReports(
                reports: filteredList,
                practitionerName: _practitionerName,
                dateRange: dateRange,
              )
            ),
          ),
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: "Export to Excel",
            onPressed: () => _handleExport((filteredList, dateRange) =>
              ExcelExporter.exportReportsToExcel(
                reports: filteredList,
                practitionerName: _practitionerName,
                dateRange: dateRange,
              )
            ),
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
                      final patientIdFormatted =
                          patientId != null ? db.formatPatientId(patientId) : 'N/A';

                      String dateString = '';
                      try {
                        final raw = r['analysis_date'] ?? r['record_date'];
                        if (raw is String) {
                          final dt = DateTime.parse(raw);
                          dateString = DateFormat('yyyy-MM-dd HH:mm').format(dt);
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
                          leading:
                              UIHelpers.getStatusIndicator(r['diagnosis'], size: 12.0),
                          tileColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          title: Text(
                            '${r['name'] ?? 'Unnamed'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'ID: $patientIdFormatted • ${r['diagnosis'] ?? 'Pending'} • $dateString',
                          ),
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ReportDetailPage(report: r)),
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