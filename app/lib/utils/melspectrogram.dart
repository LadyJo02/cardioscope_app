// lib\utils\melspectrogram.dart

import 'package:cardioscope_app/services/tflite_service.dart';

/// Called by recovery queue to rebuild mel-spectrogram PNG
Future<void> generateMelSpectrogram(String filePath) async {
  try {
    await TfliteService().generateMelImageBytes(filePath);
  } catch (_) {
    // gracefully ignore — model may not be loaded yet or file missing
  }
}
