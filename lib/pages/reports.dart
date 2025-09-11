// lib/pages/reports.dart

import 'package:cardioscope_app/database_helper.dart';
// Corrected the import path
import 'package:cardioscope_app/pages/reports_detail.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late Future<List<Map<String, dynamic>>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = DatabaseHelper.instance.getAllReports();
  }

  void _refreshReports() {
    setState(() {
      _reportsFuture = DatabaseHelper.instance.getAllReports();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Saved Reports", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
        automaticallyImplyLeading: false,
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _refreshReports)],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _reportsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No saved reports found."));
          }

          final reports = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              final date = DateTime.parse(report['recordedDate']);

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.audiotrack_rounded, color: Color(0xFFC31C42)),
                  title: Text(report['patientName'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(DateFormat('MMMM d, yyyy - HH:mm').format(date)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (context) => ReportDetailPage(report: report),
                    )).then((_) => _refreshReports()); // Refresh when returning
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}