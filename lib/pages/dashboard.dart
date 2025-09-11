import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/chart_widget.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isMenuOpen = false;
  String _userName = 'User';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('userName') ?? 'User';
    });
  }

  void _toggleMenu() {
    if (_isMenuOpen) {
      _overlayEntry?.remove();
      _isMenuOpen = false;
    } else {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
      _isMenuOpen = true;
    }
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) => Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleMenu,
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8.0),
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: 200,
                child: Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.folder,
                            color: Color(0xFFC31C42)),
                        title: const Text("Reports"),
                        onTap: () {
                          _toggleMenu();
                          Navigator.pushNamed(context, '/reports');
                        },
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.settings,
                            color: Color(0xFFC31C42)),
                        title: const Text("Settings"),
                        onTap: () {
                          _toggleMenu();
                          Navigator.pushNamed(context, '/settings');
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('MMMM d, y').format(DateTime.now());

    final recentResults = [
      {
        "patient": "Patient 001",
        "status": "Normal",
        "date": "Sept 10, 2025 - 11:30 AM",
        "color": Colors.green,
      },
      {
        "patient": "Patient 002",
        "status": "MR Detected",
        "date": "Sept 9, 2025 - 03:15 PM",
        "color": Colors.orange,
      },
      {
        "patient": "Patient 003",
        "status": "Normal",
        "date": "Sept 8, 2025 - 09:45 AM",
        "color": Colors.red,
      },
    ];

    return Scaffold(
      // --- FIX: SET THE BACKGROUND TO OFF-WHITE ---
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          "Dashboard",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFFC31C42),
        actions: [
          CompositedTransformTarget(
            link: _layerLink,
            child: IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: _toggleMenu,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Hello, $_userName 👋",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF33333d),
                  ),
            ),
            Text(
              today,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF666666),
                  ),
            ),
            const SizedBox(height: 24),
            Text(
              "Recent Results",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF333333),
                  ),
            ),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recentResults.length,
              itemBuilder: (context, index) {
                final result = recentResults[index];
                return Card(
                  color: Colors.white,
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading:
                        Icon(Icons.favorite, color: result["color"] as Color),
                    title: Text("${result["patient"]} - ${result["status"]}"),
                    subtitle: Text(result["date"] as String),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Patient Records",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/reports');
                  },
                  child: const Text(
                    "View All",
                    style: TextStyle(color: Color(0xFFC31C42)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              "Insights",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF333333),
                  ),
            ),
            const SizedBox(height: 10),
            const SizedBox(
              height: 200,
              child: ChartWidget(),
            ),
          ],
        ),
      ),
    );
  }
}