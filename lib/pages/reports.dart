// lib/pages/reports.dart
import 'package:flutter/material.dart';

import '../database_helper.dart';
import 'reports_detail.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> reports = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    final data = await db.getAllReports();
    if (mounted) setState(() => reports = data);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFC31C42),
        title: const Text('Results', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          itemBuilder: (_, i) {
            final r = reports[i];
            return Card(
              color: Colors.white,
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                title: Text(r['patientName'] ?? 'Unnamed'),
                subtitle: Text('Last analysis: ${r['recordedDate'] ?? ''} • ${r['classification'] ?? 'Pending'}'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportDetailPage(report: r))),
              ),
            );
          },
        ),
      ),
    );
  }
}
