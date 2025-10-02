// lib/pages/login.dart
import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';
import '../main.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  bool _showLoginView = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final _loginPinController = TextEditingController();
  String? _selectedPractitioner;
  String? _loginError;

  final _registerNameController = TextEditingController();
  final _registerPinController = TextEditingController();
  String? _registerError;
  String? _selectedQuestion;
  final _registerAnswerController = TextEditingController();

  final db = DatabaseHelper.instance;
  List<Map<String, dynamic>> practitioners = [];

  @override
  void initState() {
    super.initState();
    _loadPractitioners();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _loginPinController.dispose();
    _registerNameController.dispose();
    _registerPinController.dispose();
    _registerAnswerController.dispose();
    super.dispose();
  }

  Future<void> _loadPractitioners() async {
    final database = await db.database;
    final rows = await database.query('practitioners');
    if (mounted) {
      setState(() {
        practitioners = rows;
      });
    }
  }

  Future<void> _login() async {
    setState(() => _loginError = null);

    if (_selectedPractitioner == null || _loginPinController.text.isEmpty) {
      setState(() => _loginError = "Please select your profile and enter your PIN.");
      return;
    }

    final practitioner = await db.getPractitioner(
      _selectedPractitioner!,
      _loginPinController.text,
    );

    if (practitioner == null) {
      setState(() => _loginError = "Invalid PIN. Please try again.");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("practitioner_id", practitioner['practitioner_id']);
    await prefs.setString("practitioner_name", practitioner['name']);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    }
  }

  Future<void> _register() async {
    setState(() => _registerError = null);

    if (_registerNameController.text.trim().isEmpty ||
        _registerPinController.text.isEmpty ||
        _selectedQuestion == null ||
        _registerAnswerController.text.trim().isEmpty) {
      setState(() => _registerError = "Please fill all fields.");
      return;
    }

    if (_registerPinController.text.length != 6) {
      setState(() => _registerError = "PIN must be 6 digits.");
      return;
    }

    // Confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Important Reminder"),
        content: const Text(
          "⚠️ Please take note of your Security Question & Answer.\n\n"
          "If you forget them, you will not be able to reset your PIN "
          "and may lose access to your patient records.\n\n"
          "Do you want to continue with registration?"
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Continue")),
        ],
      ),
    );

    if (confirm != true) return;

    final row = {
      'name': _registerNameController.text.trim(),
      'pin': _registerPinController.text,
      'security_question': _selectedQuestion,
      'security_answer': _registerAnswerController.text.trim(),
    };

    final id = await db.insertPractitioner(row);

    if (id == 0) {
      setState(() => _registerError = "A practitioner with this name already exists.");
      return;
    }

    await _loadPractitioners();
    _registerNameController.clear();
    _registerPinController.clear();
    _registerAnswerController.clear();
    _selectedQuestion = null;

    _toggleView();
    _showMessage("Registration successful! You can now log in.");
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _toggleView() {
    setState(() {
      _showLoginView = !_showLoginView;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Image.asset('assets/images/app_logo.png', height: 220),
                ),
                const SizedBox(height: 16),
                const Text("CardioScope",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.deep,
                    )),
                const SizedBox(height: 8),
                const Text("AI-Powered Heart Sound Analysis",
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.accent,
                    )),
                const SizedBox(height: 40),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _showLoginView
                      ? _buildLoginView()
                      : _buildRegisterView(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginView() {
    return Column(
      key: const ValueKey('login'),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedPractitioner,
          items: practitioners
              .map((p) => DropdownMenuItem<String>(
                    value: p['name'] as String,
                    child: Text(p['name'] as String),
                  ))
              .toList(),
          onChanged: (val) => setState(() => _selectedPractitioner = val),
          decoration: _inputDecoration("Select Profile", Icons.person_outline),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _loginPinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: _inputDecoration("Enter 6-digit PIN", Icons.lock_outline),
        ),
        if (_loginError != null) ...[
          const SizedBox(height: 8),
          Text(_loginError!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 24),
        _buildAuthButton(label: "Login", onPressed: _login),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ForgotPinPage()),
            );
          },
          child: const Text("Forgot PIN?",
              style: TextStyle(color: AppColors.primary)),
        ),
        const SizedBox(height: 16),
        _buildToggleRow(
          label: "Don't have an account?",
          buttonLabel: "Register",
          onPressed: _toggleView,
        ),
      ],
    );
  }

  Widget _buildRegisterView() {
    return Column(
      key: const ValueKey('register'),
      children: [
        TextField(
          controller: _registerNameController,
          decoration: _inputDecoration("Full Name", Icons.badge_outlined),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _registerPinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: _inputDecoration("Set 6-Digit PIN", Icons.lock_outline),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _selectedQuestion,
          items: [
            "Favorite color?",
            "Mother's maiden name?",
            "First pet's name?",
          ]
              .map((q) => DropdownMenuItem(value: q, child: Text(q)))
              .toList(),
          onChanged: (val) => setState(() => _selectedQuestion = val),
          decoration: _inputDecoration("Security Question", Icons.help_outline),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _registerAnswerController,
          decoration: _inputDecoration("Answer", Icons.edit),
        ),
        if (_registerError != null) ...[
          const SizedBox(height: 8),
          Text(_registerError!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 24),
        _buildAuthButton(label: "Register", onPressed: _register),
        const SizedBox(height: 16),
        _buildToggleRow(
          label: "Already have an account?",
          buttonLabel: "Login",
          onPressed: _toggleView,
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.accent),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildAuthButton(
      {required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildToggleRow(
      {required String label,
      required String buttonLabel,
      required VoidCallback onPressed}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label),
        TextButton(
          onPressed: onPressed,
          child: Text(buttonLabel,
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.bold)),
        )
      ],
    );
  }
}

// -------------------------
// Forgot PIN Screen
// -------------------------
class ForgotPinPage extends StatefulWidget {
  const ForgotPinPage({super.key});

  @override
  State<ForgotPinPage> createState() => _ForgotPinPageState();
}

class _ForgotPinPageState extends State<ForgotPinPage> {
  final db = DatabaseHelper.instance;
  String? _selectedPractitioner;
  Map<String, dynamic>? _practitioner;
  final _answerController = TextEditingController();
  final _newPinController = TextEditingController();
  String? _error;
  int _attempts = 0;

  @override
  void dispose() {
    _answerController.dispose();
    _newPinController.dispose();
    super.dispose();
  }

  Future<void> _loadPractitioner(String name) async {
    final p = await db.getPractitionerByName(name);
    setState(() => _practitioner = p);
  }

  Future<void> _resetPin() async {
    if (_practitioner == null) return;
    if (_answerController.text.trim().toLowerCase() !=
        (_practitioner!['security_answer'] as String).toLowerCase()) {
      setState(() {
        _attempts++;
        _error = "Incorrect answer. Attempt $_attempts of 3.";
      });
      if (_attempts >= 3) {
        setState(() => _error = "Too many failed attempts. Try later.");
      }
      return;
    }

    if (_newPinController.text.length != 6) {
      setState(() => _error = "PIN must be 6 digits.");
      return;
    }

    await db.updatePractitionerPin(
        _practitioner!['practitioner_id'], _newPinController.text);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("PIN reset successfully.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Forgot PIN")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedPractitioner,
              items: practitionersDropdown(),
              onChanged: (val) {
                setState(() => _selectedPractitioner = val);
                if (val != null) _loadPractitioner(val);
              },
              decoration:
                  const InputDecoration(labelText: "Select Practitioner"),
            ),
            const SizedBox(height: 16),
            if (_practitioner != null) ...[
              Text("Question: ${_practitioner!['security_question']}"),
              const SizedBox(height: 8),
              TextField(
                controller: _answerController,
                decoration: const InputDecoration(labelText: "Your Answer"),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _newPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(labelText: "New 6-Digit PIN"),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _resetPin,
                child: const Text("Reset PIN"),
              )
            ]
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<String>> practitionersDropdown() {
    return practitioners
        .map((p) => DropdownMenuItem(
              value: p['name'] as String,
              child: Text(p['name'] as String),
            ))
        .toList();
  }

  List<Map<String, dynamic>> practitioners = [];
  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final database = await db.database;
    final rows = await database.query('practitioners');
    if (mounted) {
      setState(() {
        practitioners = rows;
      });
    }
  }
}
