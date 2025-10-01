// lib/pages/dashboard.dart
import 'package:cardioscope_app/database_helper.dart';
import 'package:cardioscope_app/pages/reports_detail.dart';
import 'package:cardioscope_app/utils/ui_helpers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with AutomaticKeepAliveClientMixin {
  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> allReports = [];

  // State variables
  String greeting = "Good day";
  String userName = "Health Practitioner";
  int totalPatients = 0;
  int totalThisWeek = 0;

  // Insights panel
  int todayCount = 0;
  int todayMRCount = 0;
  int todayMSCount = 0;
  int todayMVPCount = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadGreetingAndName();
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
    if (!mounted) return;

    final results = await Future.wait([
      db.getAllReports(),
      // TODO: implement these helper queries in db if needed
      Future.value(0), // today screenings placeholder
      Future.value(0), // today MR
      Future.value(0), // today MS
      Future.value(0), // today MVP
    ]);

    final data = results[0] as List<Map<String, dynamic>>;

    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final tot = data.length;
    final thisWeek = data.where((r) {
      try {
        final dateStr = r['record_date'] ?? r['analysis_date'];
        if (dateStr is String) {
          return DateTime.parse(dateStr).isAfter(weekAgo);
        }
        return false;
      } catch (_) {
        return false;
      }
    }).length;

    setState(() {
      allReports = data;
      totalPatients = tot;
      totalThisWeek = thisWeek;
      todayCount = results[1] as int;
      todayMRCount = results[2] as int;
      todayMSCount = results[3] as int;
      todayMVPCount = results[4] as int;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final recentPatients = allReports.take(3).toList();

    return VisibilityDetector(
      key: const Key('dashboard_detector'),
      onVisibilityChanged: (visibilityInfo) {
        if (visibilityInfo.visibleFraction > 0.5) {
          _loadData();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFFC31C42),
          title: const Text('Dashboard', style: TextStyle(color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () => Navigator.pushNamed(context, '/settings'),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadData,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGreetingCard(),
                const SizedBox(height: 20),
                Row(children: [
                  _statCard('Total Patients', totalPatients,
                      Icons.people_alt_rounded, Colors.blue),
                  const SizedBox(width: 12),
                  _statCard('This Week', totalThisWeek,
                      Icons.calendar_today_rounded, Colors.green),
                ]),
                const SizedBox(height: 24),
                _buildRecentPatientsHeader(),
                const SizedBox(height: 8),
                if (recentPatients.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('No recent patient screenings.',
                          style: TextStyle(color: Colors.black54)),
                    ),
                  )
                else
                  ...recentPatients.map((p) => _buildPatientTile(p)),
                const SizedBox(height: 24),
                Text('Today\'s Insights',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _insightCard('Screenings', '$todayCount', Colors.blue),
                    const SizedBox(width: 8),
                    _insightCard('MR Detected', '$todayMRCount', Colors.orange),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _insightCard('MS Detected', '$todayMSCount', Colors.purple),
                    const SizedBox(width: 8),
                    _insightCard('MVP Detected', '$todayMVPCount', Colors.green),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildGreetingCard() {
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
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
                      style: const TextStyle(color: Colors.black87)),
                  TextSpan(
                      text: userName,
                      style: const TextStyle(
                          color: Color(0xFFC31C42),
                          fontWeight: FontWeight.bold)),
                  const TextSpan(
                      text: '!', style: TextStyle(color: Colors.black87)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('MMMM d, yyyy – HH:mm').format(DateTime.now()),
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            const Text(
              'AI-powered assistant for heart sound analysis. Quick screening and easy patient report management.',
              style:
                  TextStyle(fontSize: 14, color: Colors.black54, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        color: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
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
          ]),
        ),
      ),
    );
  }

  Widget _buildRecentPatientsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Recent Patients',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (allReports.length > 3)
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/reports'),
            child: const Text('View All',
                style: TextStyle(
                    color: Color(0xFFC31C42), fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  Widget _buildPatientTile(Map<String, dynamic> p) {
    String dateTimeString = '';
    try {
      final raw = p['analysis_date'] ?? p['record_date'];
      if (raw is String) {
        final dt = DateTime.parse(raw);
        dateTimeString = DateFormat('yyyy-MM-dd HH:mm').format(dt);
      }
    } catch (_) {}

    final id = p['user_id'];
    final formattedId =
        id != null ? DatabaseHelper.instance.formatPatientId(id as int) : 'N/A';

    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: UIHelpers.getStatusIndicator(p['diagnosis'], size: 12.0),
        title: Text(
          '$formattedId – ${p['name'] ?? 'Unnamed'}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${p['diagnosis'] ?? 'Pending'} • $dateTimeString'),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReportDetailPage(report: p)),
        ).then((_) => _loadData()),
      ),
    );
  }

  Widget _insightCard(String title, String value, Color color) {
    return Expanded(
      child: Card(
        color: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
      ),
    );
  }
}
