// lib/pages/results.dart

import 'package:flutter/material.dart';

class ResultsPage extends StatelessWidget {
  // Update the constructor to accept 'filePath' and 'patientName'
  final String filePath;
  final String patientName;

  const ResultsPage({
    super.key,
    required this.filePath,
    required this.patientName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Analysis for $patientName', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recording Saved!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Text(
              'Patient Name:',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[700]),
            ),
            Text(
              patientName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'File Location:',
               style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[700]),
            ),
            SelectableText(
              filePath,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
            const Spacer(),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC31C42),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                ),
                child: const Text('DONE'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}