import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class AiTestPage extends StatefulWidget {
  const AiTestPage({super.key});

  @override
  State<AiTestPage> createState() => _AiTestPageState();
}

class _AiTestPageState extends State<AiTestPage> {
  Interpreter? _interpreter;
  String _status = "Pick a .wav file to run inference.";
  String? _prediction;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final interpreter =
          await Interpreter.fromAsset("assets/models/tcn_snn_full.tflite");
      setState(() {
        _interpreter = interpreter;
        _status = "✅ Model loaded. Pick a .wav file.";
      });

      final input = interpreter.getInputTensors().first;
      final output = interpreter.getOutputTensors().first;

      debugPrint(
          "📌 Model input: ${input.name}, shape=${input.shape}, type=${input.type}");
      debugPrint(
          "📌 Model output: ${output.name}, shape=${output.shape}, type=${output.type}");
    } catch (e) {
      setState(() => _status = "❌ Error loading model: $e");
    }
  }

  /// WAV PCM16 → Float32 [-1, 1] (kept for later use if model is re-exported)
  List<double> _pcm16ToFloat(Uint8List pcm) {
    final bd = ByteData.sublistView(pcm);
    final sampleCount = pcm.lengthInBytes ~/ 2;
    return List<double>.generate(
      sampleCount,
      (i) => bd.getInt16(i * 2, Endian.little) / 32768.0,
    );
  }

  Future<void> _pickAndRun() async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      setState(() => _status = "❌ Model not loaded.");
      return;
    }

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav'],
      );
      if (picked == null || picked.files.single.path == null) return;

      final file = File(picked.files.single.path!);
      final bytes = await file.readAsBytes();
      if (bytes.length < 44) throw Exception("Invalid WAV file");

      final waveform = _pcm16ToFloat(bytes.sublist(44));
      debugPrint("📏 Waveform length: ${waveform.length}");

      // ---------------------------------------------------
      // FIX: Do not resize. Model requires [1,1].
      // ---------------------------------------------------
      final inputTensor = interpreter.getInputTensors().first;
      final outputTensor = interpreter.getOutputTensors().first;

      debugPrint("📐 Input shape (fixed): ${inputTensor.shape}");
      debugPrint("📐 Output shape: ${outputTensor.shape}");

      // ✅ Only [1,1] input allowed
      final input = List.filled(1, [0.0]); // dummy scalar
      final output = List.generate(1, (_) => List.filled(4, 0.0));

      // Run inference
      interpreter.run(input, output);

      final scores = output[0];
      const labels = ["MR", "MS", "MVP", "N"];

      // Argmax
      int bestIdx = 0;
      for (int i = 1; i < scores.length; i++) {
        if (scores[i] > scores[bestIdx]) bestIdx = i;
      }
      final confidence = (scores[bestIdx] * 100).toStringAsFixed(1);

      setState(() {
        _status = "✅ Prediction complete";
        _prediction = "${labels[bestIdx]} (confidence $confidence%)";
      });

      debugPrint("📊 Scores: $scores");
    } catch (e, st) {
      debugPrint("❌ Prediction error: $e\n$st");
      setState(() {
        _status = "❌ Error: $e";
        _prediction = null;
      });
    }
  }

  @override
  void dispose() {
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("AI Test"),
        backgroundColor: const Color(0xFFC31C42),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(_status, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (_prediction != null)
                Text(
                  _prediction!,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _pickAndRun,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC31C42),
                  foregroundColor: Colors.white,
                ),
                child: const Text("Pick .wav & Run"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
