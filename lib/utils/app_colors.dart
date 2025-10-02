// lib/utils/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Palette (semantic names)
  static const Color primary = Color(0xFF023F40);      // dark teal - main brand color
  static const Color primaryLight = Color(0xFF6BABC4); // light blue accent
  static const Color accent = Color(0xFF4F838E);       // teal secondary
  static const Color surfaceLight = Color(0xFFD0EAEB); // pale mint / soft surface
  static const Color muted = Color(0xFF9E9E9E);        // neutral grey
  static const Color deep = Color(0xFF172737);         // deep navy / headings

  // Utility/semantic
  static const Color scaffoldBackground = Color(0xFFF5F5F5); // keep the subtle gray if desired
}
