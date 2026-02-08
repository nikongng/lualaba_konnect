import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:timeago/src/messages/fr_messages.dart';

import 'package:lualaba_konnect/features/auth/presentation/pages/news_feed_page.dart';
import 'package:lualaba_konnect/features/services/presentation/pages/mobility_services_page.dart';
import 'package:lualaba_konnect/features/services/presentation/pages/jobs_page.dart';
import 'package:lualaba_konnect/features/services/presentation/pages/my_job_applications_page.dart';
import 'package:lualaba_konnect/features/services/presentation/pages/enterprise_jobs_admin_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String _filter = 'all';
  final Map<String, Future<Map<String, dynamic>?>> _profileFutures = {};

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('fr', FrMessages());
  }

  String _firstName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Utilisateur';
    final parts = n.split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.first : n;
  }

  DateTime? _dateFrom(Map<String, dynamic> data) {
    final ts = data['createdAt'];
    if (ts is Timestamp) return ts.toDate();
    final m = data['createdAtMs'];
    if (m is int) return DateTime.fromMillisecondsSinceEpoch(m);
    if (m is num) return DateTime.fromMillisecondsSinceEpoch(m.toInt());
    return null;
  }

  String _formatWhen(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 7) {
      String two(int v) => v < 10 ? '0$v' : '$v';
      return '${two(dt.day)}/${two(dt.month)}/${dt.year}';
    }
    return timeago.format(dt, locale: 'fr');
  }

  Future<Map<String, dynamic>?> _fetchUserDocAny(String uid) async {
    const cols = ['enterprise_users', 'pro_users', 'classic_users', 'users'];
    for (final c in cols) {
      final snap = await FirebaseFirestore.instance.collection(c).doc(uid).get();
      if (snap.exists) return snap.data();
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getProfileAny(String uid) {
    return _profileFutures.putIfAbsent(uid, () => _fetchUserDocAny(uid));
  }

  Future<void> _setNotificationsDisabled(String myUid, bool disabled) async {
    await FirebaseFirestore.instance.collection('notification_settings').doc(myUid).set(
      {
        'disabled': disabled,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      },
      SetOptions(merge: true),
    );
  }

  void _openNotifMenu({
    required String myUid,
    required DocumentReference docRef,
    required Color bg,
    required Color text,
    required Color sub,
    required Color card,
    required bool isDark,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.5 : 0.12), blurRadius: 24, offset: const Offset(0, 12))],
              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white24 : Colors.black12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: Text('Supprimer la notification', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
                  subtitle: Text('Retire cette notification de la liste.', style: TextStyle(color: sub)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await docRef.delete();
                  },
                ),
                Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
                ListTile(
                  leading: Icon(Icons.notifications_off_outlined, color: sub),
                  title: Text('Désactiver les notifications', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
                  subtitle: Text('Vous ne recevrez plus de notifications.', style: TextStyle(color: sub)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _setNotificationsDisabled(myUid, true);
                    if (!mounted) return;
                    showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: bg,
                        title: Text('Notifications désactivées', style: TextStyle(color: text)),
                        content: Text('Vous pouvez les réactiver plus tard.', style: TextStyle(color: sub)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('OK', style: TextStyle(color: text)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _pickAvatarFromProfile(Map<String, dynamic>? d) {
    if (d == null) return '';
    return (d['photoUrl'] ?? d['photo'] ?? d['avatar'] ?? d['profilePhoto'] ?? '').toString();
  }

  String _pickNameFromProfile(Map<String, dynamic>? d, String fallback) {
    final raw = (d?['firstName'] ?? d?['prenom'] ?? d?['displayName'] ?? d?['name'] ?? '').toString().trim();
    if (raw.isNotEmpty) return raw;
    return fallback.trim().isNotEmpty ? fallback : 'Utilisateur';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Veuillez vous connecter.')));
    }

    Query query = FirebaseFirestore.instance.collection('notifications').where('toUserId', isEqualTo: user.uid);
    if (_filter == 'mention') query = query.where('type', isEqualTo: 'mention');

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B141A) : const Color(0xFFF6F7F9);
    final card = isDark ? const Color(0xFF111B21) : Colors.white;
    final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
    final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
    const accent = Color(0xFFFB8C00);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Tout'),
                  selected: _filter == 'all',
                  selectedColor: accent.withOpacity(isDark ? 0.35 : 0.18),
                  backgroundColor: card,
                  side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                  labelStyle: TextStyle(color: _filter == 'all' ? text : sub, fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Mentions'),
                  selected: _filter == 'mention',
                  selectedColor: accent.withOpacity(isDark ? 0.35 : 0.18),
                  backgroundColor: card,
                  side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                  labelStyle: TextStyle(color: _filter == 'mention' ? text : sub, fontWeight: FontWeight.w600),
                  onSelected: (_) => setState(() => _filter = 'mention'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: query.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Erreur de chargement des notifications.\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: sub),
                    ),
                  );
                }

                final docs = (snap.data?.docs ?? const <QueryDocumentSnapshot>[]).toList()
                  ..sort((a, b) {
                    int ms(QueryDocumentSnapshot d) {
                      final data = d.data() as Map<String, dynamic>? ?? const {};
                      final ts = data['createdAt'];
                      if (ts is Timestamp) return ts.millisecondsSinceEpoch;
                      final m = data['createdAtMs'];
                      if (m is int) return m;
                      if (m is num) return m.toInt();
                      return 0;
                    }

                    return ms(b).compareTo(ms(a));
                  });

                if (docs.isEmpty) {
                  return Center(
                    child: Text('Aucune notification', style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (c, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final type = (data['type'] ?? '').toString();
                    final fromUserId = (data['fromUserId'] ?? '').toString();
                    final fromFallback = (data['fromName'] ?? 'Utilisateur').toString();
                    final fromAvatar = (data['fromAvatar'] ?? '').toString();
                    final textRaw = (data['text'] ?? '').toString();
                    final seen = data['seen'] == true;
                    final when = _formatWhen(_dateFrom(data));

                    String body;
                    IconData typeIcon;
                    Color typeColor;
                    if (type == 'mention') {
                      body = 'vous a mentionné: $textRaw';
                      typeIcon = Icons.alternate_email_rounded;
                      typeColor = const Color(0xFF64B5F6);
                    } else if (type == 'comment') {
                      body = 'a commenté: $textRaw';
                      typeIcon = Icons.mode_comment_outlined;
                      typeColor = const Color(0xFF00CBA9);
                    } else if (type == 'job_application') {
                      body = textRaw.isNotEmpty ? textRaw : 'Nouvelle candidature';
                      typeIcon = Icons.assignment_ind_outlined;
                      typeColor = const Color(0xFF00CBA9);
                    } else if (type == 'job_application_update') {
                      body = textRaw.isNotEmpty ? textRaw : 'Reponse recruteur';
                      typeIcon = Icons.mark_email_read_outlined;
                      typeColor = const Color(0xFFFB8C00);
                    } else if (type == 'new_job_offer') {
                      body = textRaw.isNotEmpty ? textRaw : 'Nouvelle offre';
                      typeIcon = Icons.business_center_outlined;
                      typeColor = const Color(0xFF64B5F6);
                    } else {
                      body = textRaw;
                      typeIcon = Icons.notifications_none;
                      typeColor = accent;
                    }

                    Widget tile = FutureBuilder<Map<String, dynamic>?>(
                      future: fromAvatar.isNotEmpty || fromUserId.isEmpty ? null : _getProfileAny(fromUserId),
                      builder: (context, profSnap) {
                        final prof = profSnap.data;
                        final avatar = fromAvatar.isNotEmpty ? fromAvatar : _pickAvatarFromProfile(prof);
                        final name = _firstName(_pickNameFromProfile(prof, fromFallback));
                        return _NotificationCard(
                          cardColor: card,
                          textColor: text,
                          subTextColor: sub,
                          accent: accent,
                          seen: seen,
                          avatarUrl: avatar,
                          name: name,
                          body: body,
                          when: when,
                          typeIcon: typeIcon,
                          typeColor: typeColor,
                          onTap: () async {
                            await doc.reference.update({'seen': true});
                            if (!context.mounted) return;

                            // Services: Emploi & Annonces
                            if (type == 'job_application_update') {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const MyJobApplicationsPage()));
                              return;
                            }
                            if (type == 'job_application') {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => EnterpriseJobsAdminPage(enterpriseUid: user.uid)));
                              return;
                            }
                            if (type == 'new_job_offer') {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const JobsPage()));
                              return;
                            }

                            if (type == 'car_booking') {
                              final rentalName = (data['rentalName'] ?? '').toString().trim();
                              final msg = (data['message'] ?? '').toString().trim();
                              DateTime? start;
                              DateTime? end;
                              final s = data['startDate'];
                              final e = data['endDate'];
                              if (s is Timestamp) start = s.toDate();
                              if (e is Timestamp) end = e.toDate();
                              String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
                              final whenText = (start != null && end != null) ? '${fmt(start)} → ${fmt(end)}' : '';

                              await showDialog<void>(
                                context: context,
                                builder: (ctx) {
                                  final isDark = Theme.of(ctx).brightness == Brightness.dark;
                                  final bg = isDark ? const Color(0xFF111B21) : Colors.white;
                                  final text = isDark ? const Color(0xFFE9EDF0) : const Color(0xFF111827);
                                  final sub = isDark ? const Color(0xFFAAB2B8) : const Color(0xFF6B7280);
                                  return AlertDialog(
                                    backgroundColor: bg,
                                    title: Text('Demande de reservation', style: TextStyle(color: text, fontWeight: FontWeight.w900)),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (rentalName.isNotEmpty) Text(rentalName, style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                                        if (whenText.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(whenText, style: TextStyle(color: sub, fontWeight: FontWeight.w700))),
                                        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(msg, style: TextStyle(color: sub, fontWeight: FontWeight.w600))),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('Fermer'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          Navigator.push(context, MaterialPageRoute(builder: (_) => const MobilityServicesPage()));
                                        },
                                        child: const Text('Ouvrir Mobilite'),
                                      ),
                                    ],
                                  );
                                },
                              );
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NewsFeedPage(
                                  initialPostId: data['postId']?.toString(),
                                  initialCommentId: data['commentId']?.toString(),
                                  initialReplyId: data['replyId']?.toString(),
                                ),
                              ),
                            );
                          },
                          onMore: () => _openNotifMenu(
                            myUid: user.uid,
                            docRef: doc.reference,
                            bg: bg,
                            text: text,
                            sub: sub,
                            card: card,
                            isDark: isDark,
                          ),
                        );
                      },
                    );

                    tile = TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: Duration(milliseconds: 420 + (i.clamp(0, 10) * 35)),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) {
                        return Opacity(
                          opacity: v,
                          child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
                        );
                      },
                      child: tile,
                    );

                    return Padding(
                      padding: EdgeInsets.fromLTRB(16, i == 0 ? 8 : 6, 16, i == docs.length - 1 ? 16 : 6),
                      child: tile,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.cardColor,
    required this.textColor,
    required this.subTextColor,
    required this.accent,
    required this.seen,
    required this.avatarUrl,
    required this.name,
    required this.body,
    required this.when,
    required this.typeIcon,
    required this.typeColor,
    required this.onTap,
    required this.onMore,
  });

  final Color cardColor;
  final Color textColor;
  final Color subTextColor;
  final Color accent;
  final bool seen;
  final String avatarUrl;
  final String name;
  final String body;
  final String when;
  final IconData typeIcon;
  final Color typeColor;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = seen ? (isDark ? Colors.white10 : Colors.black12) : accent.withOpacity(0.55);
    final bg = seen ? cardColor : (isDark ? const Color(0xFF152027) : const Color(0xFFFFF7F0));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.30 : 0.06),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty ? Icon(Icons.person, color: subTextColor) : null,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: typeColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: bg, width: 2),
                        boxShadow: [BoxShadow(color: typeColor.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Icon(typeIcon, size: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w800, color: textColor, fontSize: 14.5, letterSpacing: -0.2),
                          ),
                        ),
                        if (when.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          Text(when, style: TextStyle(color: subTextColor.withOpacity(0.85), fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                        if (!seen) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(99),
                              boxShadow: [BoxShadow(color: accent.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))],
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        InkResponse(
                          onTap: onMore,
                          radius: 20,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.more_vert, size: 18, color: subTextColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: subTextColor, fontWeight: FontWeight.w600, height: 1.25),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
