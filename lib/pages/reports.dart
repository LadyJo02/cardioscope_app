// lib/pages/reports.dart
import 'package:cardioscope_app/utils/ui_helpers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';
import 'reports_detail.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> reports = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final practitionerId = prefs.getInt('practitioner_id');
    if (practitionerId == null) return;

    final data = await db.getAllReports(practitionerId);
    if (mounted) setState(() => reports = data);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFC31C42),
        title: const Text('Results', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: reports.isEmpty
            ? const Center(child: Text('No reports found.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: reports.length,
                itemBuilder: (_, i) {
                  final r = reports[i];
                  final patientId = r['patient_id'] as int?;
                  final patientIdFormatted = patientId != null
                      ? db.formatPatientId(patientId)
                      : 'N/A';

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
                    child: ListTile(
                      leading: UIHelpers.getStatusIndicator(
                          r['diagnosis'], size: 12.0),
                      title: Text(
                        '${r['name'] ?? 'Unnamed'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'ID: $patientIdFormatted • ${r['diagnosis'] ?? 'Pending'} • $dateString',
                      ),
                      onTap: () async {
                        final updated = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ReportDetailPage(report: r)),
                        );
                        if (updated == true) _load(); // refresh if updated
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
