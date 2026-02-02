// 📄 lib/pages/settings.dart
import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:cardioscope_app/services/storage_service.dart';
import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'faq_page.dart';
import 'login.dart';
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
    _loadSavedLanguage();
    _initAudioSession();
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('app_language') ?? 'English';
    setState(() => _selectedLanguage = lang);
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      _devicesSubscription = session.devicesStream.listen((devices) {
        _checkConnectedDevices(devices.toList());
      });
      final current = await session.getDevices();
      _checkConnectedDevices(current.toList());
    } catch (_) {}
  }

  void _checkConnectedDevices(List<AudioDevice> devices) {
    final usbDevice = devices.firstWhere(
      (d) => d.isInput && (
          d.name.toLowerCase().contains('usb') ||
          d.name.toLowerCase().contains('external') ||
          d.name.toLowerCase().contains('headset')
      ),
      orElse: () => AudioDevice(
        id: '',
        name: '',
        type: AudioDeviceType.unknown,
        isInput: false,
        isOutput: false,
      ),
    );

    if (!mounted) return;
    final wasConnected = _isUsbMicConnected;

    setState(() {
      _isUsbMicConnected = usbDevice.id.isNotEmpty;
      _deviceStatusText = _isUsbMicConnected
          ? '${usbDevice.name} Connected'
          : 'Please connect the CardioScope receiver.';
    });

    if (_isUsbMicConnected != wasConnected && mounted) {
      _toast(
        _isUsbMicConnected
            ? "CardioScope receiver connected."
            : "CardioScope receiver disconnected.",
        isError: !_isUsbMicConnected,
      );
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
    final cardColor = theme.cardColor;
    final dividerColor = theme.dividerColor;
    final textColor = theme.textTheme.bodyMedium?.color;
    final isDarkMode = widget.themeNotifier.value == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        color: theme.scaffoldBackgroundColor,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          children: [
            _settingsSection(
              title: "Device Pairing",
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _buildTile(
                  icon: Icons.usb_rounded,
                  iconColor:
                      _isUsbMicConnected ? AppColors.success : AppColors.warning,
                  title: "CardioScope Receiver",
                  subtitle: _deviceStatusText,
                  textColor: textColor,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isUsbMicConnected
                            ? Icons.circle
                            : Icons.circle_outlined,
                        color:
                            _isUsbMicConnected ? AppColors.success : Colors.grey,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isUsbMicConnected ? 'Online' : 'Offline',
                        style: TextStyle(
                          color:
                              _isUsbMicConnected ? AppColors.success : Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // App Preferences
            _settingsSection(
              title: "App Preferences",
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _buildTile(
                  icon: Icons.palette_outlined,
                  title: "Dark Theme",
                  textColor: textColor,
                  trailing: Switch(
                    value: isDarkMode,
                    onChanged: _toggleTheme,
                  ),
                ),
                _buildTile(
                  icon: Icons.language,
                  title: "Language",
                  subtitle: "$_selectedLanguage (English only for now)",
                  textColor: textColor,
                  onTap: _showLanguageDialog,
                ),
                _buildTile(
                  icon: Icons.sync_alt,
                  title: 'Data Sync',
                  textColor: textColor,
                  trailing: Switch(
                    value: _isDataSyncOn,
                    onChanged: (v) => setState(() => _isDataSyncOn = v),
                  ),
                ),
              ],
            ),

            // Data & Storage
            _settingsSection(
              title: "Data & Storage",
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _buildTile(
                  icon: Icons.storage,
                  title: 'Local Storage Used',
                  subtitle: _storageUsed,
                  textColor: textColor,
                ),
                _buildTile(
                  icon: Icons.sync,
                  title: 'Rescan Local Storage',
                  subtitle: 'Rebuild missing patient data from files',
                  textColor: textColor,
                  onTap: _rescanStorage,
                ),
                _buildTile(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Export All Data',
                  textColor: textColor,
                  onTap: () => _toast("Export feature coming soon."),
                ),
                _buildTile(
                  icon: Icons.delete_sweep_outlined,
                  iconColor: AppColors.accent,
                  title: 'Clear Cache',
                  textColor: textColor,
                  onTap: _clearCache,
                ),
              ],
            ),

            // Help
            _settingsSection(
              title: "About & Help",
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _buildTile(
                  icon: Icons.info_outline,
                  title: 'Version',
                  subtitle: _appVersion,
                  textColor: textColor,
                ),
                _buildTile(
                  icon: Icons.menu_book_outlined,
                  title: 'Quick Start Guide',
                  textColor: textColor,
                  onTap: () => _goTo(const QuickStartGuidePage()),
                ),
                _buildTile(
                  icon: Icons.support_agent,
                  title: 'FAQ & Support',
                  textColor: textColor,
                  onTap: () => _goTo(const FaqPage()),
                ),
              ],
            ),

            _settingsSection(
              title: "",
              cardColor: cardColor,
              dividerColor: dividerColor,
              children: [
                _buildTile(
                  icon: Icons.logout,
                  iconColor: AppColors.accent,
                  title: 'Logout',
                  textColor: textColor,
                  onTap: _showLogoutConfirm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================= UI Helpers =================

  Widget _settingsSection({
    required String title,
    required List<Widget> children,
    required Color cardColor,
    required Color dividerColor,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.brightness == Brightness.dark
                    ? Colors.white70
                    : Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: cardColor,
              child: Column(
                children: List.generate(
                  children.length,
                  (i) => Column(
                    children: [
                      children[i],
                      if (i < children.length - 1)
                        Divider(height: 1, color: dividerColor, thickness: 0.6),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
    required Color? textColor,
  }) {
    final theme = Theme.of(context);

    return ListTile(
      tileColor: theme.cardColor,
      leading: Icon(icon, color: iconColor ?? theme.iconTheme.color),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w500, color: textColor),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: textColor?.withValues(alpha: 0.75)),
            )
          : null,
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right, color: theme.iconTheme.color)
              : null),
      onTap: onTap,
    );
  }

  // ================= Logic =================

  Future<void> _toggleTheme(bool value) async {
    widget.themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
    _toast("Theme updated.");
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.warning : AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

// ✅ Correct rescan function (place between _toast() and _clearCache())
Future<void> _rescanStorage() async {
  _toast("Scanning local storage…");

  // show a blocking spinner while rebuilding
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString("practitioner_email") ?? '';
    final id = prefs.getInt("practitioner_id") ?? 0;

    await StorageService().rebuildDatabaseFromExistingFiles(
      practitionerEmail: email,
      practitionerId: id,
    );

    if (!mounted) return;
    Navigator.pop(context); // close spinner
    _toast("Local storage scan completed.");
  } catch (e) {
    if (mounted) {
      Navigator.pop(context);
      _toast("Scan failed: $e", isError: true);
    }
  }
}

  void _clearCache() {
    _toast("Cache cleared.");
  }

  void _goTo(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _showLogoutConfirm() {
    _showDialog(
      title: 'Confirm Logout',
      content: 'Are you sure you want to log out?',
      confirm: 'Logout',
      onConfirm: _logout,
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('practitioner_id');
    await prefs.remove('practitioner_name');
    await prefs.remove('practitioner_email');
    await prefs.remove('storagePath');
    await prefs.remove('hasSeenOnboarding');

    await StorageService().clearCurrentPatient();

    // ✅ Reset for fresh restore prompt next time
    RestorePromptBridge.reset();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

void _showDialog({
  required String title,
  required String content,
  required String confirm,
  required VoidCallback onConfirm,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
      content: Text(
        content,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            "Cancel",
            style: TextStyle(
              color: isDark
                  ? Colors.white70
                  : AppColors.primary.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          onPressed: () {
            Navigator.pop(context);
            onConfirm();
          },
          child: Text(
            confirm,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

  // ================= Language Dialog =================

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Select Language"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _languageOption("English"),
            _languageOption("Filipino (coming soon)"),
            _languageOption("Cebuano (coming soon)"),
          ],
        ),
      ),
    );
  }

  Widget _languageOption(String lang) {
    return ListTile(
      title: Text(lang),
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        if (lang.startsWith("English")) {
          await prefs.setString('app_language', "English");
          setState(() => _selectedLanguage = "English");
          _toast("Language set to English.");
        } else {
          _toast("Only English is available at the moment.");
        }
        if (!mounted) return;
        Navigator.pop(context);
      },
    );
  }
}
