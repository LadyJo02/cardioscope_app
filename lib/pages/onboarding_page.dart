import 'package:cardioscope_app/pages/login.dart';
import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  bool _isLastPage = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginPage(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // ✅ NEW: Gradient background to match your login page design
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blueGrey.shade50,
              const Color(0xFFE0F7FA), // A light cyan
              Colors.teal.shade50,
            ],
          ),
        ),
        child: Stack(
          children: [
            // Main Content
            PageView(
              controller: _controller,
              onPageChanged: (index) {
                setState(() {
                  _isLastPage = index == 2;
                });
              },
              children: const [
                OnboardingSlide(
                  icon: Icons.favorite_border,
                  title: "Welcome to CardioScope",
                  description:
                      "We listen closely, helping you uncover the story in every heartbeat.",
                ),
                OnboardingSlide(
                  icon: Icons.waves,
                  title: "Record & Analyze",
                  description:
                      "Tap to capture cardiac sounds and receive immediate, on-device AI classification of potential mitral valve conditions.",
                ),
                OnboardingSlide(
                  icon: Icons.article_outlined,
                  title: "Manage & Report",
                  description:
                      "Organize patient records, track history, and export PDF or Excel reports with ease.",
                ),
              ],
            ),
            Positioned(
              top: 50,
              right: 20,
              child: TextButton(
                onPressed: _completeOnboarding,
                child: const Text("SKIP",
                    style: TextStyle(
                        color: AppColors.accent, fontWeight: FontWeight.bold)),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  SmoothPageIndicator(
                    controller: _controller,
                    count: 3,
                    effect: const ExpandingDotsEffect(
                      spacing: 12,
                      dotHeight: 10,
                      dotWidth: 10,
                      dotColor: AppColors.primaryLight,
                      activeDotColor: AppColors.accent,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 200,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () {
                        if (_isLastPage) {
                          _completeOnboarding();
                        } else {
                          _controller.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      child: Text(
                        _isLastPage ? "GET STARTED" : "NEXT",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingSlide extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const OnboardingSlide({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ✅ NEW: Icons are now a dark color with a nice gradient effect
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.accent],
            ).createShader(bounds),
            child: Icon(
              icon,
              size: 100,
              color: Colors.white, // This color is the base for the gradient
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(4, 4),
                )
              ],
            ),
          ),
          const SizedBox(height: 48),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.deep,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.deep.withValues(alpha: 0.7),
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 120), // Extra space to push content up
        ],
      ),
    );
  }
}