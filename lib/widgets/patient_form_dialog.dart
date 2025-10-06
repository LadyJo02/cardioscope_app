import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:intl/intl.dart';

import '../database_helper.dart';

class PatientFormDialog extends StatefulWidget {
  const PatientFormDialog({super.key});

  @override
  State<PatientFormDialog> createState() => _PatientFormDialogState();
}

class _PatientFormDialogState extends State<PatientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _birthdayController = TextEditingController();

  String? _selectedGender;
  DateTime? _selectedDate;

  final db = DatabaseHelper.instance;

  Future<List<String>> _getSuggestions(String pattern) async {
    final database = await db.database;
    final results = await database.query(
      'patients',
      where: 'name LIKE ?',
      whereArgs: ['%$pattern%'],
      limit: 5,
    );
    return results.map((e) => e['name'] as String).toList();
  }

  Future<Map<String, dynamic>?> _getPatientDetails(String name) async {
    final database = await db.database;
    final result = await database.query(
      'patients',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
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
      setState(() {
        _selectedDate = picked;
        _birthdayController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop({
        'name': _nameController.text.trim(),
        'birthday': _birthdayController.text.trim(),
        'gender': _selectedGender ?? 'Unspecified',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Patient Information',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              /// ✅ Updated for flutter_typeahead >= 5.0.0 (builder-based)
              TypeAheadField<String>(
                suggestionsCallback: _getSuggestions,
                builder: (context, controller, focusNode) {
                  _nameController.value = controller.value;
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Patient Name',
                      hintText: 'e.g., Dela Cruz, Juan A.',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Enter a name' : null,
                  );
                },
                itemBuilder: (context, String suggestion) {
                  return ListTile(title: Text(suggestion));
                },
                onSelected: (String suggestion) async {
                  _nameController.text = suggestion;
                  final data = await _getPatientDetails(suggestion);
                  if (data != null) {
                    setState(() {
                      _birthdayController.text = data['birthday'] ?? '';
                      _selectedGender = data['gender'];
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _birthdayController,
                readOnly: true,
                onTap: _pickDate,
                decoration: const InputDecoration(
                  labelText: 'Birthday',
                  suffixIcon: Icon(Icons.calendar_today_rounded),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Select birthday' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: const [
                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (val) => setState(() => _selectedGender = val),
                validator: (val) => val == null ? 'Select gender' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
          child: const Text('Proceed'),
        ),
      ],
    );
  }
}
