import 'package:flutter/material.dart';

// A helper class for consistent UI elements like status indicators.
class UIHelpers {
  /// Returns a color based on the classification string.
  static Color getStatusColor(String? classification) {
    switch (classification) {
      case 'Normal':
        return Colors.green; // Normal = green
      case 'MR':
        return Colors.orange; // MR = orange
      case 'MS':
        return Colors.purple; // MS = purple
      case 'MVP':
        return Colors.green; // MVP = green
      default: // Pending or null
        return Colors.grey;
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
