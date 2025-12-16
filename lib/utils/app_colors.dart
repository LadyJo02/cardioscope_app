// lib/utils/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // 🌊 Brand colors
  static const Color primary = Color(0xFF51848F);      // dark teal
  static const Color primaryLight = Color(0xFF6BABC4); // light teal accent
  static const Color accent = Color(0xFF023F40);       // deep teal-green
  static const Color deep = Color(0xFF172737);         // dark navy text
  static const Color muted = Color(0xFF9E9E9E);        // gray text

  // 🌗 Background / surface tones
  static const Color surfaceLight = Color(0xFFE6F4F5); // soft mint background
  static const Color lightSurface = Color(0xFFF9F9F9); // light cards
  static const Color darkSurface = Color(0xFF2A2A2A);  // dark cards
  static const Color scaffoldBackground = Color(0xFFF5F5F5);

  // ✅ Utility
  static const Color warning = Color(0xFFA03232);
  static const Color success = Color(0xFF2E7D32);

  static const Color error = Color(0xFFB3261E);
  static const Color onError = Colors.white;

  // 📝 Text
  static const Color textPrimary = Color(0xFF172737);
  static const Color textSecondary = Color(0xFF51848F);
  static const Color textMuted = Color(0xFF9E9E9E);
  static const Color textOnPrimary = Colors.white;
}
