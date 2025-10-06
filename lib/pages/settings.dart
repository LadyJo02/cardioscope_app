import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show themeNotifier;
import 'faq_page.dart';
import 'login.dart'; // ✅ use login instead of profile setup
import 'quick_start_guide.dart';

class SettingsPage extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeNotifier;
  const SettingsPage({super.key, required this.themeNotifier});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _selectedLanguage = 'English';
  bool _isDataSyncOn = true;
  StreamSubscription<Set<AudioDevice>>? _devicesSubscription;
  bool _isUsbMicConnected = false;
  String _deviceStatusText = 'Please connect the CardioScope receiver.';

  final String _storageUsed = "128.5 MB";
  final String _appVersion = "1.0.0";

  @override
  void initState() {
    super.initState();
    _initAudioSession();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
    _devicesSubscription = session.devicesStream.listen((devices) {
      _checkConnectedDevices(devices.toList());
    });
    _checkConnectedDevices((await session.getDevices()).toList());
  }

  void _checkConnectedDevices(List<AudioDevice> devices) {
    final usbDevice = devices.firstWhere(
      (d) => d.name.toLowerCase().contains('usb'),
      orElse: () => AudioDevice(
          id: '', name: '', type: AudioDeviceType.unknown, isInput: false, isOutput: false),
    );
    if (mounted) {
      setState(() {
        _isUsbMicConnected = usbDevice.id.isNotEmpty;
        _deviceStatusText = _isUsbMicConnected
            ? '${usbDevice.name} Connected'
            : 'Please connect the CardioScope receiver.';
      });
    }
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = themeNotifier.value == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        children: [
          _buildSectionHeader('Device Pairing', theme),
          _buildSettingsTile(
            icon: _isUsbMicConnected ? Icons.usb : Icons.usb_off,
            iconColor: _isUsbMicConnected ? Colors.green : Colors.grey,
            title: 'UAC Device Status',
            subtitle: _deviceStatusText,
          ),
          const Divider(),
          _buildSectionHeader('App Preferences', theme),
          _buildSettingsTile(
            icon: Icons.palette_outlined,
            title: 'Dark Theme',
            trailing: Switch(
              value: isDarkMode,
              onChanged: (value) async {
                themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
                final prefs = await SharedPreferences.getInstance();
                prefs.setBool('isDarkMode', value);
              },
            ),
          ),
          _buildSettingsTile(
            icon: Icons.language,
            title: 'Language',
            subtitle: _selectedLanguage,
            onTap: _showLanguageDialog,
          ),
          _buildSettingsTile(
            icon: Icons.sync_alt,
            title: 'Data Sync',
            trailing: Switch(
              value: _isDataSyncOn,
              onChanged: (value) => setState(() => _isDataSyncOn = value),
            ),
          ),
          const Divider(),
          _buildSectionHeader('Data & Storage', theme),
          _buildSettingsTile(
            icon: Icons.storage,
            title: 'Local Storage Used',
            subtitle: _storageUsed,
          ),
          _buildSettingsTile(
            icon: Icons.cloud_upload_outlined,
            title: 'Export All Data',
            onTap: () {},
          ),
          _buildSettingsTile(
            icon: Icons.delete_sweep_outlined,
            iconColor: const Color(0xFF023F40),
            title: 'Clear Cache',
            onTap: () => _showConfirmationDialog(
              context,
              title: 'Clear Cache',
              content: 'Are you sure you want to clear the app cache? This will not delete patient records.',
              confirmText: 'Clear',
              onConfirm: () {},
            ),
          ),
          const Divider(),
          _buildSectionHeader('About & Help', theme),
          _buildSettingsTile(
            icon: Icons.info_outline,
            title: 'Version',
            subtitle: _appVersion,
          ),
          _buildSettingsTile(
            icon: Icons.menu_book_outlined,
            title: 'Quick Start Guide',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const QuickStartGuidePage(),
              ));
            },
          ),
          _buildSettingsTile(
            icon: Icons.support_agent,
            title: 'FAQ & Support',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => const FaqPage(),
              ));
            },
          ),
          const Divider(),
          _buildSettingsTile(
            icon: Icons.logout,
            iconColor: const Color(0xFF023F40),
            title: 'Logout',
            onTap: () => _showConfirmationDialog(
              context,
              title: 'Confirm Logout',
              content: 'Are you sure you want to log out?',
              confirmText: 'Logout',
              onConfirm: () => _logoutAndGoToLogin(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select Language'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              setState(() => _selectedLanguage = 'English');
              Navigator.of(context).pop();
            },
            child: const Text('English'),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() => _selectedLanguage = 'Filipino');
              Navigator.of(context).pop();
            },
            child: const Text('Filipino'),
          ),
          SimpleDialogOption(
            onPressed: () {
              setState(() => _selectedLanguage = 'Cebuano');
              Navigator.of(context).pop();
            },
            child: const Text('Cebuano'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: theme.primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? Theme.of(context).iconTheme.color),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, color: Colors.grey) : null),
      onTap: onTap,
    );
  }

  void _showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String content,
    required String confirmText,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor:const Color(0xFF023F40)),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onConfirm();
            },
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  Future<void> _logoutAndGoToLogin(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('practitioner_id');
    await prefs.remove('practitioner_name');
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
    }
  }
}