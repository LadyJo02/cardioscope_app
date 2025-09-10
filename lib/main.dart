import 'package:flutter/material.dart';

// Import pages
import 'pages/dashboard.dart';
import 'pages/record.dart';
import 'pages/reports.dart';
import 'pages/results.dart';
import 'pages/settings.dart';

void main() {
  runApp(const CardioScopeApp());
}

class CardioScopeApp extends StatelessWidget {
  const CardioScopeApp({super.key});

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
        ),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
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
    RecordPage(),
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
      body: _pages[_selectedIndex],
      // We wrap the BottomNavigationBar with a Container to apply a custom shadow
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white, // Or Theme.of(context).canvasColor
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, -3), // Shadow position (moves it upwards)
            ),
          ],
        ),      
      child: BottomNavigationBar(
        elevation: 0, // Remove default shadow
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFC31C42),
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.mic), label: 'Record'),
          BottomNavigationBarItem(
              icon: Icon(Icons.analytics), label: 'Results'),
          ],
        ),
      ),
    );
  }
}
