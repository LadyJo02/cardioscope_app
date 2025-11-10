// 📁 lib/pages/login.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cardioscope_app/pages/setup_profile_page.dart';
import 'package:cardioscope_app/services/auth_backup_service.dart';
import 'package:cardioscope_app/services/storage_service.dart';
import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../database_helper.dart';
import '../main.dart';
import 'forgot_pin_page.dart';

// Canonicalize email
String _canonicalizeEmail(String input) {
  final raw = input.trim().toLowerCase();
  final parts = raw.split('@');
  if (parts.length != 2) return raw;
  var local = parts[0];
  final domain = parts[1];
  if (domain == 'gmail.com' || domain == 'googlemail.com') {
    local = local.split('+').first.replaceAll('.', '');
  }
  return '$local@$domain';
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _showLoginView = true;
  static bool _restorePromptShown = false;
  bool _loginPinVisible = false;
  bool _registerPinVisible = false;


  // ✅ Public helper to reset the restore prompt
  static void resetRestorePrompt() {
    _restorePromptShown = false;
  }


  // Form controllers
  final _loginPinController = TextEditingController();
  final _registerNameController = TextEditingController();
  final _registerClinicNameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPinController = TextEditingController();
  final _registerAnswerController = TextEditingController();
  final TextEditingController _loginEmailCtl = TextEditingController();

  String? _loginError;
  String? _registerError;
  String? _selectedQuestion;
  bool _acceptedTerms = false;

  final db = DatabaseHelper.instance;
  List<String> _emailSuggestions = [];

  DateTime _lastLoginTap = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isLoggingIn = false;
  bool _isRegistering = false;

  String _safeQuestion(String? q) =>
      (q?.trim().isNotEmpty ?? false) ? q! : "Security Question";

  bool _debouncedTap({int ms = 600}) {
    final now = DateTime.now();
    if (now.difference(_lastLoginTap).inMilliseconds < ms) return false;
    _lastLoginTap = now;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadPractitioners();
  }

  @override
  void dispose() {
    _loginPinController.dispose();
    _registerNameController.dispose();
    _registerClinicNameController.dispose();
    _registerEmailController.dispose();
    _registerPinController.dispose();
    _registerAnswerController.dispose();
    super.dispose();
  }

  Future<void> _loadPractitioners() async {
    final rows = await db.getAllPractitioners();
    final seen = <String>{};
    setState(() {
      _emailSuggestions = rows
          .map((e) => e['email']?.toString().trim().toLowerCase() ?? '')
          .where((e) => e.isNotEmpty)
          .where((email) => seen.add(email))
          .toList();
    });
  }

  // ✅ NEW: Backup detect & prompt
  Future<void> _checkForBackupAndPrompt({
    required int practitionerId,
    required String practitionerEmail,
  }) async {
    if (_restorePromptShown) return;
    _restorePromptShown = true;

    final storage = StorageService();
    final backupDir = storage.externalBackupRoot;

    if (!await backupDir.exists()) return;

    final entries = backupDir.listSync().whereType<Directory>().toList();
    if (entries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No previous backup found.")),
        );
      }
      return;
    }

    final conn = await db.database;
    int count = 0;
    try {
      final result = await conn.rawQuery('SELECT COUNT(*) FROM heart_sound_records');
      count = Sqflite.firstIntValue(result) ?? 0;
    } catch (_) {
      count = 0;
    }

    if (count > 0) return; // DB not empty

    if (!mounted) return;
    final restore = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          "Previous CardioScope data detected",
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          "A prior CardioScope record archive is present on this device.\n\n"
          "\n\nWould you like to restore your patient cases and recordings?"
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Not now"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Restore"),
          ),
        ],
      ),
    );

    if (!mounted || restore != true) return;

// ✅ Skip asking PIN again if already verified in login
String? pinCheck;
final alreadyAuthed = _isLoggingIn == false && !_showLoginView;

if (alreadyAuthed) {
  pinCheck = _loginPinController.text.trim();
} else {
  pinCheck = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final pinCtrl = TextEditingController();
      return AlertDialog(
        title: const Text("Security Check"),
        content: TextField(
          controller: pinCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: "Enter your 6-digit PIN to restore data",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, pinCtrl.text.trim()), child: const Text("Verify")),
        ],
      );
    },
  );
}

