// lib\pages\pdf_viewer_page.dart
import 'dart:io';

import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class PdfViewerPage extends StatelessWidget {
  final String filePath;
  final String title;

  const PdfViewerPage({super.key, required this.filePath, this.title = 'View Report'});

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primary,
      ),
      body: file.existsSync()
          ? SfPdfViewer.file(file)
          : const Center(
              child: Text("❌ File not found or deleted."),
            ),
    );
  }
}
