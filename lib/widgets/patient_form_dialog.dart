// 📁 lib/widgets/patient_form_dialog.dart
import 'dart:developer' as developer;

import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';
import '../services/storage_service.dart';

class PatientFormDialog extends StatefulWidget {
  final bool isSwitchMode;

  const PatientFormDialog({super.key, this.isSwitchMode = false});

  @override
  State<PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends State<PatientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _birthdayController = TextEditingController();
  final _symptomsController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  DateTime? _selectedDate;
  String? _selectedGender;
  int? _calculatedAge;
  bool _isExistingPatient = false;

  final db = DatabaseHelper.instance;
  final storage = StorageService();

  @override
  void dispose() {
    _nameController.dispose();
    _birthdayController.dispose();
    _symptomsController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  int _calculateAge(DateTime birthDate) {
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  Future<List<String>> _getSuggestions(String pattern) async {
    if (pattern.trim().isEmpty) return [];
    final results = await db.getPatientSuggestions(pattern.trim());
    return results
        .where((name) => name.toLowerCase().contains(pattern.toLowerCase()))
        .toList();
  }

  Future<Map<String, dynamic>?> _getPatient(String name) async {
    return await db.getPatientDetails(name);
  }

  void _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 365 * 20)),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select Birthday',
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _birthdayController.text = DateFormat('yyyy-MM-dd').format(picked);
        _calculatedAge = _calculateAge(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final birthday = _birthdayController.text.trim();
    final gender = _selectedGender ?? 'Unspecified';
    final age = _selectedDate != null ? _calculateAge(_selectedDate!) : null;
    final symptoms = _symptomsController.text.trim();

    final prefs = await SharedPreferences.getInstance();
    final practitionerId = prefs.getInt('practitioner_id') ?? 1;

    final patientData = {
      'name': name,
      'birthday': birthday,
      'age': age,
      'gender': gender,
      'symptoms': symptoms,
    };

    final basePath = await storage.getSavedPath();
    if (basePath == null || basePath.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage not ready. Please restart app.')),
      );
      return;
    }

    final existing = await _getPatient(name);
    int patientId;
    String folderPath = "";

    if (existing != null) {
      patientId = existing['patient_id'];
      folderPath = existing['folder_path'] ?? "";

      await db.database.then((conn) {
        conn.update(
          'patients',
          patientData,
          where: 'patient_id = ?',
          whereArgs: [patientId],
        );
      });

      if (folderPath.isEmpty) {
        folderPath = await storage.createPatientSubfolders(basePath, patientId);
        await db.updatePatientFolderPath(patientId, folderPath);
      }

      developer.log("🔄 Updated patient $patientId");
    } else {
      patientId = await db.findOrCreatePatient(practitionerId, patientData);
      folderPath = await storage.createPatientSubfolders(basePath, patientId);
      await db.updatePatientFolderPath(patientId, folderPath);

      developer.log("🆕 New patient $patientId");
    }

    await storage.setCurrentPatient(patientId);

    if (!mounted) return;
    Navigator.pop(context, {
      'patient_id': patientId,
      ...patientData,
      'folder_path': folderPath,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.isSwitchMode ? 'Switch Patient' : 'Patient Information',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TypeAheadField<String>(
                debounceDuration: const Duration(milliseconds: 100),
                suggestionsCallback: _getSuggestions,
                builder: (context, controller, focusNode) {
                  controller.text = _nameController.text;
                  controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: controller.text.length),
                  );
                  return TextFormField(
                    controller: _nameController,
                    focusNode: focusNode,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Patient Name',
                      hintText: 'e.g., Juan Dela Cruz',
                      suffixIcon: _isExistingPatient
                          ? IconButton(
                              icon: const Icon(Icons.edit, color: AppColors.primary),
                              onPressed: () {
                                setState(() {
                                  _isExistingPatient = false;
                                  _nameController.clear();
                                  _birthdayController.clear();
                                  _symptomsController.clear();
                                  _selectedGender = null;
                                  _selectedDate = null;
                                  _calculatedAge = null;
                                });
                              },
                            )
                          : null,
                    ),
                    validator: (v) => v == null || v.isEmpty ? 'Enter a name' : null,
                    onChanged: (_) => setState(() {}),
                  );
                },
                itemBuilder: (_, suggestion) =>
                    ListTile(title: Text(suggestion)),
                onSelected: (suggestion) async {
                  final data = await _getPatient(suggestion);
                  _nameController.text = suggestion;

                  setState(() {
                    _isExistingPatient = true;
                    _birthdayController.text = data?['birthday'] ?? '';
                    _symptomsController.text = data?['symptoms'] ?? '';
                    _selectedGender = data?['gender'];

                    if (data?['birthday'] != null && data!['birthday'].toString().isNotEmpty) {
                      final parsed = DateTime.tryParse(data['birthday']);
                      if (parsed != null) {
                        _selectedDate = parsed;
                        _calculatedAge = _calculateAge(parsed);
                      }
                    }
                  });
                },
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _birthdayController,
                      readOnly: true,
                      onTap: _pickDate,
                      decoration: const InputDecoration(
                        labelText: 'Birthday',
                        suffixIcon: Icon(Icons.calendar_today_rounded),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Select birthday' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_calculatedAge != null)
                    Text("Age: $_calculatedAge",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        )),
                ],
              ),

              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _selectedGender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                ],
                onChanged: (v) => setState(() => _selectedGender = v),
                validator: (v) => v == null ? 'Please select gender' : null,
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _symptomsController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Symptoms',
                  hintText: 'Shortness of breath, chest pain, etc.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(widget.isSwitchMode ? 'Switch' : 'Proceed'),
        ),
      ],
    );
  }
}