// If user cancelled or length invalid
if (pinCheck == null || pinCheck.length != 6) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("❌ PIN verification failed.")),
    );
    // Surface a clear auth error so the user can try again normally
    _loginError = "Invalid email or PIN.";
    setState(() {});
  }
  return;
}
// We must fetch the practitioner row here
final practitionerRow = await db.getPractitionerById(practitionerId);
if (practitionerRow == null) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Practitioner not found for restore.")),
    );
  }
  return;
}


// Validate the entered PIN against stored hash
final ok = await verifySecret(
  pinCheck,
  practitionerRow['pin_hash'] ?? '',
  practitionerRow['pin_salt'] ?? '',
  practitionerRow['pin_iters'] ?? 120000,
);

    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("PIN verification failed.")),
      );
      return;
    }

    // proceed restore
    await storage.rebuildDatabaseFromExistingFiles(
      practitionerEmail: practitionerEmail,
      practitionerId: practitionerId,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Data restored successfully.")),
    );

    // Force UI refresh after DB rebuild
    // ✅ After restore, check if profile incomplete
Future.delayed(const Duration(milliseconds: 400), () async {
  if (!mounted) return;

  final practitionerRow2 = await db.getPractitionerById(practitionerId);
  final name = (practitionerRow2?['name'] ?? '').toString().trim();
  final clinic = (practitionerRow2?['clinic_name'] ?? '').toString().trim();
  final email = (practitionerRow2?['email'] ?? '').toString();

  final hasName = name.isNotEmpty;
  final hasClinic = clinic.isNotEmpty;

  if (!mounted) return;

  if (!hasName || !hasClinic) {
    debugPrint("➡️ Redirecting to SetupProfilePage after restore...");
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SetupProfilePage(
          practitionerId: practitionerId,
          email: email,
        ),
      ),
    );
    return;
  }

  Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => const MainNavigation()),
  );
});

  }

  // ---------------- LOGIN ----------------
  Future<void> _login() async {
    if (_isLoggingIn) return;
    debugPrint("[LOGIN] handler started");

    final email = _loginEmailCtl.text.trim();
    final pin = _loginPinController.text.trim();

    if (email.isEmpty || pin.isEmpty) {
      setState(() => _loginError = "Please enter your email and PIN.");
      return;
    }

    setState(() => _isLoggingIn = true);

    try {
      final emailCanon = _canonicalizeEmail(email);
      final conn = await db.database;

      await conn.rawUpdate('''
        UPDATE practitioners
        SET email_canonical = LOWER(email)
        WHERE (email_canonical IS NULL OR email_canonical = '') AND email != '';
      ''');

      final practitioner = await db.getPractitionerByEmailCanonical(emailCanon);
      if (practitioner == null) {
        final offered = await _offerRestoreFlowIfBackupPresent(emailCanon: emailCanon, rawEmail: email, pin: pin);
        if (!offered) {
          setState(() => _loginError = "Invalid email or PIN.");
        }
        return;
      }

      await _maybeEnrollIfAuthMissing(practitioner);

      final ok = await verifySecret(
        pin,
        practitioner['pin_hash'] ?? '',
        practitioner['pin_salt'] ?? '',
        practitioner['pin_iters'] ?? 120000,
      );

      if (!ok) {
        // maybe user is from an uninstalled build, offer restore
        final offered = await _offerRestoreFlowIfBackupPresent(emailCanon: emailCanon, rawEmail: email, pin: pin);
        if (!offered) {
          setState(() => _loginError = "Invalid email or PIN.");
        }
        return;
      }

      final pid = practitioner['practitioner_id'] as int;
      final name = practitioner['name'] as String;
      final emailReal = practitioner['email'] ?? '';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt("practitioner_id", pid);
      await prefs.setString("practitioner_email", emailReal);
      await prefs.setString("practitioner_name", name);
      await prefs.setString("clinic_name", practitioner['clinic_name'] ?? '');
      await prefs.setBool('isLoggedIn', true);

      // ✅ Prompt recovery BEFORE navigating
      await _checkForBackupAndPrompt(
        practitionerId: pid,
        practitionerEmail: emailReal,
      );

      if (!mounted) return;
      Future.microtask(() {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainNavigation()),
        );
      });

      // Background auto-scan safety
      Future.microtask(() async {
        final storage = StorageService();
        final securePath = await storage.ensureBaseFolderFor(
          practitionerId: pid,
          practitionerName: name,
          practitionerEmail: emailReal,
        );

        final result =
            await conn.rawQuery('SELECT COUNT(*) as count FROM heart_sound_records');
        final count = Sqflite.firstIntValue(result) ?? 0;

        if (count == 0) {
          await storage.rebuildDatabaseFromExistingFiles(
            practitionerEmail: emailReal,
            practitionerId: pid,
          );
        }

        debugPrint("✅ Secure path active: $securePath");
      });
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

