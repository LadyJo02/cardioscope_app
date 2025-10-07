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
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _filteredReports = [];

  String _practitionerName = "";
  int? _practitionerId;
  bool _isLoading = true;
  String? _selectedPatient;
  String _searchQuery = "";

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

    final data = await db.getAllReportsWithPatients(_practitionerId!);
    final patients = await db.getAllPatients(_practitionerId!);

    if (mounted) {
      setState(() {
        _reports = data;
        _patients = patients;
        _filteredReports = _reports;
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredReports = _reports.where((r) {
        final name = (r['name'] ?? '').toString().toLowerCase();
        final matchesSearch =
            _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());
        final matchesPatient = _selectedPatient == null ||
            _selectedPatient == 'All' ||
            name == _selectedPatient;
        return matchesSearch && matchesPatient;
      }).toList();
    });
  }

  Future<void> _handleExport(
    Future<void> Function(List<Map<String, dynamic>>, DateTimeRange)
        exportFunction,
  ) async {
    final scaffold = ScaffoldMessenger.of(context);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now(),
      ),
    );
    if (!mounted || picked == null || _practitionerId == null) return;

    final filtered = await db.getAllReports(
      _practitionerId!,
      startDate: picked.start,
      endDate: picked.end,
    );

    if (filtered.isEmpty) {
      scaffold.showSnackBar(
        const SnackBar(content: Text("No reports in this date range.")),
      );
      return;
    }
    await exportFunction(filtered, picked);
  }

  Future<void> _exportWavFiles(
      List<Map<String, dynamic>> filtered, DateTimeRange range) async {
    final scaffold = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final files = <XFile>[];
      for (final r in filtered) {
        final path = r['file_path'] as String?;
        if (path != null && await File(path).exists()) files.add(XFile(path));
      }
      if (mounted) Navigator.pop(context);
      if (files.isEmpty) {
        scaffold.showSnackBar(
          const SnackBar(content: Text("No WAV files found.")),
        );
        return;
      }
      await Share.shareXFiles(
        files,
        text:
            'CardioScope WAV files ${DateFormat('yyyy-MM-dd').format(range.start)}–${DateFormat('yyyy-MM-dd').format(range.end)}',
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      scaffold.showSnackBar(SnackBar(content: Text("Export error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('Reports', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: "Export WAV Files",
            onPressed: () => _handleExport(_exportWavFiles),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: "Export PDF",
            onPressed: () => _handleExport((list, range) =>
                PdfExporter.exportBatchReports(
                    reports: list,
                    practitionerName: _practitionerName,
                    dateRange: range)),
          ),
          IconButton(
            icon: const Icon(Icons.table_view_outlined),
            tooltip: "Export Excel",
            onPressed: () => _handleExport((list, range) =>
                ExcelExporter.exportReportsToExcel(
                    reports: list,
                    practitionerName: _practitionerName,
                    dateRange: range)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: Column(
                children: [
                  // 🔍 Search and filter row
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search patient name...',
                            ),
                            onChanged: (val) {
                              _searchQuery = val;
                              _applyFilters();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: _selectedPatient ?? 'All',
                          items: [
                            const DropdownMenuItem(
                                value: 'All', child: Text('All Patients')),
                            ..._patients.map((p) => DropdownMenuItem<String>(
                                  value: p['name'],
                                  child: Text(p['name']),
                                )),
                          ],
                          onChanged: (val) {
                            _selectedPatient = val;
                            _applyFilters();
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _filteredReports.isEmpty
                        ? const Center(child: Text('No reports found.'))
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredReports.length,
                            itemBuilder: (_, i) {
                              final r = _filteredReports[i];
                              final patientId = r['patient_id'] as int?;
                              final pid = patientId != null
                                  ? db.formatPatientId(patientId)
                                  : 'N/A';
                              String date = '';
                              try {
                                final raw = r['analysis_date'] ?? r['record_date'];
                                if (raw is String) {
                                  date = DateFormat('yyyy-MM-dd HH:mm')
                                      .format(DateTime.parse(raw));
                                }
                              } catch (_) {}
                              return Card(
                                color: Colors.white,
                                elevation: 2,
                                margin:
                                    const EdgeInsets.symmetric(vertical: 6.0),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: UIHelpers.getStatusIndicator(
                                      r['diagnosis'],
                                      size: 12.0),
                                  title: Text(
                                    r['name'] ?? 'Unnamed',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                      'ID: $pid • ${r['diagnosis'] ?? 'Pending'} • $date'),
                                  onTap: () async {
                                    final res = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              ReportDetailPage(report: r)),
                                    );
                                    if (res == true && mounted) load();
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
