import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FollowedCompaniesPage extends StatelessWidget {
  const FollowedCompaniesPage({super.key});

  Future<Map<String, dynamic>?> _getEnterprise(String uid) async {
    final snap = await FirebaseFirestore.instance.collection('enterprise_users').doc(uid).get();
    if (!snap.exists) return null;
    return snap.data();
  }

  String _nameFrom(Map<String, dynamic>? d, String fallback) {
    final raw = (d?['name'] ?? d?['displayName'] ?? d?['companyName'] ?? d?['firstName'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    return fallback.isNotEmpty ? fallback : 'Entreprise';
  }

  String _avatarFrom(Map<String, dynamic>? d) {
    return (d?['photoUrl'] ?? d?['avatarUrl'] ?? d?['logoUrl'] ?? d?['avatar'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    final divider = isDark ? Colors.white12 : Colors.black12;
    const accent = Color(0xFFFB8C00);

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Veuillez vous connecter.')));
    }

    final q = FirebaseFirestore.instance.collection('company_follows').where('followerUid', isEqualTo: user.uid);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        title: const Text('Entreprises suivies'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Erreur: ${snap.error}', style: TextStyle(color: sub)));
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return Center(child: Text('Aucune entreprise suivie.', style: TextStyle(color: sub, fontWeight: FontWeight.w700)));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final enterpriseUid = (d['enterpriseUid'] ?? '').toString().trim();
              if (enterpriseUid.isEmpty) return const SizedBox.shrink();

              return FutureBuilder<Map<String, dynamic>?>(
                future: _getEnterprise(enterpriseUid),
                builder: (context, enterpriseSnap) {
                  final enterprise = enterpriseSnap.data;
                  final name = _nameFrom(enterprise, enterpriseUid);
                  final avatar = _avatarFrom(enterprise);

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: divider),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.28 : 0.06), blurRadius: 18, offset: const Offset(0, 10))],
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 48,
                            height: 48,
                            color: isDark ? Colors.white10 : const Color(0xFFE9ECEF),
                            child: avatar.trim().isEmpty
                                ? Icon(Icons.apartment_rounded, color: isDark ? Colors.white54 : Colors.black38)
                                : CachedNetworkImage(imageUrl: avatar, fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text('ID: $enterpriseUid', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: sub, fontWeight: FontWeight.w700, fontSize: 12)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final ref = FirebaseFirestore.instance.collection('company_follows').doc('${user.uid}_$enterpriseUid');
                            await ref.delete();
                          },
                          style: TextButton.styleFrom(foregroundColor: accent),
                          child: const Text('Ne plus suivre', style: TextStyle(fontWeight: FontWeight.w900)),
                        ),
                      ],
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
}

