import 'package:cardioscope_app/database_helper.dart';
import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ForgotPinPage extends StatefulWidget {
  const ForgotPinPage({super.key});

  @override
  State<ForgotPinPage> createState() => _ForgotPinPageState();
}

class _ForgotPinPageState extends State<ForgotPinPage> {
  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> practitioners = [];
  String? _selectedPractitioner;
  Map<String, dynamic>? _practitionerData;
  final _answerController = TextEditingController();
  final _newPinController = TextEditingController();
  String? _error;
  int _attempts = 0;
  final int _maxAttempts = 3;

  @override
  void initState() {
    super.initState();
    _loadAllPractitioners();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _newPinController.dispose();
    super.dispose();
  }

  Future<void> _loadAllPractitioners() async {
    final rows = await db.getAllPractitioners();
    if (mounted) {
      setState(() {
        practitioners = rows;
      });
    }
  }

  Future<void> _loadPractitionerDetails(String name) async {
    final p = await db.getPractitionerByName(name);
    setState(() {
      _practitionerData = p;
      _selectedPractitioner = name;
      // Reset state when user changes
      _attempts = 0;
      _error = null;
      _answerController.clear();
      _newPinController.clear();
    });
  }

  Future<void> _resetPin() async {
    if (_practitionerData == null) return;

    final enteredAnswer = _answerController.text.trim().toLowerCase();
    final correctAnswer = (_practitionerData!['security_answer'] as String?)?.toLowerCase();

    if (correctAnswer == null || enteredAnswer != correctAnswer) {
      setState(() {
        _attempts++;
        if (_attempts >= _maxAttempts) {
          _error = "Too many failed attempts. Please contact support.";
        } else {
          _error = "Incorrect answer. Attempt $_attempts of $_maxAttempts.";
        }
      });
      return;
    }

    if (_newPinController.text.length != 6) {
      setState(() => _error = "New PIN must be 6 digits.");
      return;
    }

    await db.updatePractitionerPin(
        _practitionerData!['practitioner_id'], _newPinController.text);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("PIN reset successfully. You can now log in."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool attemptsExceeded = _attempts >= _maxAttempts;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Reset PIN"),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Select your profile to begin the recovery process.",
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              initialValue: _selectedPractitioner,
              items: practitioners
                  .map((p) => DropdownMenuItem(
                        value: p['name'] as String,
                        child: Text(p['name'] as String),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  _loadPractitionerDetails(val);
                }
              },
              decoration: InputDecoration(
                labelText: "Select Profile",
                prefixIcon: const Icon(Icons.person_outline, color: AppColors.accent),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              hint: const Text("Select your profile"),
            ),
            const SizedBox(height: 16),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _practitionerData != null ? 1.0 : 0.0,
              child: _practitionerData != null
                  ? _buildRecoveryForm(attemptsExceeded)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecoveryForm(bool attemptsExceeded) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text(
          "Security Question:",
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        Text(
          "${_practitionerData!['security_question']}",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _answerController,
          enabled: !attemptsExceeded,
          decoration: InputDecoration(
            labelText: "Your Answer",
            prefixIcon: const Icon(Icons.edit, color: AppColors.accent),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _newPinController,
          obscureText: true,
          enabled: !attemptsExceeded,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: InputDecoration(
            labelText: "New 6-Digit PIN",
            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.accent),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: attemptsExceeded ? null : _resetPin,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              "Reset PIN",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
