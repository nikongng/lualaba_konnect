
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ===============================
/// PAGE : LISTE DES CONVERSATIONS
/// ===============================
class MarketMessagesPage extends StatelessWidget {
  const MarketMessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Connectez-vous')),
      );
    }

    final q = FirebaseFirestore.instance
        .collection('market_messages')
        .where('participants', arrayContains: uid)
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Messages (Market)')),
      body: StreamBuilder<QuerySnapshot>(
        stream: q.snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            );
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('Aucun message'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final d = docs[index];
              final data = d.data() as Map<String, dynamic>;

              final Timestamp? createdAt =
                  data['createdAt'] as Timestamp?;

              final participants =
                  (data['participants'] as List?)?.cast<String>() ?? [];

              final String otherUserId = participants.firstWhere(
                (e) => e != uid,
                orElse: () => data['to'] ?? '',
              );

              final bool isUnread =
                  data['to'] == uid && data['read'] != true;

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.shade100,
                  child: const Icon(Icons.message, color: Colors.orange),
                ),
                title: Text(data['productName'] ?? 'Produit'),
                subtitle: Text(
                  data['content'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(_formatTime(createdAt)),
                onTap: () async {
                  if (isUnread) {
                    await d.reference.update({'read': true});
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatThreadPage(
                        productId: data['productId'] ?? '',
                        productName: data['productName'] ?? '',
                        otherUserId: otherUserId,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  static String _formatTime(Timestamp? ts) {
    if (ts == null) return '...';
    final dt = ts.toDate();
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}

/// ===============================
/// PAGE : THREAD DE DISCUSSION
/// ===============================
class ChatThreadPage extends StatefulWidget {
  final String productId;
  final String productName;
  final String otherUserId;

  const ChatThreadPage({
    super.key,
    required this.productId,
    required this.productName,
    required this.otherUserId,
  });

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final TextEditingController _ctrl = TextEditingController();

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final msg = {
      'productId': widget.productId,
      'productName': widget.productName,
      'content': text,
      'from': uid,
      'to': widget.otherUserId,
      'participants': [uid, widget.otherUserId],
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': Timestamp.now(), // fallback UX
    };

    _ctrl.clear();
    await FirebaseFirestore.instance
        .collection('market_messages')
        .add(msg);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final q = FirebaseFirestore.instance
        .collection('market_messages')
        .where('productId', isEqualTo: widget.productId)
        .where('participants', arrayContains: uid)
        .orderBy('createdAt', descending: false);

    return Scaffold(
      appBar: AppBar(title: Text(widget.productName)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: q.snapshots(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final docs = snap.data?.docs ?? [];

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data() as Map<String, dynamic>;

                    final bool isMe = data['from'] == uid;

                    final Timestamp? createdAt =
                        (data['createdAt'] ??
                                data['createdAtLocal'])
                            as Timestamp?;

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.orange.shade100
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(data['content'] ?? ''),
                            const SizedBox(height: 4),
                            Text(
                              _formatTime(createdAt),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration:
                        const InputDecoration(hintText: 'Message...'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.orange),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(Timestamp? ts) {
    if (ts == null) return '...';
    final dt = ts.toDate();
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
