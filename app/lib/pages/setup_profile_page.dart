import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';
import '../main.dart';
import '../utils/app_colors.dart'; 

class SetupProfilePage extends StatefulWidget {
  final int practitionerId;
  final String email;

  const SetupProfilePage({
    super.key,
    required this.practitionerId,
    required this.email,
  });

  @override
  State<SetupProfilePage> createState() => _SetupProfilePageState();
}

class _SetupProfilePageState extends State<SetupProfilePage> {
  final _nameCtl = TextEditingController();
  final _clinicCtl = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  Future<void> _preload() async {
    final db = DatabaseHelper.instance;
    final row = await db.getPractitionerById(widget.practitionerId);
    if (row != null) {
      _nameCtl.text = row['name'] ?? '';
      _clinicCtl.text = row['clinic_name'] ?? '';
    }
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    final clinic = _clinicCtl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = "Please enter your full name.");
      return;
    }

    setState(() => _loading = true);

    try {
      final db = DatabaseHelper.instance;
      await db.updatePractitionerProfile(
        widget.practitionerId,
        name: name,
        clinicName: clinic,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("practitioner_name", name);
      await prefs.setString("clinic_name", clinic);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Complete Profile"),
        backgroundColor: AppColors.primary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Welcome back 👋\nPlease confirm your details to continue.",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),

            TextField(
              controller: _nameCtl,
              decoration: const InputDecoration(
                labelText: "Full Name",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _clinicCtl,
              decoration: const InputDecoration(
                labelText: "Clinic / Facility (optional)",
                border: OutlineInputBorder(),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],

            const Spacer(),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Continue",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
