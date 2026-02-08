
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:lualaba_konnect/core/config.dart';

/// ===============================
/// PAGE : LISTE DES CONVERSATIONS
/// ===============================
class MarketMessagesPage extends StatelessWidget {
  const MarketMessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bg = isDark ? const Color(0xFF0F1214) : Colors.white;
    final Color text = isDark ? Colors.white : Colors.black87;
    final Color sub = isDark ? Colors.white70 : Colors.black54;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Connectez-vous')),
      );
    }

    final q = FirebaseFirestore.instance
      .collection('market_messages')
      .where('participants', arrayContains: uid)
      // Order by client-side timestamp to avoid flicker when serverTimestamp is applied
      .orderBy('createdAtLocal', descending: true);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Messages (Market)', style: TextStyle(color: text)),
        backgroundColor: isDark ? const Color(0xFF14181C) : Colors.white,
        iconTheme: IconThemeData(color: text),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: q.snapshots(),
        builder: (ctx, snap) {
          if (snap.hasError) {
            // First: try network query without orderBy and sort client-side
            return FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('market_messages')
                  .where('participants', arrayContains: uid)
                  .get(),
              builder: (c, netSnap) {
                if (netSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (netSnap.hasData && (netSnap.data?.docs.isNotEmpty ?? false)) {
                  final docs = List<QueryDocumentSnapshot>.from(netSnap.data!.docs);
                  docs.sort((a, b) {
                    final ai = _tsMillisFromData(a.data() as Map<String, dynamic>);
                    final bi = _tsMillisFromData(b.data() as Map<String, dynamic>);
                    return bi.compareTo(ai); // descending
                  });
                  return _buildConversationList(context, docs, uid);
                }
                // Network fallback failed — try cache
                return FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('market_messages')
                      .where('participants', arrayContains: uid)
                      .get(const GetOptions(source: Source.cache)),
                  builder: (cc, cacheSnap) {
                    if (cacheSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = cacheSnap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(child: Text('Erreur: ${snap.error}'));
                    }
                    final sorted = List<QueryDocumentSnapshot>.from(docs);
                    sorted.sort((a, b) {
                      final ai = _tsMillisFromData(a.data() as Map<String, dynamic>);
                      final bi = _tsMillisFromData(b.data() as Map<String, dynamic>);
                      return bi.compareTo(ai);
                    });
                    return _buildConversationList(context, sorted, uid);
                  },
                );
              },
            );
          }

          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            );
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(child: Text('Aucun message', style: TextStyle(color: sub)));
          }

          return _buildConversationList(context, docs, uid);
        },
      ),
    );
  }

  static Widget _buildThreadList(List<QueryDocumentSnapshot> docs, String? uid) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final d = docs[i];
        final data = d.data() as Map<String, dynamic>;

        final bool isMe = data['from'] == uid;
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        final Color meBg = isDark ? Colors.orange.withOpacity(0.25) : Colors.orange.shade100;
        final Color otherBg = isDark ? Colors.white10 : Colors.grey.shade200;

        final Timestamp? createdAt =
            (data['createdAt'] ?? data['createdAtLocal']) as Timestamp?;

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMe ? meBg : otherBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(data['content'] ?? ''),
                const SizedBox(height: 4),
                Text(
                  _formatTime(createdAt),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper to extract sortable timestamp from a document's data
  static int _tsMillisFromData(Map<String, dynamic> data) {
    try {
      final dynamic ts = data['createdAtLocal'] ?? data['createdAt'];
      if (ts == null) return 0;
      if (ts is Timestamp) return ts.toDate().millisecondsSinceEpoch;
      if (ts is int) return ts; // milliseconds
      if (ts is String) return DateTime.parse(ts).millisecondsSinceEpoch;
      if (ts is Map) {
        final s = ts['_seconds'];
        if (s is int) return s * 1000;
      }
    } catch (_) {}
    return 0;
  }

  Widget _buildConversationList(BuildContext context, List<QueryDocumentSnapshot> docs, String uid) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color text = isDark ? Colors.white : Colors.black87;
    final Color sub = isDark ? Colors.white70 : Colors.black54;
    return ListView.builder(
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final d = docs[index];
        final data = d.data() as Map<String, dynamic>;

        final Timestamp? createdAt = (data['createdAt'] ?? data['createdAtLocal']) as Timestamp?;

        final participants = (data['participants'] as List?)?.cast<String>() ?? [];

        final String otherUserId = participants.firstWhere(
          (e) => e != uid,
          orElse: () => data['to'] ?? '',
        );

        final bool isUnread = data['to'] == uid && data['read'] != true;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isDark ? Colors.orange.withOpacity(0.2) : Colors.orange.shade100,
            child: const Icon(Icons.message, color: Colors.orange),
          ),
          title: Text(data['productName'] ?? 'Produit', style: TextStyle(color: text)),
          subtitle: Text(
            data['content'] ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: sub),
          ),
          trailing: Text(_formatTime(createdAt), style: TextStyle(color: sub)),
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

  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final msg = {
    'productId': widget.productId,
    'productName': widget.productName,
    'content': text,
    'from': user.uid,
    'to': widget.otherUserId,
    'participants': [user.uid, widget.otherUserId],
    'read': false,
    'createdAt': FieldValue.serverTimestamp(),
    'createdAtLocal': Timestamp.now(),
  };

  _ctrl.clear();
  
  try {
    // 1. Sauvegarde dans Firestore
    await FirebaseFirestore.instance.collection('market_messages').add(msg);

    // 2. Envoi de la notification via ton serveur Render
    final idToken = await user.getIdToken();
    final url = Uri.parse(kNotifierUrl);
        await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'recipients': [widget.otherUserId],
        'title': 'Market: ${widget.productName}', // Titre explicite
        'body': text,
        'senderAvatarUrl': user.photoURL ?? '',
        'data': { 
          'productId': widget.productId,
          'type': 'market_message' 
        }
      }),
    );
  } catch (e) {
    debugPrint("Erreur envoi message Market: $e");
  }
}

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final q = FirebaseFirestore.instance
      .collection('market_messages')
      .where('productId', isEqualTo: widget.productId)
      .where('participants', arrayContains: uid)
      // Use local timestamp for stable ordering on client
      .orderBy('createdAtLocal', descending: false);

    final double kb = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(title: Text(widget.productName)),
      body: Column(
        children: [
          // Petite indication de l'annonce concernée
          Container(
            width: double.infinity,
            color: Colors.orange.shade50,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.campaign, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Annonce: ${widget.productName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  'ID ${widget.productId}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: q.snapshots(),
              builder: (ctx, snap) {
                if (snap.hasError) {
                  // Try network get without orderBy and sort client-side
                  return FutureBuilder<QuerySnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('market_messages')
                        .where('productId', isEqualTo: widget.productId)
                        .where('participants', arrayContains: uid)
                        .get(),
                    builder: (nc, netSnap) {
                      if (netSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (netSnap.hasData && (netSnap.data?.docs.isNotEmpty ?? false)) {
                        final docs = List<QueryDocumentSnapshot>.from(netSnap.data!.docs);
                        docs.sort((a, b) {
                          final ai = MarketMessagesPage._tsMillisFromData(a.data() as Map<String, dynamic>);
                          final bi = MarketMessagesPage._tsMillisFromData(b.data() as Map<String, dynamic>);
                          return ai.compareTo(bi); // ascending
                        });
                        return MarketMessagesPage._buildThreadList(docs, uid);
                      }
                      // fallback to cache
                      return FutureBuilder<QuerySnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('market_messages')
                            .where('productId', isEqualTo: widget.productId)
                            .where('participants', arrayContains: uid)
                            .get(const GetOptions(source: Source.cache)),
                        builder: (cc, cacheSnap) {
                          if (cacheSnap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final docs = cacheSnap.data?.docs ?? [];
                          final sorted = List<QueryDocumentSnapshot>.from(docs);
                          sorted.sort((a, b) {
                            final ai = MarketMessagesPage._tsMillisFromData(a.data() as Map<String, dynamic>);
                            final bi = MarketMessagesPage._tsMillisFromData(b.data() as Map<String, dynamic>);
                            return ai.compareTo(bi);
                          });
                          return MarketMessagesPage._buildThreadList(sorted, uid);
                        },
                      );
                    },
                  );
                }

                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final docs = snap.data?.docs ?? [];

                return MarketMessagesPage._buildThreadList(docs, uid);
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: kb > 0 ? kb : 6.0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8.0,2.0,8.0,2.0),
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
