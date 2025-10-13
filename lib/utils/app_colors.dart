// lib/utils/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Palette (semantic names)
  static const Color primary = Color(0xFF51848f);      // dark teal - main brand color
  static const Color primaryLight = Color(0xFF6BABC4); // light blue accent
  static const Color accent = Color(0xFF023F40);       // teal secondary
  static const Color surfaceLight = Color(0xFFD0EAEB); // pale mint / soft surface
  static const Color muted = Color(0xFF9E9E9E);        // neutral grey
  static const Color deep = Color(0xFF172737);         // deep navy / headings

  // Utility/semantic
  static const Color scaffoldBackground = Color(0xFFF5F5F5); // keep the subtle gray if desired
  static const Color warning = Color(0xFFA03232); // soft red for warnings/errors
  static const Color success = Color(0xFF34b233); // green for success
  

  // Text colors
  static const Color textPrimary = Color(0xFF172737);   // deep navy
  static const Color textSecondary = Color(0xFF51848f); // dark teal
  static const Color textMuted = Color(0xFF9E9E9E);
  static const Color textOnPrimary = Colors.white;      // white text on primary color
      
}
