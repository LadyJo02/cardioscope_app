import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Service class to run inference using the combined TFLite model.
class TfliteService {
  static final TfliteService _instance = TfliteService._internal();
  factory TfliteService() => _instance;
  TfliteService._internal();

  Interpreter? _interpreter;

  final String _modelPath = "assets/models/tcn_snn_full.tflite";
  static const List<String> _labels = ["MR", "MS", "MVP", "N"];

  bool get isReady => _interpreter != null;

  Future<void> loadModel() async {
    if (isReady) return;
    try {
      debugPrint("🔎 Loading combined TFLite model…");
      final interpreter = await Interpreter.fromAsset(_modelPath);
      interpreter.allocateTensors();
      _interpreter = interpreter;
      debugPrint("✅ Combined model loaded successfully.");
    } catch (e, st) {
      debugPrint("❌ Error loading TFLite model: $e");
      debugPrint("Stacktrace: $st");
    }
  }

  Float32List _pcm16ToFloat32List(Uint8List pcmBytes) {
    final byteData = ByteData.sublistView(pcmBytes);
    final sampleCount = pcmBytes.lengthInBytes ~/ 2;
    final floatList = Float32List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      floatList[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return floatList;
  }
  
  /// =========== THIS IS THE MISSING FUNCTION ===========
  /// Converts raw logit scores from the model into a probability distribution.
  List<double> _softmax(List<double> logits) {
    if (logits.isEmpty) return [];
    final maxLogit = logits.reduce(max);
    final exps = logits.map((x) => exp(x - maxLogit)).toList();
    final sumExps = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sumExps).toList();
  }
  /// ==========================================================

  Future<Map<String, dynamic>?> runInference({String? filePath}) async {
    if (!isReady) await loadModel();
    if (!isReady) {
      debugPrint("❌ Model is not loaded. Cannot run inference.");
      return null;
    }

    try {
      // Your teammate mentioned training on 5-second clips.
      // 5 seconds @ 4000 Hz = 20000 samples.
      const int expectedWaveformLength = 20000;
      Float32List waveform;

      if (filePath != null && await File(filePath).exists()) {
        final fileBytes = await File(filePath).readAsBytes();
        if (fileBytes.length <= 44) {
          debugPrint("❌ Error: WAV file too small.");
          return null;
        }
        waveform = _pcm16ToFloat32List(fileBytes.sublist(44));

        if (waveform.length < expectedWaveformLength) {
          final padded = Float32List(expectedWaveformLength);
          padded.setRange(0, waveform.length, waveform);
          waveform = padded;
        } else if (waveform.length > expectedWaveformLength) {
          waveform = waveform.sublist(0, expectedWaveformLength);
        }
        debugPrint("🟢 Input waveform ready: ${waveform.length} samples.");
      } else {
        debugPrint("❌ File not found: $filePath");
        return null;
      }

      // Input must be List<List<double>> to avoid shape errors.
      final input = [waveform.toList()]; 
      
      // Assume the combined model now only has ONE output (the logits).
      final output = List.generate(1, (_) => List.filled(_labels.length, 0.0));

      _interpreter!.run(input, output);

      // --- FIX: Apply softmax to the logits to get probabilities ---
      final logits = output[0];
      final probabilities = _softmax(logits);
      // -----------------------------------------------------------

      final bestIndex =
          probabilities.indexWhere((p) => p == probabilities.reduce(max));
      final predictedLabel = _labels[bestIndex];

      debugPrint("--- Analysis Results ---");
      for (int i = 0; i < _labels.length; i++) {
        debugPrint(
            "   ${_labels[i]}: ${(probabilities[i] * 100).toStringAsFixed(2)}%");
      }
      debugPrint("🏆 Predicted: $predictedLabel "
          "(Conf: ${(probabilities[bestIndex] * 100).toStringAsFixed(2)}%)");

      return {
        'label': predictedLabel,
        'confidence': probabilities[bestIndex],
        'probabilities': Map.fromIterables(_labels, probabilities),
      };
    } catch (e, st) {
      debugPrint("❌ FATAL Error during inference: $e");
      debugPrint("Stacktrace:\n$st");
      return null;
    }
  }

  Future<void> testBatch(List<String> assetFiles) async {
    final tempDir = await getTemporaryDirectory();
    for (final asset in assetFiles) {
      final bytes = await rootBundle.load(asset);
      final file = File("${tempDir.path}/${asset.split('/').last}");
      await file.writeAsBytes(bytes.buffer.asUint8List());
      debugPrint("🎧 Testing file: ${file.path}");
      await runInference(filePath: file.path);
      debugPrint("--------------------------------------------------");
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    debugPrint("✅ TFLite interpreter disposed.");
  }
}