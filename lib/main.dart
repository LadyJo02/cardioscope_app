import 'package:cardioscope_app/pages/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pages/dashboard.dart';
import 'pages/login.dart';
import 'pages/record.dart';
import 'pages/reports.dart';
import 'pages/settings.dart';
import 'services/storage_service.dart';
import 'services/tflite_service.dart';
import 'utils/app_colors.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;
  final int? practitionerId = prefs.getInt("practitioner_id");

  final isDarkMode = prefs.getBool('isDarkMode') ?? false;
  themeNotifier.value = isDarkMode ? ThemeMode.dark : ThemeMode.light;

  final asked = prefs.getBool('storagePermissionAsked') ?? false;
  if (!asked) {
    if (await Permission.storage.request().isGranted) {
      await prefs.setBool('storagePermissionAsked', true);
    }
  }

  final tflite = TfliteService();
  await tflite.loadModel();

  runApp(CardioScopeApp(
    hasSeenOnboarding: hasSeenOnboarding,
    isLoggedIn: practitionerId != null,
  ));
}

class CardioScopeApp extends StatelessWidget {
  final bool hasSeenOnboarding;
  final bool isLoggedIn;

  const CardioScopeApp({
    super.key,
    required this.hasSeenOnboarding,
    required this.isLoggedIn,
  });

  Widget _getInitialPage() {
    if (!hasSeenOnboarding) {
      return const OnboardingPage();
    } else {
      return isLoggedIn ? const MainNavigation() : const LoginPage();
    }
  }

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
            scaffoldBackgroundColor: AppColors.scaffoldBackground,
            primaryColor: AppColors.primary,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: Brightness.light,
              secondary: AppColors.accent,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: AppColors.primary,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: Brightness.dark,
              secondary: AppColors.accent,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            useMaterial3: true,
          ),
          home: _getInitialPage(),
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

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();
  final GlobalKey<ReportsPageState> _reportsPageKey = GlobalKey();
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const DashboardPage(),
      ReportsPage(key: _reportsPageKey),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
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

  /// 🧩 MIC BUTTON LOGIC — Includes cancel reminder dialog
  Future<void> _handleMicPressed() async {
    final storageService = StorageService();
    final savedPath = await storageService.getSavedPath();

    debugPrint('🔍 Checking saved folder path...');
    debugPrint('Saved path: $savedPath');

    // 🆕 Case 1 — First time user (no folder saved)
    if (savedPath == null || savedPath.isEmpty) {
      debugPrint('🆕 No folder path found. Showing folder selection dialog.');

      if (!mounted) return;

      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Select Save Folder'),
          content: const Text(
            'For better access, please select or create a folder inside Downloads (e.g., CardioScope).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Select Folder'),
            ),
          ],
        ),
      );

      // ❌ If user pressed "Cancel" — show reminder dialog
      if (proceed != true) {
        debugPrint('❌ User canceled folder selection dialog.');

        if (!mounted) return;
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Folder Required'),
            content: const Text(
              'You need to select a folder to save recordings.\nPlease tap the mic button again to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      final pickedPath = await storageService.pickFolder();
      debugPrint('📁 Folder picked: $pickedPath');

      if (!mounted) return;

      // ❌ If user cancels the system folder picker
      if (pickedPath == null || pickedPath.isEmpty) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Folder Required'),
            content: const Text(
              'You must select a folder to save recordings.\nPlease tap the mic button again to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      // ✅ Folder successfully selected and saved
      debugPrint('✅ Folder path saved: $pickedPath');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Folder selected: $pickedPath'),
          duration: const Duration(seconds: 2),
        ),
      );

      if (!mounted) return;
      _navigateToRecordPage();
    } 
    // 🔁 Case 2 — Returning user
    else {
      debugPrint('✅ Existing folder path detected: $savedPath');
      if (!mounted) return;
      _navigateToRecordPage();
    }
  }

  Future<void> _navigateToRecordPage() async {
    final refreshNeeded = await Navigator.pushNamed(context, '/record');
    if (refreshNeeded == true && mounted) {
      _reportsPageKey.currentState?.load();
      _onItemTapped(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() => _selectedIndex = index);
        },
        children: _pages,
      ),
      floatingActionButton: Hero(
        tag: 'record_button_hero',
        child: FloatingActionButton.large(
          onPressed: _handleMicPressed,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 8.0,
          shape: const CircleBorder(),
          child: const Icon(Icons.mic, size: 40),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Theme.of(context).bottomAppBarTheme.color ?? Colors.white,
        surfaceTintColor:
            Theme.of(context).bottomAppBarTheme.surfaceTintColor ?? Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 10.0,
        height: 70,
        elevation: 10,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _buildNavItem(Icons.dashboard_rounded, 'Dashboard', 0),
            const SizedBox(width: 80), // Space for FAB
            _buildNavItem(Icons.analytics_rounded, 'Results', 1),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;
    final color = isSelected ? AppColors.primary : Colors.grey;

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
