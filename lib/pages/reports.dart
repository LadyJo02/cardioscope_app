// lib/pages/reports.dart
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
  String? _selectedPatient = 'All';
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    debugPrint("🔄 Loading reports data...");

    try {
      final prefs = await SharedPreferences.getInstance();
      _practitionerId = prefs.getInt('practitioner_id');
      _practitionerName =
          prefs.getString('practitioner_name') ?? "Practitioner";

      if (_practitionerId == null) {
        if (mounted) setState(() => _isLoading = false);
        debugPrint("⚠️ No practitioner ID found. Aborting load.");
        return;
      }

      debugPrint("🔍 Fetching reports for practitioner ID: $_practitionerId");
      final dbData = await db.getAllReportsWithPatients(_practitionerId!);
      debugPrint("✅ Fetched ${dbData.length} reports.");

      debugPrint("🔍 Fetching all patients...");
      final patients = await db.getAllPatients(_practitionerId!);
      debugPrint("✅ Fetched ${patients.length} patients.");

      final data = List<Map<String, dynamic>>.from(dbData);

      // Sort newest first
      data.sort((a, b) {
        final da = DateTime.tryParse(a['record_date'] ?? '') ?? DateTime(2000);
        final dbb = DateTime.tryParse(b['record_date'] ?? '') ?? DateTime(2000);
        return dbb.compareTo(da);
      });

      if (mounted) {
        setState(() {
          _reports = data;
          _patients = patients;
          _filteredReports = data;
          _isLoading = false;
        });
        debugPrint("🟢 UI updated successfully.");
      }
    } catch (e) {
      debugPrint("🔴 ERROR loading reports: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error loading reports: $e")));
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredReports = _reports.where((r) {
        final name = (r['name'] ?? '').toString().toLowerCase();

        final matchesSearch =
            _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase());

        final selectedPatientName = _patients
            .firstWhere((p) => p['name'] == _selectedPatient,
                orElse: () => {})
            .putIfAbsent('name', () => null);

        final matchesPatient = _selectedPatient == null ||
            _selectedPatient == 'All' ||
            r['name'] == selectedPatientName;

        return matchesSearch && matchesPatient;
      }).toList();
    });
  }

  Future<void> _handleExport(
    Future<void> Function(List<Map<String, dynamic>>, DateTimeRange)
        exportFunction,
  ) async {
    if (!mounted) return;
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
    if (!context.mounted || picked == null || _practitionerId == null) return;

    final filtered = await db.getAllReports(
      _practitionerId!,
      startDate: picked.start,
      endDate: picked.end,
    );

    if (!context.mounted) return;

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
    if (!mounted) return;
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

  Future<void> _showEditDialogForList(Map<String, dynamic> report) async {
    final nameCtrl = TextEditingController(text: report['name'] ?? '');
    final genderCtrl = TextEditingController(text: report['gender'] ?? '');
    final birthdayCtrl = TextEditingController(text: report['birthday'] ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Patient Info"),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name")),
            const SizedBox(height: 8),
            TextField(controller: genderCtrl, decoration: const InputDecoration(labelText: "Gender")),
            const SizedBox(height: 8),
            TextField(
              controller: birthdayCtrl,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: "Birthday",
                suffixIcon: Icon(Icons.calendar_today),
              ),
              onTap: () async {
                DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(birthdayCtrl.text) ?? DateTime(2000),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  birthdayCtrl.text = DateFormat('yyyy-MM-dd').format(picked);
                }
              },
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            child: const Text("Save"),
            onPressed: () async {
              final patientId = report['patient_id'] as int?;
              if (patientId != null) {
                await db.database.then((conn) {
                  conn.update(
                    'patients',
                    {
                      'name': nameCtrl.text.trim(),
                      'gender': genderCtrl.text.trim(),
                      'birthday': birthdayCtrl.text.trim(),
                    },
                    where: 'patient_id = ?',
                    whereArgs: [patientId],
                  );
                });
                if (!context.mounted) return; 

                setState(() {
                  report['name'] = nameCtrl.text.trim();
                  report['gender'] = genderCtrl.text.trim();
                  report['birthday'] = birthdayCtrl.text.trim();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("✅ Patient info updated.")),
                );
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
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
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12))),
                            ),
                            onChanged: (val) {
                              _searchQuery = val;
                              _applyFilters();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: _selectedPatient,
                          items: [
                            const DropdownMenuItem(
                                value: 'All', child: Text('All Patients')),
                            ..._patients.map((p) => DropdownMenuItem<String>(
                                  value: p['name'],
                                  child: Text(p['name']),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedPatient = val;
                            });
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
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                                if (raw is String && raw.isNotEmpty) {
                                  date = DateFormat('yyyy-MM-dd HH:mm')
                                      .format(DateTime.parse(raw));
                                }
                              } catch (_) {}

                              return Dismissible(
                                key: Key(r['record_id'].toString()),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  color: AppColors.warning,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                confirmDismiss: (_) async {
                                  return await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text("Confirm Delete"),
                                    content: const Text("Are you sure you want to delete this report?"),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: const Text("Cancel"),
                                      ),
                                      // ⬇️ Replace your old button with this fixed version:
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            ),
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                          textStyle: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text("Delete"),
                                      ),
                                    ],
                                  ),
                                  ) ?? false;
                                },

                                onDismissed: (_) async {
                                  await db.deleteRecordById(r['record_id']);
                                  if (!context.mounted) return; 
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text("Report deleted.")),
                                  );
                                  setState(() => _filteredReports.removeAt(i));
                                },
                                child: Card(
                                  color: Colors.white,
                                  elevation: 2,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 6.0),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  child: ListTile(
                                    leading: UIHelpers.getStatusIndicator(
                                        r['diagnosis'], size: 12.0),
                                    title: Text(
                                      r['name'] ?? 'Unnamed',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(
                                        'ID: $pid • ${r['diagnosis'] ?? 'Pending'} • $date'),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) async {
                                        if (value == 'edit') {
                                          await _showEditDialogForList(r);
                                        } else if (value == 'delete') {
                                          await db.deleteRecordById(r['record_id']);
                                          if (!context.mounted) return; 
                                          setState(() =>
                                              _filteredReports.removeAt(i));
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  content:
                                                      Text("🗑 Report deleted.")));
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(children: [
                                            Icon(Icons.edit,
                                                color: AppColors.deep),
                                            SizedBox(width: 8),
                                            Text('Edit'),
                                          ]),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(children: [
                                            Icon(Icons.delete,
                                                color: AppColors.warning),
                                            SizedBox(width: 8),
                                            Text('Delete'),
                                          ]),
                                        ),
                                      ],
                                    ),
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
