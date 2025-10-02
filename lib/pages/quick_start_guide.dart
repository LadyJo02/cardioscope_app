import 'package:cardioscope_app/utils/app_colors.dart';
import 'package:flutter/material.dart'; 

class QuickStartGuidePage extends StatelessWidget {
  const QuickStartGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick Start Guide', style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildGuideStep(
            context,
            icon: Icons.usb,
            title: '1. Connect the Device',
            description: 'Plug the CardioScope USB-C receiver into your phone. The status light on the receiver will turn on.',
          ),
          _buildGuideStep(
            context,
            icon: Icons.place_outlined,
            title: '2. Place the Stethoscope',
            description: 'For best results, place the stethoscope chestpiece on the patient\'s chest at the 5th intercostal space, along the midclavicular line (the "Mitral Area"). Ensure good contact with the skin.',
          ),
          _buildGuideStep(
            context,
            icon: Icons.mic,
            title: '3. Start Recording',
            description: 'Tap the large microphone button at the bottom of the screen. You will see the real-time heart sound waveform. Record for at least 3-5 seconds.',
          ),
          _buildGuideStep(
            context,
            icon: Icons.analytics_outlined,
            title: '4. View the Analysis',
            description: 'After recording, the app will automatically analyze the sound and provide a classification (Normal, MR, MS, or MVP) along with a confidence score.',
          ),
          _buildGuideStep(
            context,
            icon: Icons.picture_as_pdf_outlined,
            title: '5. Manage Reports',
            description: 'All recordings are saved locally. You can view them in the "Results" tab and export them as PDF reports for documentation.',
          ),
        ],
      ),
    );
  }

  Widget _buildGuideStep(BuildContext context, {required IconData icon, required String title, required String description}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).primaryColor, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(description, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}