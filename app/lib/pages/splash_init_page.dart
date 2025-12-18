// 📁 lib/pages/splash_init_page.dart
import 'dart:async';

import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';
import '../main.dart';
import '../services/storage_service.dart';
import '../services/tflite_service.dart';
import 'login.dart';
import 'onboarding_page.dart';

/// ✅ Heartbeat line painter with soft fade glow
class HeartbeatPainter extends CustomPainter {
  final double progress;
  final double opacity; // 👈 fade glow param

  HeartbeatPainter(this.progress, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: opacity)   // 👈 animated glow fade
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final midY = size.height * 0.5;
    final width = size.width;

    path.moveTo(0, midY);
    path.lineTo(width * 0.2, midY);
    path.lineTo(width * 0.30, midY - 18);
    path.lineTo(width * 0.36, midY + 20);
    path.lineTo(width * 0.42, midY - 12);
    path.lineTo(width * 0.50, midY);
    path.lineTo(width, midY);

    final metric = path.computeMetrics().first;
    final drawLen = metric.length * progress;
    final partial = metric.extractPath(0, drawLen);

    canvas.drawPath(partial, paint);
  }

  @override
  bool shouldRepaint(covariant HeartbeatPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.opacity != opacity;
}

class SplashInitPage extends StatefulWidget {
  const SplashInitPage({super.key});
  @override
  State<SplashInitPage> createState() => _SplashInitPageState();
}

class _SplashInitPageState extends State<SplashInitPage>
    with TickerProviderStateMixin {

  late AnimationController _pulse;     // logo pulse
  late AnimationController _heartbeat; // ECG progress
  late AnimationController _fadeOut;   // entire screen fade
  late Animation<double> _glow;        // ECG glow fade

  @override
  void initState() {
    super.initState();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.94,
      upperBound: 1.06,
    )..repeat(reverse: true);

    _heartbeat = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // ✅ Glow fade animation (soft breathing)
    _glow = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _heartbeat,
        curve: Curves.easeInOut,
      ),
    );

    _fadeOut = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _initialize();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _heartbeat.dispose();
    _fadeOut.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await Future.delayed(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool('hasSeenOnboarding') ?? false;
    final pid = prefs.getInt("practitioner_id");
    final name = prefs.getString("practitioner_name") ?? "";
    final email = prefs.getString("practitioner_email") ?? "";

    await Permission.microphone.request();
    if (await Permission.storage.isDenied) await Permission.storage.request();
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }

    Future.microtask(() async {
      try { await TfliteService().loadModels(loadClassifier: true); } catch (_) {}
    });

    try { await DatabaseHelper.instance.verifyDatabaseStructure(); } catch (_) {}

    if (pid != null) {
      Future.microtask(() async {
        try {
          final storage = StorageService();
          await storage.ensureBaseFolderFor(
            practitionerId: pid,
            practitionerName: name,
            practitionerEmail: email,
          );

          final db = await DatabaseHelper.instance.database;
          final cnt = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) as count FROM heart_sound_records')) ?? 0;

          if (cnt == 0) {
            await storage.rebuildDatabaseFromExistingFiles(
              practitionerEmail: email,
              practitionerId: pid,
            );
          }
        } catch (_) {}
      });
    }

    await Future.delayed(const Duration(milliseconds: 700));
    await _fadeOut.forward();

    if (!mounted) return;

    if (!hasSeen) {
      _goTo(const OnboardingPage());
    } else if (pid != null) {
      _goTo(const MainNavigation());
    } else {
      _goTo(const LoginPage());
    }
  }

  void _goTo(Widget page) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fadeScreen = Tween(begin: 1.0, end: 0.0).animate(_fadeOut);

    return Scaffold(
      backgroundColor: Colors.white,
      body: FadeTransition(
        opacity: fadeScreen,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pulse, _heartbeat]),
                  builder: (_, __) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [

                        /// ✅ Bigger breathing logo
                        ScaleTransition(
                          scale: _pulse,
                          child: Image.asset(
                            'assets/images/app_logo.png',
                            height: 175,
                          ),
                        ),

                        const SizedBox(height: 20),

                        const Text(
                          "CardioScope",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          "Powered by AI + Deep Learning",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                        const SizedBox(height: 32),

                        /// ✅ ECG with soft fade glow pulse
                        SizedBox(
                          height: 42,
                          width: 150,
                          child: AnimatedBuilder(
                            animation: _glow,
                            builder: (_, __) {
                              return CustomPaint(
                                painter: HeartbeatPainter(
                                  _heartbeat.value,
                                  _glow.value,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                "© 2025 CardioScope. All rights reserved.",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
