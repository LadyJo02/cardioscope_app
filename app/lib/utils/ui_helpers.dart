// lib/utils/ui_helpers.dart
import 'package:flutter/material.dart';

import 'app_colors.dart';

class UIHelpers {
  static Color getStatusColor(String? classification) {
    switch (classification) {
      case 'Normal':
        return AppColors.primary; // healthy -> primary dark teal
      case 'MR':
        return AppColors.accent; // MR -> teal accent
      case 'MS':
        return AppColors.primaryLight; // MS -> lighter blue
      case 'MVP':
        return AppColors.surfaceLight; // MVP -> pale mint for visual distinction
      default:
        return Colors.grey; // pending or unknown
    }
  }

  static Widget getStatusIndicator(String? classification, {double size = 12.0}) {
    return Icon(
      Icons.circle,
      color: getStatusColor(classification),
      size: size,
    );
  }
}
