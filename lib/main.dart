// lib/main.dart
import 'package:cardioscope_app/pages/profile_setup.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/dashboard.dart';
import 'pages/record.dart';
import 'pages/reports.dart';
import 'pages/settings.dart';
import 'services/tflite_service.dart'; 

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Load preferences
  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;
  final String? userName = prefs.getString('userName');

  // ✅ Request storage permission
  final asked = prefs.getBool('storagePermissionAsked') ?? false;
  if (!asked) {
    if (await Permission.storage.request().isGranted) {
      await prefs.setBool('storagePermissionAsked', true);
    }
  }

  // ✅ Pre-load the AI model for faster first-time use
  //    (The test batch has been removed).
  final tflite = TfliteService();
  await tflite.loadModel();

  // ✅ Then launch the app normally
  runApp(CardioScopeApp(userName: userName));
}

class CardioScopeApp extends StatelessWidget {
  final String? userName;
  const CardioScopeApp({super.key, this.userName});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          title: 'CardioScope',
          debugShowCheckedModeBanner: false,
          
          themeMode: mode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF5F5F5),
            primaryColor: const Color(0xFFC31C42),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFC31C42),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFFC31C42),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFC31C42),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          
          // **CORRECT INITIAL ROUTE LOGIC**
          home: userName == null || userName!.isEmpty
              ? const ProfileSetupPage()
              : const MainNavigation(),

          routes: {
            '/record': (context) => const RecordPage(),
            '/reports': (context) => const ReportsPage(),
            '/settings': (context) => SettingsPage(themeNotifier: themeNotifier),
          },
        );
      },
    );
  }
}

// MainNavigation class remains the same
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  // **ADD A PAGE CONTROLLER FOR SMOOTH NAVIGATION**
  final PageController _pageController = PageController();

  final List<Widget> _pages = const [
    DashboardPage(),
    ReportsPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      // Animate to the page
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // **USE PAGEVIEW TO KEEP PAGE STATE**
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: _pages,
      ),
      floatingActionButton: Hero(
        tag: 'record_button_hero',
        child: FloatingActionButton.large(
          onPressed: () {
            Navigator.pushNamed(context, '/record');
          },
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          elevation: 8.0,
          shape: const CircleBorder(),
          child: const Icon(Icons.mic, size: 40),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 10.0,
        height: 70,
        elevation: 10,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _buildNavItem(Icons.dashboard_rounded, 'Dashboard', 0),
            const SizedBox(width: 80), // space for the FAB notch
            _buildNavItem(Icons.analytics_rounded, 'Results', 1),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;
    final color = isSelected ? Theme.of(context).primaryColor : Colors.grey;

    return InkWell(
      onTap: () => _onItemTapped(index),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
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