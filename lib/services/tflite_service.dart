// lib/services/tflite_service.dart
import 'dart:io';
import 'dart:math';

import 'package:cardioscope_app/utils/latency_debug.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// 🎨 Accurate Inferno-Blue colormap version (matches matplotlib -1→4 range)
/// Handles safe waveform trimming/padding to prevent RangeErrors.
/// - preprocess_mel.tflite → generates mel-spectrogram (colored)
/// - tcn_snn_full.tflite → AI classification
class TfliteService {
  static final TfliteService _instance = TfliteService._internal();
  factory TfliteService() => _instance;
  TfliteService._internal();

  Interpreter? _preprocInterpreter;
  Interpreter? _mainInterpreter;

  final String _preprocModelPath = "assets/models/preprocess_mel.tflite";
  final String _mainModelPath = "assets/models/tcn_snn_full.tflite";

  static const List<String> _labels = ["N", "MR", "MS", "MVP"];
  static const int _expectedLength = 20000;

  bool get isPreprocReady => _preprocInterpreter != null;
  bool get isMainReady => _mainInterpreter != null;

  Future<void> loadModel() async => loadModels();

  Future<void> loadModels({bool loadClassifier = true}) async {
    LatencyDebug.start("🧠 AI", "Loading TFLite models");
    try {
      if (!isPreprocReady) {
        debugPrint("🔎 Loading preprocess_mel.tflite...");
        _preprocInterpreter = await Interpreter.fromAsset(_preprocModelPath);
        LatencyDebug.mark("🧠 AI", "Preprocess model loaded");
        debugPrint("✅ preprocess_mel.tflite loaded.");
      }
      if (!isMainReady) {
        debugPrint("🔎 Loading tcn_snn_full.tflite...");
        _mainInterpreter = await Interpreter.fromAsset(_mainModelPath);
        LatencyDebug.mark("🧠 AI", "Classifier model loaded");
        debugPrint("✅ tcn_snn_full.tflite loaded.");
      }
    } catch (e, st) {
      debugPrint("❌ Model load error: $e\n$st");
    }
    LatencyDebug.end("🧠 AI", "All models ready");
  }
    
