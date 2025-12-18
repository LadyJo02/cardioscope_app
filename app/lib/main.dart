// lib/main.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/dashboard.dart';
import 'pages/record.dart';
import 'pages/reports.dart';
import 'pages/settings.dart';
import 'pages/splash_init_page.dart';
import 'services/storage_service.dart';
import 'utils/app_colors.dart';
import 'utils/app_theme.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;

  runApp(const CardioScopeApp());
}

class CardioScopeApp extends StatelessWidget {
  const CardioScopeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          title: 'CardioScope',
          theme: AppTheme.lightTheme.copyWith(
            bottomAppBarTheme: const BottomAppBarThemeData(
              color: Colors.white,
              elevation: 10,
              surfaceTintColor: Colors.transparent,
            ),
          ),
          darkTheme: AppTheme.darkTheme.copyWith(
            bottomAppBarTheme: const BottomAppBarThemeData(
              color: Color(0xFF1E1E1E),
              elevation: 10,
              surfaceTintColor: Colors.transparent,
            ),
          ),
          themeMode: mode,
          debugShowCheckedModeBanner: false,
          navigatorObservers: [routeObserver],
          home: const SplashInitPage(),
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

// ✅ NAVIGATION SHELL + Pulse mic button
class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {

  int _selectedIndex = 0;
  final PageController _pageController = PageController();
  final GlobalKey<ReportsPageState> _reportsPageKey = GlobalKey();

  late final List<Widget> _pages = [
    const DashboardPage(),
    ReportsPage(key: _reportsPageKey),
  ];

  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0.92,
      upperBound: 1.06,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeInOut,
      );
    });
  }

  Future<void> _goToRecord() async {
    final storage = StorageService();
    await storage.getOrCreateBaseFolder();

    if (!mounted) return;
    final refresh = await Navigator.pushNamed(context, '/record');

    if (refresh == true) {
      _reportsPageKey.currentState?.load();
      _onItemTapped(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _selectedIndex = i),
        children: _pages,
      ),

      floatingActionButton: GestureDetector(
        onTap: _goToRecord,
        child: Hero(
          tag: 'record_button_hero',
          child: ScaleTransition(
            scale: _pulse,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.mic,
                size: 52,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 12,
        height: 78,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.dashboard_rounded, 'Dashboard', 0),
            const SizedBox(width: 80),
            _navItem(Icons.analytics_rounded, 'Results', 1),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int i) {
    final active = _selectedIndex == i;
    return InkWell(
      onTap: () => _onItemTapped(i),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? AppColors.primary : Colors.grey),
            Text(
              label,
              style: TextStyle(
                color: active ? AppColors.primary : Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
