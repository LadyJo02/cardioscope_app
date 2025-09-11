import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class ResultsPage extends StatefulWidget {
  final String tempAudioPath;
  const ResultsPage({super.key, required this.tempAudioPath});

  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  Future<void> _saveReport() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final storagePath = '${directory.path}/CardioScope/heart_sounds';
      final storageDir = Directory(storagePath);

      if (!await storageDir.exists()) {
        await storageDir.create(recursive: true);
      }
      
      final patientName = _nameController.text.trim().replaceAll(' ', '_');
      final date = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      // --- FIX: Changed file extension to .m4a ---
      final newFileName = '${patientName}_$date.m4a';
      final newFilePath = '$storagePath/$newFileName';

      final tempFile = File(widget.tempAudioPath);
      await tempFile.copy(newFilePath);
      await tempFile.delete();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report saved successfully!')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving report: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis & Save', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
                const SizedBox(height: 20),
                const Text(
                  'Recording Complete!',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter patient name to save the report.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Patient Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a patient name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC31C42),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      textStyle: const TextStyle(fontSize: 16)),
                  onPressed: _saveReport,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save Report'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  child: const Text('Discard Recording'),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}