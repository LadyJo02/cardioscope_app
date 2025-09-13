import 'package:cardioscope_app/database_helper.dart';
import 'package:cardioscope_app/pages/reports.dart';      // ✅ page showing all reports
import 'package:cardioscope_app/pages/reports_detail.dart';
import 'package:cardioscope_app/widgets/chart_widget.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> allReports = [];
  List<int> weeklyCounts = List.filled(7, 0);

  String greeting = "Good day";
  String userName = "Health Practitioner";

  int totalPatients = 0;
  int totalThisWeek = 0;

  @override
  void initState() {
    super.initState();
    _loadGreetingAndName();
    _loadData();
  }

  Future<void> _loadGreetingAndName() async {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      greeting = "Good morning";
    } else if (hour < 18) {
      greeting = "Good afternoon";
    } else {
      greeting = "Good evening";
    }

    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('userName');
    if (savedName != null && savedName.trim().isNotEmpty) {
      userName = savedName.trim();
    }

    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    allReports = await db.getAllReports();
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    totalPatients = allReports.length;
    totalThisWeek = allReports
        .where((r) =>
            DateTime.parse(r['recordedDate']).isAfter(weekAgo))
        .length;

    weeklyCounts = await db.fetchScreeningsPerDayLast7();

    if (mounted) setState(() {});
  }

  Widget _statCard(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        color: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text('$value',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recentPatients = allReports.take(3).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFC31C42),
        title: const Text('Dashboard', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Greeting + short description ----
              Card(
                color: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                          children: [
                            TextSpan(
                              text: '$greeting, ',
                              style: const TextStyle(color: Colors.black87),
                            ),
                            TextSpan(
                              text: userName,
                              style: const TextStyle(
                                  color: Color(0xFFC31C42),
                                  fontWeight: FontWeight.bold),
                            ),
                            const TextSpan(
                              text: '!',
                              style: TextStyle(color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'CardioScope quickly analyzes heart sounds to help you detect Mitral Valve Disorders in real-time clinical practice.',
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ---- Key Stats Row ----
              Row(
                children: [
                  _statCard('Total Patients', totalPatients,
                      Icons.people_alt_rounded, Colors.blue),
                  const SizedBox(width: 12),
                  _statCard('This Week', totalThisWeek,
                      Icons.calendar_today_rounded, Colors.green),
                ],
              ),
              const SizedBox(height: 28),

              // ---- Recent Patients ----
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Patients',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          )),
                  if (allReports.length > 3)
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ReportsPage()),
                        );
                      },
                      child: const Text(
                        'View All',
                        style: TextStyle(
                            color: Color(0xFFC31C42),
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (recentPatients.isEmpty)
                const Text('No recent patients.'),
              for (final p in recentPatients)
                Card(
                  color: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    title: Text(p['patientName'] ?? 'Unnamed'),
                    subtitle: Text(
                        'Last analysis: ${p['recordedDate'] ?? ''} • ${p['classification'] ?? ''}'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReportDetailPage(report: p),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 28),

              // ---- Insights Graph ----
              Text('Insights',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
              const SizedBox(height: 4),
              const Text(
                'Screenings performed in the past 7 days',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: ChartWidget(counts: weeklyCounts),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
