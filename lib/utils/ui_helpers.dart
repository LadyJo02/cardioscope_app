import 'package:flutter/material.dart';

// A helper class for consistent UI elements like status indicators.
class UIHelpers {
  /// Returns a color based on the classification string.
  static Color getStatusColor(String? classification) {
    switch (classification) {
      case 'Normal':
        return Colors.green.shade600;
      case 'Murmur': // Or other abnormal types like MS, MR, MVP
      case 'MS':
      case 'MR':
      case 'MVP':
        return Colors.red.shade600;
      default: // This will cover 'Pending' or null
        return Colors.grey.shade400;
    }
  }

  /// Returns an Icon widget with the appropriate status color.
  static Widget getStatusIndicator(String? classification, {double size = 12.0}) {
    return Icon(
      Icons.circle,
      color: getStatusColor(classification),
      size: size,
    );
  }
}