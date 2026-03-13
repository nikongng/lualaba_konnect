import 'package:flutter/material.dart';
import 'package:lualaba_konnect/features/chat/presentation/pages/chat_list_page.dart';
import 'health_user_context.dart';

class HealthTeleconsultationPage extends StatelessWidget {
  final HealthUserContext contextRef;

  const HealthTeleconsultationPage({
    super.key,
    required this.contextRef,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teleconsultation')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La teleconsultation video est basee sur WebRTC (solution gratuite et fiable).',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              '1) Ouvrir une conversation\n'
              '2) Demarrer un appel video depuis le chat.',
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatListPage()));
              },
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Ouvrir les conversations'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChatListPage()));
              },
              icon: const Icon(Icons.videocam),
              label: const Text('Demarrer une consultation video'),
            ),
          ],
        ),
      ),
    );
  }
}
