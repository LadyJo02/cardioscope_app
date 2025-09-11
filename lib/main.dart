import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Pages
import 'pages/dashboard.dart';
import 'pages/profile_setup.dart';
import 'pages/record.dart';
import 'pages/reports.dart';
import 'pages/results.dart';
import 'pages/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final String? userName = prefs.getString('userName');

  runApp(CardioScopeApp(userName: userName));
}

class CardioScopeApp extends StatelessWidget {
  final String? userName;
  const CardioScopeApp({super.key, this.userName});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CardioScope',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFC31C42),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC31C42),
          primary: const Color(0xFFC31C42),
          surface: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: userName == null
          ? const ProfileSetupPage()
          : const MainNavigation(),
      routes: {
        '/record': (context) => const RecordPage(),
        '/reports': (context) => const ReportsPage(),
        '/settings': (context) => const SettingsPage(),
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    DashboardPage(),
    ResultsPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // ✅ Matches dashboard background
      body: _pages[_selectedIndex],

      floatingActionButton: SizedBox(
        width: 65,
        height: 65,
        child: FloatingActionButton(
          onPressed: () {
            Navigator.pushNamed(context, '/record');
          },
          backgroundColor: const Color(0xFFC31C42),
          foregroundColor: Colors.white,
          elevation: 6.0,
          shape: const CircleBorder(),
          child: const Icon(Icons.mic, size: 30),
        ),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        height: 70,
        elevation: 10,
        color: const Color(0xFFF5F5F5), // ✅ Same as dashboard background
        padding: EdgeInsets.zero,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _buildNavItem(Icons.dashboard, 'Dashboard', 0),
            const SizedBox(width: 40), // space for mic
            _buildNavItem(Icons.analytics, 'Results', 1),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final bool isSelected = _selectedIndex == index;
    final Color color = isSelected ? const Color(0xFFC31C42) : Colors.grey;

    return InkWell(
      onTap: () => _onItemTapped(index),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
