import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database_helper.dart';
import '../main.dart';
import 'forgot_pin_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _showLoginView = true;

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
  }

  @override
  void dispose() {
    _loginPinController.dispose();
    _registerNameController.dispose();
    _registerPinController.dispose();
    _registerAnswerController.dispose();
    super.dispose();
  }

  Future<void> _loadPractitioners() async {
    final rows = await db.getAllPractitioners();
    if (mounted) {
      setState(() {
        practitioners = rows;
      });
    }
  }

  Future<void> _login() async {
    setState(() => _loginError = null);
    if (_selectedPractitioner == null || _loginPinController.text.isEmpty) {
      setState(() => _loginError = "Please select a profile and enter your PIN.");
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
    final practitionerId = practitioner['practitioner_id'];
    final practitionerName = practitioner['name'];
    if (practitionerId == null || practitionerName == null) {
      setState(() => _loginError = "Profile data is corrupted. Please re-register.");
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("practitioner_id", practitionerId as int);
    await prefs.setString("practitioner_name", practitionerName as String);
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Important Reminder"),
        content: const Text(
          "⚠️ Please take note of your Security Question & Answer.\n\n"
          "If you forget them, you will not be able to reset your PIN "
          "and may lose access to your patient records.",
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
      'security_answer': _registerAnswerController.text.trim().toLowerCase(),
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
    setState(() => _selectedQuestion = null);
    _toggleView();
    _showMessage("Registration successful! You can now log in.");
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ));
  }

  void _toggleView() {
    setState(() {
      _loginError = null;
      _registerError = null;
      _showLoginView = !_showLoginView;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // ✅ NEW: Gradient background to match your new design
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blueGrey.shade50,
              const Color(0xFFE0F7FA),
              Colors.teal.shade50,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ✅ NEW: Logo uses its original colors
                  Image.asset(
                    'assets/images/app_logo.png',
                    height: 120,
                  ),
                  const SizedBox(height: 16),
                  // ✅ NEW: Text uses the primary app color
                  const Text("CardioScope",
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.deep,
                        letterSpacing: 0.5,
                      )),
                  const SizedBox(height: 8),
                  Text("AI-Powered Heart Sound Analysis",
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.deep.withValues(alpha: 0.7),
                      )),
                  const SizedBox(height: 40),
                  Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(24),
                    shadowColor: Colors.black38,
                    child: Container(
                      decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(24)),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(opacity: animation, child: child);
                          },
                          child: _showLoginView
                              ? _buildLoginView()
                              : _buildRegisterView(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
          items: practitioners.map((p) => DropdownMenuItem<String>(
                value: p['name'] as String,
                child: Text(p['name'] as String),
              )).toList(),
          onChanged: (val) => setState(() => _selectedPractitioner = val),
          decoration: _inputDecoration("Select Profile", Icons.person_outline),
          hint: const Text("Select your profile"),
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ForgotPinPage()),
              );
            },
            child: const Text("Forgot PIN?"),
          ),
        ),
        const SizedBox(height: 8),
        _buildAuthButton(label: "Login", onPressed: _login),
        const SizedBox(height: 24),
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
            "What is your favorite color?",
            "What is your mother's maiden name?",
            "What was your first pet's name?",
          ].map((q) => DropdownMenuItem(value: q, child: Text(q))).toList(),
          onChanged: (val) => setState(() => _selectedQuestion = val),
          decoration: _inputDecoration("Security Question", Icons.help_outline),
          hint: const Text("Select a question"),
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
        const SizedBox(height: 24),
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
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }

  Widget _buildAuthButton({required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildToggleRow({required String label, required String buttonLabel, required VoidCallback onPressed}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600)),
        TextButton(
          onPressed: onPressed,
          child: Text(buttonLabel, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
        )
      ],
    );
  }
}