// ✅ If login fails, offer restore based on backup presence (for returning users)
Future<bool> _offerRestoreFlowIfBackupPresent({
  required String emailCanon,
  required String rawEmail,
  required String pin,
}) async {
  final storage = StorageService();
  final backupRoot = storage.externalBackupRoot;

  if (!await backupRoot.exists()) return false;

  // Look for practitioner folder match via email canonical hash
  final dirs = backupRoot.listSync().whereType<Directory>();
  Directory? match;

  for (final d in dirs) {
    final meta = File("${d.path}/practitioner.meta.json");
    if (!meta.existsSync()) continue;

    try {
      final data = jsonDecode(await meta.readAsString());
      if (StorageService().metaMatchesEmailHash(data, emailCanon)) {
        match = d;
        break;
      }
    } catch (_) {}
  }

  if (match == null) return false;

  if (!mounted) return false;
  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text("Backup Detected"),
      content: const Text(
        "We found previous CardioScope data on this device.\n\n"
        "Would you like to restore your patient cases and recordings?"
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Restore")),
      ],
    ),
  );

  if (confirm != true) return true;

  if (!mounted) return false;
  // Ask for PIN to continue restore
  final pinCheck = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final pinCtrl = TextEditingController(text: pin);
      return AlertDialog(
        title: const Text("Security Check"),
        content: TextField(
          controller: pinCtrl,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: "Enter your 6-digit PIN"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, pinCtrl.text.trim()), child: const Text("Verify")),
        ],
      );
    },
  );

  if (pinCheck == null || pinCheck.length != 6) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("PIN verification failed.")),
      );
    }
    return true;
  }

  await storage.rebuildDatabaseFromExistingFiles(
    practitionerEmail: rawEmail,
    practitionerId: -1, // auto detect folder
  );

  if (!mounted) return true;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text("Data restored. Please login again.")),
  );

  return true; // ✅ ensure non-null return
}

  // ---------------- MIGRATE LEGACY USERS ----------------
  Future<void> _maybeEnrollIfAuthMissing(Map<String, dynamic> practitioner) async {
    final hasPin = (practitioner['pin_hash'] ?? '').toString().isNotEmpty;
    final hasAnswer = (practitioner['answer_hash'] ?? '').toString().isNotEmpty;
    final hasQuestion = (practitioner['security_question'] ?? '').toString().isNotEmpty;
    if (hasPin && hasAnswer && hasQuestion) return;

    final pid = practitioner['practitioner_id'] as int;
    final name = practitioner['name'];
    final email = practitioner['email'] ?? '';
    final emailCanon = _canonicalizeEmail(email);

    final newPinCtl = TextEditingController();
    final ansCtl = TextEditingController();
    String? selectedQ = practitioner['security_question'];

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text('Set PIN & Security Q&A'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: newPinCtl,
                obscureText: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (_debouncedTap() && !_isLoggingIn) _login();
                },
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(labelText: 'New 6-digit PIN'),
              ),
              DropdownButtonFormField<String>(
                initialValue: selectedQ,
                items: const [
                  DropdownMenuItem(value: "What is your favorite color?", child: Text("What is your favorite color?")),
                  DropdownMenuItem(value: "What is your mother's maiden name?", child: Text("What is your mother's maiden name?")),
                  DropdownMenuItem(value: "What was your first pet's name?", child: Text("What was your first pet's name?")),
                ],
                onChanged: (v) => selectedQ = v,
                decoration: const InputDecoration(labelText: "Security Question"),
              ),
              TextField(
                controller: ansCtl,
                decoration: const InputDecoration(labelText: 'Answer'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        );
      },
    );

    if (ok != true) return;

    final pinSecret = await hashSecret(newPinCtl.text);
    final ansSecret = await hashSecret(ansCtl.text);

    final conn = await db.database;
    await conn.update(
      'practitioners',
      {
        'security_question': selectedQ ?? '',
        'answer_hash': ansSecret.hashB64,
        'answer_salt': ansSecret.saltB64,
        'answer_iters': ansSecret.iters,
        'pin_hash': pinSecret.hashB64,
        'pin_salt': pinSecret.saltB64,
        'pin_iters': pinSecret.iters,
      },
      where: 'practitioner_id = ?',
      whereArgs: [pid],
    );

    unawaited(Future(() async {
      try {
        final storage = StorageService();
        final securePath = await storage.ensureBaseFolderFor(
          practitionerId: pid,
          practitionerName: name,
          practitionerEmail: email,
        );

        await AuthBackupService.saveAuthBackup(
          practitionerFolderPath: securePath,
          emailCanonical: emailCanon,
          question: _safeQuestion(selectedQ),
          answer: ansSecret,
        );
      } catch (e) {
        debugPrint("⚠️ Post-register storage setup failed: $e");
      }
    }));

    _showMessage("Security setup complete.");
  }

  // ---------------- REGISTER ----------------
  Future<void> _register() async {
    if (_isRegistering) return;

    final nameRaw = _registerNameController.text.trim();
    final emailRaw = _registerEmailController.text.trim();
    final pin = _registerPinController.text.trim();
    final answer = _registerAnswerController.text.trim().toLowerCase();

    if (nameRaw.isEmpty ||
        emailRaw.isEmpty ||
        pin.isEmpty ||
        _selectedQuestion == null ||
        answer.isEmpty) {
      setState(() => _registerError = "Please fill all fields.");
      return;
    }

    if (!_acceptedTerms) {
      setState(() => _registerError = "You must accept the Terms.");
      return;
    }

    if (pin.length != 6) {
      setState(() => _registerError = "PIN must be 6 digits.");
      return;
    }

    const weakPins = {"000000","111111","123456","654321","222222","121212"};
    if (weakPins.contains(pin)) {
      setState(() => _registerError = "PIN too weak. Choose a stronger 6-digit PIN.");
      return;
    }


    setState(() => _isRegistering = true);
    try {
      final emailCanon = _canonicalizeEmail(emailRaw);
      final existing = await db.getPractitionerByEmailCanonical(emailCanon);
      if (existing != null) {
        setState(() => _registerError = "Account already exists. Please login.");
        return;
      }

      final pinSecret = await hashSecret(pin);
      final answerSecret = await hashSecret(answer);

      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Important Reminder"),
          content: const Text(
            "Please remember your email, PIN, and security answer.\n\n"
            "If lost, your records cannot be recovered.",
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("I Understand"),
            ),
          ],
        ),
      );

      if (proceed != true) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final row = {
        'name': nameRaw,
        'clinic_name': _registerClinicNameController.text.trim(),
        'email': emailRaw,
        'email_canonical': emailCanon,
        'pin_hash': pinSecret.hashB64,
        'pin_salt': pinSecret.saltB64,
        'pin_iters': pinSecret.iters,
        'security_question': _selectedQuestion,
        'answer_hash': answerSecret.hashB64,
        'answer_salt': answerSecret.saltB64,
        'answer_iters': answerSecret.iters,
        'consent_agreed': _acceptedTerms ? 1 : 0,
      };

      final id = await db.insertPractitioner(row);

      unawaited(Future(() async {
        try {
          final storage = StorageService();
          final securePath = await storage.ensureBaseFolderFor(
            practitionerId: id,
            practitionerName: nameRaw,
            practitionerEmail: emailRaw,
          );

          await AuthBackupService.saveAuthBackup(
            practitionerFolderPath: securePath,
            emailCanonical: emailCanon,
            question: _safeQuestion(_selectedQuestion),
            answer: answerSecret,
          );
        } catch (e) {
          debugPrint("⚠️ Post-register storage setup failed: $e");
        }
      }));

      if (!mounted) return;
      Navigator.pop(context);

      _registerNameController.clear();
      _registerEmailController.clear();
      _registerPinController.clear();
      _registerAnswerController.clear();
      _selectedQuestion = null;
      _acceptedTerms = false;

      await _loadPractitioners();

      _toggleView();
      _showMessage("Registration successful. You can now log in.");
    } finally {
      if (mounted) setState(() => _isRegistering = false);
    }
  }

  // ---------------- UI HELPERS ----------------
  void _toggleView() {
    setState(() {
      _loginError = null;
      _registerError = null;
      _showLoginView = !_showLoginView;
    });
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blueGrey.shade50, Colors.teal.shade50],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Image.asset('assets/images/app_logo.png', height: 120),
                  const SizedBox(height: 16),
                  const Text(
                    "CardioScope",
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        child: _showLoginView ? _buildLoginView() : _buildRegisterView(),
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
        TypeAheadField<String>(
          suggestionsCallback: (pattern) {
            final input = pattern.toLowerCase().trim();
            if (input.isEmpty) return [];
            return _emailSuggestions
                .where((e) => e.toLowerCase().startsWith(input))
                .toList();
          },
          builder: (context, controller, focusNode) {
            // Keep our own controller in sync with the widget controller
            if (_loginEmailCtl.text != controller.text) {
              controller.text = _loginEmailCtl.text;
              controller.selection = TextSelection.fromPosition(
                TextPosition(offset: controller.text.length),
              );
            }

            return TextField(
              controller: controller, // ✅ use the provided controller
              focusNode: focusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username, AutofillHints.email],
              decoration: _inputDecoration("Email Address", Icons.email_outlined),
              onSubmitted: (_) {
                if (_debouncedTap() && !_isLoggingIn) _login();
              },
            );
          },
          itemBuilder: (context, suggestion) => ListTile(title: Text(suggestion)),
          onSelected: (suggestion) {
            _loginEmailCtl.text = suggestion; // keeps both in sync via listener
            FocusScope.of(context).unfocus();
            },
          ),

        const SizedBox(height: 16),

        TextField(
          controller: _loginPinController,
          obscureText: !_loginPinVisible,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_debouncedTap() && !_isLoggingIn) _login();
          },
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: _inputDecoration("Enter 6-digit PIN", Icons.lock_outline).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_loginPinVisible ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _loginPinVisible = !_loginPinVisible),
            ),
          ),    
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

        _authButton("Login", _login, loading: _isLoggingIn),
        const SizedBox(height: 24),

        _switchViewText("Don't have an account?", "Register", _toggleView),
      ],
    );
  }

  Widget _buildRegisterView() {
    return Column(
      key: const ValueKey('register'),
      children: [
        TextField(
          controller: _registerNameController,
          decoration: _inputDecoration("Full Name", Icons.person),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _registerClinicNameController,
          decoration: _inputDecoration("Clinic / Facility Name", Icons.local_hospital),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _registerEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: _inputDecoration("Email Address", Icons.email_outlined),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _registerPinController,
          obscureText: !_registerPinVisible,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_debouncedTap() && !_isLoggingIn) _login();
          },
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: _inputDecoration("6-digit PIN", Icons.lock).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_registerPinVisible ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _registerPinVisible = !_registerPinVisible),
            ),
          ),
        ),

        const SizedBox(height: 12),

