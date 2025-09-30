import 'package:flutter/material.dart';

class FaqPage extends StatelessWidget {
  const FaqPage({super.key}); 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FAQ & Support', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFC31C42),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      backgroundColor: Colors.white, 
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: const [ 
          FaqItem(
            question: 'What conditions can CardioScope detect?',
            answer: 'CardioScope is specifically designed to detect and classify Mitral Valve Diseases: Mitral Regurgitation (MR), Mitral Stenosis (MS), and Mitral Valve Prolapse (MVP), and distinguish them from Normal heart sounds.',
          ),
          FaqItem(
            question: 'Does the app require an internet connection?',
            answer: 'No. CardioScope works completely offline. All audio processing and AI analysis happens directly on your device to ensure privacy and functionality in remote areas.',
          ),
          FaqItem(
            question: 'Where is my data stored?',
            answer: 'All patient recordings and reports are stored locally and securely on your device\'s internal storage. No data is sent to the cloud unless you manually enable a backup feature.',
          ),
          FaqItem(
            question: 'How accurate is the AI detection?',
            answer: 'The deep learning model has been trained on a validated dataset to achieve high accuracy. However, CardioScope is a screening tool and is not a substitute for a formal diagnosis by a cardiologist. Results should always be clinically correlated.',
          ),
          FaqItem(
            question: 'How do I contact support?',
            answer: 'For technical assistance or questions, please contact our support team at support@cardioscope.ph.',
          ),
        ],
      ),
    );
  }
}

class FaqItem extends StatelessWidget {
  final String question;
  final String answer;

  const FaqItem({
    super.key,
    required this.question,
    required this.answer,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent, 
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: Theme.of(context).primaryColor,
          collapsedIconColor: Colors.grey,
          title: Text(
            question,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          children: [
            Text(
              answer,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
