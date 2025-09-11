import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_setup.dart'; 

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _resetAndGoToSetup(BuildContext context) async {
    // 1. Get the shared preferences instance
    final prefs = await SharedPreferences.getInstance();

    // 2. Remove the saved user name
    await prefs.remove('userName');

    // 3. Navigate to the setup page and clear all previous routes
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const ProfileSetupPage()),
        (Route<dynamic> route) => false, // This predicate removes all routes
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Settings",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFFC31C42),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ListTile(
            leading: const Icon(Icons.person_remove, color: Colors.red),
            title: const Text('Reset User Profile'),
            subtitle: const Text('This will clear your saved name and restart the app.'),
            onTap: () {
              // Show a confirmation dialog before resetting
              showDialog(
                context: context,
                builder: (BuildContext dialogContext) {
                  return AlertDialog(
                    title: const Text('Confirm Reset'),
                    content: const Text('Are you sure you want to clear your user profile? You will be asked to enter your name again.'),
                    actions: <Widget>[
                      TextButton(
                        child: const Text('Cancel'),
                        onPressed: () {
                          Navigator.of(dialogContext).pop(); // Close the dialog
                        },
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Reset'),
                        onPressed: () {
                          // Pass the main context to the reset function
                          _resetAndGoToSetup(context);
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
          // You can add more settings options here in the future
        ],
      ),
    );
  }
}