DropdownButtonFormField<String>(
  isExpanded: true, // ✅ prevents overflow
  initialValue: _selectedQuestion,
  items: [
    "What is your favorite color?",
    "What is your mother's maiden name?",
    "What was your first pet's name?",
  ].map((q) {
    return DropdownMenuItem(
      value: q,
      child: Text(
        q,
        overflow: TextOverflow.ellipsis, // ✅ ellipsis for long text
        maxLines: 1,
      ),
    );
  }).toList(),
  onChanged: (v) => setState(() => _selectedQuestion = v),
  decoration: _inputDecoration("Security Question", Icons.help_outline),
),

        const SizedBox(height: 12),

        TextField(
          controller: _registerAnswerController,
          decoration: _inputDecoration("Answer", Icons.edit),
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const SizedBox(
            height: 100,
            child: SingleChildScrollView(
              child: Text(
                '''By registering, you confirm that:
1. You are a licensed or supervised medical practitioner or student using CardioScope for academic, diagnostic, or research purposes.
2. You agree to comply with the Data Privacy Act of 2012 (RA 10173) and ensure all patient data remains confidential.
3. You consent to secure, local storage of data on this device only.
4. You will ensure patient consent is obtained before every recording.''',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ),
        ),

        CheckboxListTile(
          title: const Text("I have read and agree to the Terms & Conditions"),
          value: _acceptedTerms,
          onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
        ),

        if (_registerError != null) ...[
          const SizedBox(height: 8),
          Text(_registerError!, style: const TextStyle(color: Colors.red)),
        ],

        const SizedBox(height: 12),

        _authButton("Register", _register, loading: _isRegistering),
        const SizedBox(height: 16),

        _switchViewText("Already have an account?", "Login", _toggleView),
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

  Widget _authButton(String label, Future<void> Function() onTap,
      {bool loading = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading
            ? null
            : () async {
                debugPrint("BUTTON TAP: $label");
                if (!_debouncedTap()) return;
                await onTap();
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: loading
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _switchViewText(String text, String button, VoidCallback onTap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(text),
        TextButton(
          onPressed: onTap,
          child: Text(button, style: const TextStyle(color: AppColors.primary)),
        ),
      ],
    );
  }
}
/// Public helper to reset backup-restore flag from other screens
class RestorePromptBridge {
  static void reset() {
    _LoginPageState.resetRestorePrompt();
  }
}
