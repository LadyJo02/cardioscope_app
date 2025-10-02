// lib/pages/login.dart
import 'package:flutter/material.dart';
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
  late TabController _tabController;

  final _loginPinController = TextEditingController();
  String? _selectedPractitioner;

  final _registerNameController = TextEditingController();
  final _registerPinController = TextEditingController();

  final db = DatabaseHelper.instance;

  List<Map<String, dynamic>> practitioners = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPractitioners();
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
    if (_selectedPractitioner == null || _loginPinController.text.isEmpty) {
      _showMessage("Please select a practitioner and enter PIN.");
      return;
    }

    final practitioner = await db.getPractitioner(
      _selectedPractitioner!,
      _loginPinController.text,
    );

    if (practitioner == null) {
      _showMessage("Invalid credentials. Try again.");
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
    if (_registerNameController.text.trim().isEmpty ||
        _registerPinController.text.isEmpty) {
      _showMessage("Please fill in all fields.");
      return;
    }

    final row = {
      'name': _registerNameController.text.trim(),
      'pin': _registerPinController.text,
    };

    final id = await db.insertPractitioner(row);

    if (id == 0) {
      _showMessage("Practitioner already exists.");
      return;
    }

    await _loadPractitioners();
    _registerNameController.clear();
    _registerPinController.clear();

    _tabController.animateTo(0);
    _showMessage("Registration successful. Please log in.");
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Center(child: Image.asset('assets/images/app_logo.png', height: 180)),
            const SizedBox(height: 20),
            TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFFC31C42),
              labelColor: const Color(0xFFC31C42),
              unselectedLabelColor: Colors.grey,
              tabs: const [
                Tab(text: "Login"),
                Tab(text: "Register"),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildLoginTab(),
                  _buildRegisterTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
            decoration: InputDecoration(
              labelText: "Select Practitioner",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _loginPinController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: "Enter PIN",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC31C42),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "Login",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(
            controller: _registerNameController,
            decoration: InputDecoration(
              labelText: "Practitioner Name",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _registerPinController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: "Set PIN",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _register,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC31C42),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "Register",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
