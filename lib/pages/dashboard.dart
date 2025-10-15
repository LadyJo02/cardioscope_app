import 'package:cardioscope_app/database_helper.dart';
import 'package:cardioscope_app/pages/reports_detail.dart';
import 'package:cardioscope_app/utils/app_colors.dart';
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

  String greeting = "Good day";
  String practitionerName = "Health Practitioner";
  int totalPatients = 0;
  int totalThisWeek = 0;

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
    practitionerName =
        prefs.getString('practitioner_name') ?? "Health Practitioner";

    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final practitionerId = prefs.getInt('practitioner_id');
    if (practitionerId == null) return;

    final data = await db.getAllReports(practitionerId);

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

    todayCount = data.where((r) {
      final raw = r['analysis_date'] ?? r['record_date'];
      if (raw is String) {
        final dt = DateTime.tryParse(raw);
        return dt != null &&
            dt.year == now.year &&
            dt.month == now.month &&
            dt.day == now.day;
      }
      return false;
    }).length;

    todayMRCount = data.where((r) => r['diagnosis'] == 'MR').length;
    todayMSCount = data.where((r) => r['diagnosis'] == 'MS').length;
    todayMVPCount = data.where((r) => r['diagnosis'] == 'MVP').length;

    setState(() {
      allReports = data;
      totalPatients = tot;
      totalThisWeek = thisWeek;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final recentPatients = allReports.take(3).toList();

    return VisibilityDetector(
      key: const Key('dashboard_detector'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.5) _loadData();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          title: const Text('Dashboard'),
          actions: [
            IconButton(
              icon: Icon(Icons.settings,
                  color: Theme.of(context).colorScheme.onPrimary),
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
                  _placeholderCard(
                      Icons.inbox_rounded, 'No recent patient screenings.')
                else
                  ...recentPatients.map((p) => _buildPatientTile(p)),
                const SizedBox(height: 24),
                Text(
                  "Today's Insights",
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
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

  Widget _placeholderCard(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Card(
        color: Theme.of(context).cardColor,
        elevation: 8,
        shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: AppColors.muted.withValues(alpha: 0.8), size: 40),
              const SizedBox(height: 10),
              Text(
                text,
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreetingCard() {
    return Card(
      color: Theme.of(context).cardColor,
      elevation: 8,
      shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.25),
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
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface)),
                  TextSpan(
                      text: practitionerName,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold)),
                  TextSpan(
                      text: '!',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('MMMM d, yyyy – HH:mm').format(DateTime.now()),
              style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'AI-powered assistant for heart sound analysis. Quick screening and easy patient report management.',
              style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                  height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        color: Theme.of(context).cardColor,
        elevation: 8,
        shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text('$value',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
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
            onTap: () =>
                Navigator.pushNamed(context, '/reports').then((_) => _loadData()),
            child: const Text('View All',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
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

    final id = p['patient_id'];
    final formattedId =
        id != null ? DatabaseHelper.instance.formatPatientId(id as int) : 'N/A';

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 8,
      shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: UIHelpers.getStatusIndicator(p['diagnosis'], size: 12.0),
        horizontalTitleGap: 12.0,
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
        color: Theme.of(context).cardColor,
        elevation: 8,
        shadowColor: Theme.of(context).shadowColor.withValues(alpha: 0.25),
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
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface)),
          ]),
        ),
      ),
    );
  }
}