  void dispose() {
    _preprocInterpreter?.close();
    _mainInterpreter?.close();
    _preprocInterpreter = null;
    _mainInterpreter = null;
  }

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(max);
    final exps = logits.map((x) => exp(x - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  Float32List _pcm16ToFloat32List(Uint8List pcmBytes) {
    final byteData = ByteData.sublistView(pcmBytes);
    final samples = pcmBytes.lengthInBytes ~/ 2;
    final out = Float32List(samples);
    for (int i = 0; i < samples; i++) {
      out[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  Float32List _normalizeWaveform(Float32List waveform) {
    if (waveform.length > _expectedLength) {
      return waveform.sublist(0, _expectedLength);
    } else if (waveform.length < _expectedLength) {
      final padded = Float32List(_expectedLength);
      padded.setRange(0, waveform.length, waveform);
      return padded;
    }
    return waveform;
  }

  Future<Map<String, dynamic>?> runInference({required String filePath, String? session,}) async {
    LatencyDebug.start("🧠 Inference", "Running AI on $filePath", session);
    try {
      await loadModels();
      if (!isMainReady) return null;

      final file = File(filePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      if (bytes.length < 44) return null;

      final pcm = bytes.sublist(44);
      var waveform = _pcm16ToFloat32List(Uint8List.fromList(pcm));
      waveform = _normalizeWaveform(waveform);
      LatencyDebug.mark("🧠 Inference", "Waveform normalized (length=${waveform.length})", session: session);

      final input = waveform.reshape([1, _expectedLength]);
      final outputTensor = _mainInterpreter!.getOutputTensors().first;
      final output = [List.filled(outputTensor.shape.last, 0.0)];

      final t0 = DateTime.now();
      _mainInterpreter!.run(input, output);
      LatencyDebug.mark("🧠 Inference", "Model run took ${DateTime.now().difference(t0).inMilliseconds} ms", session: session);

      final logits = output[0].map((e) => (e as num).toDouble()).toList();
      final probs = _softmax(logits);
      final bestIdx = probs.indexOf(probs.reduce(max));

      LatencyDebug.end("🧠 Inference", "Inference done: ${_labels[bestIdx]} (${(probs[bestIdx]*100).toStringAsFixed(1)}%)", session);
      return {
        'label': _labels[bestIdx],
        'confidence': probs[bestIdx],
        'probabilities': Map.fromIterables(_labels, probs),
      };
    } catch (e, st) {
      debugPrint("❌ Inference error: $e\n$st");
      return null;
    }
  }

  /// 🎨 Generate mel-spectrogram PNG (with optional PDF brightness correction)
  Future<Uint8List?> generateMelImageBytes(String filePath, {bool forPdf = false, String? session,}) async {
    LatencyDebug.start("🧠 Mel", "Generating Mel-spectrogram for $filePath", session);
    try {
      await loadModels();
      if (!isPreprocReady) return null;

      final file = File(filePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      if (bytes.length < 44) return null;

      final pcm = bytes.sublist(44);
      var waveform = _pcm16ToFloat32List(Uint8List.fromList(pcm));
      waveform = _normalizeWaveform(waveform);

      final input = waveform.reshape([1, _expectedLength]);
      final melOut = List.generate(128, (_) => List.filled(150, 0.0));

      final tMel = DateTime.now();
      _preprocInterpreter!.run(input, melOut);
      LatencyDebug.mark("🧠 Mel", "Mel run took ${DateTime.now().difference(tMel).inMilliseconds} ms", session: session);
      return _melToColoredPngBytes(melOut, forPdf: forPdf);
    } catch (e, st) {
      debugPrint("❌ Mel image generation failed: $e\n$st");
      LatencyDebug.end("🧠 Mel", "Mel image ready (128×150)", session);
      return null;
    }
  }

  /// 🧩 Converts mel values to colored PNG using Inferno-Blue colormap
  Uint8List _melToColoredPngBytes(List<List<double>> mel, {bool forPdf = false}) {
    double minVal = double.infinity, maxVal = double.negativeInfinity;
    for (var row in mel) {
      for (var v in row) {
        if (!v.isNaN) {
          if (v < minVal) minVal = v;
          if (v > maxVal) maxVal = v;
        }
      }
    }

    final range = (maxVal - minVal).abs() < 1e-9 ? 1.0 : maxVal - minVal;
    final width = mel[0].length;
    final height = mel.length;

    // ✅ v4 syntax (uses named params)
    final image = img.Image(width: width, height: height);

    // ✅ Gamma adjustment: slightly brighter for PDF to match app display
    final gamma = forPdf ? 0.72 : 0.82;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double norm = ((mel[y][x] - minVal) / range).clamp(0.0, 1.0);
        norm = pow(norm, gamma).toDouble();

        final color = _magmaColor(norm);
        image.setPixelRgb(x, y, color[0], color[1], color[2]);
      }
    }

    // ✅ Ensure it's RGB (no alpha)
    final rgbImage = img.copyResize(image,
        width: image.width, height: image.height, maintainAspect: false);

    // ✅ Encode cleanly
    return Uint8List.fromList(img.encodePng(rgbImage, level: 3));
  }

  /// 🎨 Inferno-Blue colormap (black → indigo → violet → red → orange → yellow)
  List<int> _magmaColor(double t) {
    t = t.clamp(0.0, 1.0);

    const stops = [
      [0.0, 0.0, 0.0, 0.0],      // black
      [0.05, 0.02, 0.02, 0.18],  // near black-blue
      [0.15, 0.09, 0.05, 0.40],  // indigo-violet
      [0.30, 0.26, 0.07, 0.55],  // violet-magenta
      [0.45, 0.50, 0.15, 0.60],  // red-purple
      [0.65, 0.85, 0.30, 0.45],  // 🔥 orange-red
      [0.80, 1.00, 0.60, 0.30],  // 🔆 bright orange-yellow
      [1.0, 1.00, 0.95, 0.70],   // ⚡ light yellow-white peak
    ];

    for (int i = 0; i < stops.length - 1; i++) {
      final a = stops[i];
      final b = stops[i + 1];
      if (t >= a[0] && t <= b[0]) {
        final f = (t - a[0]) / (b[0] - a[0]);
        final s = 0.5 - 0.5 * cos(f * pi);
        final r = a[1] + s * (b[1] - a[1]);
        final g = a[2] + s * (b[2] - a[2]);
        final bl = a[3] + s * (b[3] - a[3]);
        return [(r * 255).toInt(), (g * 255).toInt(), (bl * 255).toInt()];
      }
    }

    final c = stops.last;
    return [(c[1] * 255).toInt(), (c[2] * 255).toInt(), (c[3] * 255).toInt()];
  }
}