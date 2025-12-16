// lib/utils/app_theme.dart
import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: AppColors.primary,

    // Soft light background (from #f5f5f5)
    scaffoldBackgroundColor: AppColors.scaffoldBackground,

    // Cards stay slightly lighter for contrast
    cardColor: AppColors.lightSurface,

    dividerColor: Colors.grey.shade400,
    shadowColor: Colors.black26,

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 20,
      ),
    ),

    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      // 👇 Matches scaffold background for uniform light pages
      surface: AppColors.scaffoldBackground,
      onSurface: Colors.black87,
      secondary: AppColors.deep,

      error: AppColors.error,
      onError: AppColors.onError,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: const Color(0xFF121212),
    cardColor: AppColors.darkSurface,
    dividerColor: Colors.grey,
    shadowColor: Colors.black54,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 20,
      ),
    ),
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      surface: AppColors.darkSurface,
      onSurface: Colors.white70,
      secondary: AppColors.deep,

      error: AppColors.error,
      onError: AppColors.onError,
    ),
  );
}
