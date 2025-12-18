import 'dart:async';
import 'dart:io';

import 'package:cardioscope_app/database_helper.dart';
import 'package:cardioscope_app/services/tflite_service.dart';
import 'package:cardioscope_app/utils/melspectrogram.dart';
import 'package:flutter/material.dart';

class RecoveryReanalysisQueue {
  static final RecoveryReanalysisQueue _i = RecoveryReanalysisQueue._();
  RecoveryReanalysisQueue._();
  factory RecoveryReanalysisQueue() => _i;

  final List<int> _pending = [];
  bool _running = false;

  void add(int recordId) {
    _pending.add(recordId);
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;

    final db = DatabaseHelper.instance;

    while (_pending.isNotEmpty) {
      final recordId = _pending.removeAt(0);
      try {
        final rec = await (await db.database).query(
          "heart_sound_records",
          where: "record_id = ?",
          whereArgs: [recordId],
          limit: 1,
        );
        if (rec.isEmpty) continue;

        final filePath = rec.first['file_path'] as String;
        if (!await File(filePath).exists()) continue;

        // Spectrogram
        await generateMelSpectrogram(filePath);

        // AI inference
        final result = await TfliteService().runInference(filePath: filePath);
        if (result == null) continue;

        final diagnosis = result['label'];
        final probabilitiesJson = result['probabilities'].toString();
        final now = DateTime.now().toIso8601String();

        await db.upsertAnalysisByRecordId(
          recordId,
          diagnosis: diagnosis,
          probabilitiesJson: probabilitiesJson,
          analysisDateIso: now,
        );

      } catch (e) {
        debugPrint("⚠️ reanalysis error: $e");
      }
    }

    _running = false;
  }
}

final reanalysisQueue = RecoveryReanalysisQueue();
