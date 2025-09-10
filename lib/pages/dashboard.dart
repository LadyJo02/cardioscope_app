import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/chart_widget.dart';
import '../widgets/custom_button.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isMenuOpen = false;

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
    RenderBox renderBox = context.findRenderObject() as RenderBox;
    var size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        top: kToolbarHeight + 8,
        right: 16,
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: Offset(size.width - 150, 0),
          child: Material(
            color: Colors.transparent,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading:
                        const Icon(Icons.folder, color: Color(0xFFC31C42)),
                    title: const Text("Reports"),
                    onTap: () {
                      _toggleMenu();
                      Navigator.pushNamed(context, '/reports');
                    },
                  ),
                  const Divider(height: 0),
                  ListTile(
                    leading:
                        const Icon(Icons.settings, color: Color(0xFFC31C42)),
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
            // Greeting
            Text(
              "Hello, Joanna 👋",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF333333),
                  ),
            ),
            Text(
              today,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF666666),
                  ),
            ),
            const SizedBox(height: 20),

            // Start Recording Button
            CustomButton(
              label: "Start New Recording",
              icon: Icons.mic,
              onPressed: () {
                Navigator.pushNamed(context, '/record');
              },
            ),
            const SizedBox(height: 24),

            // Recent Results
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
                    title:
                        Text("${result["patient"]} - ${result["status"]}"),
                    subtitle: Text(result["date"] as String),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Patient Records Shortcut
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

            // Insights Chart
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
