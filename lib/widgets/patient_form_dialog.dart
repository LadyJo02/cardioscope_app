import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';
import '../services/storage_service.dart';

class PatientFormDialog extends StatefulWidget {
  /// If true, the dialog was opened from “Switch Patient”.
  final bool isSwitchMode;

  const PatientFormDialog({super.key, this.isSwitchMode = false});

  @override
  State<PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends State<PatientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _birthdayController = TextEditingController();

  DateTime? _selectedDate;
  String? _selectedGender;
  int? _calculatedAge;
  bool _isExistingPatient = false;

  final db = DatabaseHelper.instance;
  final storage = StorageService();

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
    return await db.getPatientSuggestions(pattern);
  }

  Future<Map<String, dynamic>?> _getPatientDetails(String name) async {
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

    if (picked != null) {
      final age = _calculateAge(picked);
      setState(() {
        _selectedDate = picked;
        _birthdayController.text = DateFormat('yyyy-MM-dd').format(picked);
        _calculatedAge = age;
      });
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final birthday = _birthdayController.text.trim();
    final gender = _selectedGender ?? 'Unspecified';
    final age = _selectedDate != null ? _calculateAge(_selectedDate!) : null;

    final basePath = await storage.getSavedPath();
    if (basePath == null || basePath.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please select a base folder first (via the mic button).',
            ),
          ),
        );
      }
      return;
    }

    final patientFolder = await storage.createPatientFolder(basePath, name);

    final prefs = await SharedPreferences.getInstance();
    final practitionerId = prefs.getInt('practitioner_id') ?? 1;

    final patientData = {
      'name': name,
      'birthday': birthday,
      'age': age,
      'gender': gender,
      'folder_path': patientFolder,
    };

    final patientId = await db.findOrCreatePatient(practitionerId, patientData);
    await db.updatePatientFolderPath(patientId, patientFolder);
    await storage.setCurrentPatient(patientId);

    if (mounted) {
      Navigator.of(context).pop({
        'patient_id': patientId,
        'name': name,
        'birthday': birthday,
        'age': age,
        'gender': gender,
        'folder_path': patientFolder,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSwitchMode = widget.isSwitchMode;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        isSwitchMode ? 'Switch Patient' : 'Patient Information',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔹 Patient Name Field with Autocomplete
              TypeAheadField<String>(
                suggestionsCallback: _getSuggestions,
                builder: (context, controller, focusNode) {
                  controller.text = _nameController.text; // ✅ keep name visible
                  return TextFormField(
                    controller: _nameController,
                    focusNode: focusNode,
                    autofocus: !_isExistingPatient,   // Autofocus only for new patients
                    enabled: !_isExistingPatient,     // Disable if existing patient
                    decoration: InputDecoration(
                      labelText: 'Patient Name',
                      hintText: 'e.g., Dela Cruz, Juan A.',
                      suffixIcon: _isExistingPatient
                          ? IconButton(
                              icon: const Icon(Icons.edit, color: AppColors.primary),
                              tooltip: 'Edit name (create new patient)',
                              onPressed: () {
                                setState(() {
                                  _isExistingPatient = false;
                                  _nameController.clear();
                                  _birthdayController.clear();
                                  _selectedGender = null;
                                  _selectedDate = null;
                                  _calculatedAge = null;
                                });
                              },
                            )
                          : null,
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Enter a name' : null,
                  );
                },
                itemBuilder: (context, String suggestion) {
                  return ListTile(title: Text(suggestion));
                },
                onSelected: (String suggestion) async {
                  // ✅ Ensure name is displayed in text field
                  _nameController.text = suggestion;

                  final data = await _getPatientDetails(suggestion);
                  if (data != null) {
                    setState(() {
                      _isExistingPatient = true;
                      _birthdayController.text = data['birthday'] ?? '';
                      _selectedGender = data['gender'];
                      if (data['birthday'] != null &&
                          data['birthday'].toString().isNotEmpty) {
                        final parsed = DateTime.tryParse(data['birthday'].toString());
                        if (parsed != null) {
                          _selectedDate = parsed;
                          _calculatedAge = _calculateAge(parsed);
                        }
                      }
                    });
                  }
                },
              ),

              const SizedBox(height: 12),

              // 🔹 Birthday + Age
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
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
                      validator: (value) =>
                          value == null || value.isEmpty
                              ? 'Select birthday'
                              : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_calculatedAge != null)
                    Text(
                      "Age: $_calculatedAge",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // 🔹 Gender Dropdown
              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                ],
                onChanged: (val) => setState(() => _selectedGender = val),
                validator: (val) =>
                    val == null ? 'Please select gender' : null,
              ),
            ],
          ),
        ),
      ),

      // 🔹 Actions
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(isSwitchMode ? 'Switch' : 'Proceed'),
        ),
      ],
    );
  }
}
