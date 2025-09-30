import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Service class to run the TFLite preprocessing and classifier models.
class TfliteService {
  static final TfliteService _instance = TfliteService._internal();
  factory TfliteService() => _instance;
  TfliteService._internal();

  Interpreter? _preprocessorInterpreter;
  Interpreter? _classifierInterpreter;

  final String _preprocessorModelPath = "assets/models/preprocess_mel.tflite";
  final String _classifierModelPath   = "assets/models/tcn_snn.tflite";
  static const List<String> _labels   = ["MR", "MS", "MVP", "N"];

  bool get isReady =>
      _preprocessorInterpreter != null && _classifierInterpreter != null;

  // ==========================================================
  // Load both models
  // ==========================================================
  Future<void> loadModel() async {
    if (isReady) return;
    try {
      debugPrint("🔎 Loading TFLite models…");

      final pre = await Interpreter.fromAsset(_preprocessorModelPath);
      final cls = await Interpreter.fromAsset(_classifierModelPath);

      pre.allocateTensors();
      cls.allocateTensors();

      _preprocessorInterpreter = pre;
      _classifierInterpreter   = cls;

      debugPrint("✅ Both TFLite models loaded.");
    } catch (e, st) {
      debugPrint("❌ Error loading TFLite models: $e");
      debugPrint("Stacktrace: $st");
    }
  }

  // ==========================================================
  // Utility
  // ==========================================================
  /// Convert 16-bit PCM bytes to Float32 in range -1…1
  Float32List _pcm16ToFloat32List(Uint8List pcmBytes) {
    final byteData = ByteData.sublistView(pcmBytes);
    final sampleCount = pcmBytes.lengthInBytes ~/ 2;
    final floatList = Float32List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      floatList[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return floatList;
  }

  // ==========================================================
  // Inference
  // ==========================================================
  Future<Map<String, dynamic>?> runInference({String? filePath}) async {
    if (!isReady) await loadModel();
    if (!isReady) {
      debugPrint("❌ Models are not loaded. Cannot run inference.");
      return null;
    }

    try {
      //------------------------------------------------------------------
      // The new preprocessor expects 5 s of audio at 4 kHz → 20 000 samples
      //------------------------------------------------------------------
      const int expectedWaveformLength = 20000;
      Float32List waveform;

      // Load wav file (from local filesystem or copied asset)
      if (filePath != null && await File(filePath).exists()) {
        final fileBytes = await File(filePath).readAsBytes();
        if (fileBytes.length <= 44) {
          debugPrint("❌ Error: WAV file too small.");
          return null;
        }
        waveform = _pcm16ToFloat32List(fileBytes.sublist(44)); // skip 44-byte WAV header

        // pad / crop to exactly 20 000 samples
        if (waveform.length < expectedWaveformLength) {
          final padded = Float32List(expectedWaveformLength);
          padded.setRange(0, waveform.length, waveform);
          waveform = padded;
        } else if (waveform.length > expectedWaveformLength) {
          waveform = waveform.sublist(0, expectedWaveformLength);
        }
        debugPrint("🟢 Input waveform loaded: ${waveform.length} samples.");
      } else {
        debugPrint("❌ File not found: $filePath");
        return null;
      }

      //------------------ Step 1: Preprocessor ------------------
      final preInput  = [waveform]; // shape [1,20000]
      final preOutput = List.generate(128, (_) => List<double>.filled(150, 0.0));
      _preprocessorInterpreter!.run(preInput, preOutput);

      //------------------ Step 2: Classifier --------------------
      // Classifier has 2 outputs: [logits] and [softmax probabilities]
      final clsInput = [preOutput]; // shape [1,128,150]
      final Map<int, Object> outputs = {
        0: List.generate(1, (_) => List.filled(_labels.length, 0.0)), // logits
        1: List.generate(1, (_) => List.filled(_labels.length, 0.0)), // softmax
      };
      _classifierInterpreter!.runForMultipleInputs([clsInput], outputs);

      final probabilities = (outputs[1] as List<List<double>>)[0];
      final bestIndex =
          probabilities.indexWhere((p) => p == probabilities.reduce(max));
      final predictedLabel = _labels[bestIndex];

      // Print full probability distribution
      for (int i = 0; i < _labels.length; i++) {
        debugPrint("   ${_labels[i]}: ${(probabilities[i] * 100).toStringAsFixed(2)}%");
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

  // ==========================================================
  // Batch test helper
  // ==========================================================
  Future<void> testBatch(List<String> assetFiles) async {
    final tempDir = await getTemporaryDirectory();

    for (final asset in assetFiles) {
      // Copy asset wav to a temp file
      final bytes = await rootBundle.load(asset);
      final file = File("${tempDir.path}/${asset.split('/').last}");
      await file.writeAsBytes(bytes.buffer.asUint8List());

      debugPrint("🎧 Testing file: ${file.path}");
      final result = await runInference(filePath: file.path);

      if (result != null) {
        final probs = result['probabilities'] as Map<String, double>;
        probs.forEach((label, prob) {
          debugPrint("   $label: ${(prob * 100).toStringAsFixed(2)}%");
        });
        debugPrint("👉 Final Prediction: ${result['label']} "
            "(Conf: ${(result['confidence'] * 100).toStringAsFixed(2)}%)");
        debugPrint("--------------------------------------------------");
      }
    }
  }

  void dispose() {
    _preprocessorInterpreter?.close();
    _classifierInterpreter?.close();
    _preprocessorInterpreter = null;
    _classifierInterpreter = null;
    debugPrint("✅ TFLite interpreters disposed.");
  }
}
