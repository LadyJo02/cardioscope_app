import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

class ExcelViewerPage extends StatefulWidget {
  final String filePath;
  final String title;

  const ExcelViewerPage({
    super.key,
    required this.filePath,
    this.title = "Excel Viewer",
  });

  @override
  State<ExcelViewerPage> createState() => _ExcelViewerPageState();
}

class _ExcelViewerPageState extends State<ExcelViewerPage> {
  List<List<String>> _data = [];

  @override
  void initState() {
    super.initState();
    _loadExcel();
  }

  Future<void> _loadExcel() async {
    try {
      final bytes = File(widget.filePath).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);

      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet != null) {
        setState(() {
          _data = sheet.rows
              .map((row) => row.map((c) => c?.value?.toString() ?? "").toList())
              .toList();
        });
      }
    } catch (e) {
      debugPrint("❌ Excel load error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(widget.title,
            style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
      ),
      body: _data.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: _data.first
                    .map((col) => DataColumn(label: Text(col)))
                    .toList(),
                rows: _data
                    .skip(1)
                    .map((r) => DataRow(
                          cells: r.map((c) => DataCell(Text(c))).toList(),
                        ))
                    .toList(),
              ),
            ),
    );
  }
}
