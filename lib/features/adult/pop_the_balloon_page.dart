import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lualaba_konnect/core/supabase_service.dart';

class PopTheBalloonPage extends StatefulWidget {
  const PopTheBalloonPage({super.key});

  @override
  State<PopTheBalloonPage> createState() => _PopTheBalloonPageState();
}

class _PopTheBalloonPageState extends State<PopTheBalloonPage> with SingleTickerProviderStateMixin {
  static const int _maxVoiceSeconds = 20;
  static const String _adultChatCollection = 'adult_pop_chats';
  final AudioPlayer _popPlayer = AudioPlayer();
  final AudioPlayer _voicePlayer = AudioPlayer();
  final FlutterSoundRecorder _voiceRecorder = FlutterSoundRecorder();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _displayNameCtrl = TextEditingController();
  final TextEditingController _jobCtrl = TextEditingController();
  final TextEditingController _hobbyCtrl = TextEditingController();
  final TextEditingController _ageCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _preferencesCtrl = TextEditingController();
  final TextEditingController _skinToneOtherCtrl = TextEditingController();
  final List<_BalloonCandidate> _pool = [];
  final List<_BalloonCandidate> _kept = [];
  _BalloonCandidate? _finalChoice;
  bool _loading = true;
  bool _profileChecking = true;
  bool _profileGate = false;
  bool _editingProfile = false;
  bool _savingProfile = false;
  bool _photoPicking = false;
  bool _voiceBusy = false;
  bool _voicePlaying = false;
  bool _isRecordingVoice = false;
  String? _loadError;
  String? _profileError;
  int _poppedCount = 0;
  final int _episodeSize = 10;
  DocumentReference<Map<String, dynamic>>? _userRef;
  String _gender = 'Homme';
  String _skinTone = 'Moyen';
  bool _skinToneOther = false;
  Uint8List? _adultPhotoBytes;
  String? _adultPhotoUrl;
  bool _adultPhotoChanged = false;
  Uint8List? _voiceIntroBytes;
  String? _voiceIntroUrl;
  String? _voiceIntroName;
  String _voiceIntroExt = 'm4a';
  bool _voiceIntroChanged = false;
  StreamSubscription<void>? _voiceDoneSub;
  StreamController<Uint8List>? _voiceStreamController;
  StreamSubscription<Uint8List>? _voiceStreamSub;
  final List<int> _voiceStreamBuffer = <int>[];
  Timer? _voiceTimer;
  int _voiceSeconds = 0;
  bool _voiceRecorderReady = false;
  String _currentRecordingExt = 'm4a';
  bool _recordingToStream = false;
  late final AnimationController _balloonMotionCtrl;

  @override
  void initState() {
    super.initState();
    _balloonMotionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _voiceDoneSub = _voicePlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _voicePlaying = false);
    });
    _initVoiceRecorder();
    _bootstrap();
  }

  @override
  void dispose() {
    _balloonMotionCtrl.dispose();
    _voiceTimer?.cancel();
    _voiceDoneSub?.cancel();
    _voiceStreamSub?.cancel();
    unawaited(_disposeVoiceStreamCapture());
    _popPlayer.dispose();
    _voicePlayer.dispose();
    unawaited(_voiceRecorder.closeRecorder());
    _displayNameCtrl.dispose();
    _jobCtrl.dispose();
    _hobbyCtrl.dispose();
    _ageCtrl.dispose();
    _addressCtrl.dispose();
    _preferencesCtrl.dispose();
    _skinToneOtherCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _profileChecking = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _profileGate = true;
      _profileError = 'Connectez-vous pour participer.';
      if (mounted) setState(() => _profileChecking = false);
      return;
    }
    final doc = await _fetchUserDoc(user.uid);
    if (doc == null) {
      _profileGate = true;
      _profileError = 'Profil introuvable.';
      if (mounted) setState(() => _profileChecking = false);
      return;
    }
    _userRef = doc.ref;
    _hydrateAdultProfile(doc.data);
    _profileGate = !_isAdultProfileComplete(doc.data);
    if (mounted) setState(() => _profileChecking = false);
    if (!_profileGate) {
      await _loadCandidates();
    }
  }

  Future<_UserDoc?> _fetchUserDoc(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final preferred = (prefs.getString('user_collection') ?? '').trim();
    final cols = <String>{
      if (preferred.isNotEmpty) preferred,
      'classic_users',
      'pro_users',
      'enterprise_users',
      'users',
    }.toList();

    for (final col in cols) {
      try {
        final snap = await FirebaseFirestore.instance.collection(col).doc(uid).get();
        if (!snap.exists) continue;
        return _UserDoc(snap.reference, snap.data() ?? <String, dynamic>{});
      } catch (_) {}
    }
    return null;
  }

  Future<void> _openEditProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await _fetchUserDoc(user.uid);
    if (doc == null) {
      if (mounted) {
        setState(() {
          _profileError = 'Profil introuvable.';
        });
      }
      return;
    }
    _userRef = doc.ref;
    _hydrateAdultProfile(doc.data);
    if (mounted) {
      setState(() {
        _profileError = null;
        _editingProfile = true;
      });
    }
  }

  void _hydrateAdultProfile(Map<String, dynamic> data) {
    final adult = (data['adultProfile'] is Map) ? Map<String, dynamic>.from(data['adultProfile']) : <String, dynamic>{};
    final displayName = _pickString(adult, ['displayName', 'popDisplayName']) ?? _pickString(data, ['popDisplayName']) ?? '';
    final job = _pickString(adult, ['job', 'work', 'profession']) ?? '';
    final hobby = _pickString(adult, ['hobby', 'hobbies', 'passion', 'passTime']) ?? '';
    final address = _pickString(adult, ['address', 'location', 'city']) ?? '';
    final ageVal = adult['age'];
    final skin = _pickString(adult, ['skinTone', 'skin', 'complexion']) ?? '';
    final pref = _pickString(adult, ['preferences', 'womenPreferences']) ?? '';
    final gender = _pickString(adult, ['gender', 'genre']) ?? _pickString(data, ['genre', 'gender']);
    final photo = _pickString(adult, ['photoUrl', 'photo']) ?? _pickString(data, ['adultPhotoUrl']);
    final voice = _pickString(adult, ['voiceIntroUrl', 'voiceUrl', 'voiceNoteUrl']) ?? _pickString(data, ['voiceIntroUrl']);
    _displayNameCtrl.text = displayName;
    _jobCtrl.text = job;
    _hobbyCtrl.text = hobby;
    _addressCtrl.text = address;
    _preferencesCtrl.text = pref;
    if (ageVal is int) _ageCtrl.text = ageVal.toString();
    if (ageVal is String && ageVal.trim().isNotEmpty) _ageCtrl.text = ageVal.trim();
    if (_ageCtrl.text.trim().isEmpty) {
      final birth = data['birthDate'];
      final age = _ageFrom(birth);
      if (age != null) _ageCtrl.text = age.toString();
    }
    if (gender != null && gender.trim().isNotEmpty) {
      final g = gender.toLowerCase();
      if (g.startsWith('h') || g.startsWith('m')) {
        _gender = 'Homme';
      } else if (g.startsWith('f')) _gender = 'Femme';
      else _gender = 'Autre';
    }
    if (skin.isNotEmpty) {
      final preset = ['Clair', 'Moyen', 'Foncé', 'Très foncé'];
      if (preset.contains(skin)) {
        _skinTone = skin;
        _skinToneOther = false;
      } else {
        _skinTone = 'Autre';
        _skinToneOther = true;
        _skinToneOtherCtrl.text = skin;
      }
    }
    if (photo != null && photo.isNotEmpty) {
      _adultPhotoUrl = photo;
    }
    if (voice != null && voice.isNotEmpty) {
      _voiceIntroUrl = voice;
    }
  }

  bool _isAdultProfileComplete(Map<String, dynamic> data) {
    final adult = (data['adultProfile'] is Map) ? Map<String, dynamic>.from(data['adultProfile']) : <String, dynamic>{};
    final displayName = _pickString(adult, ['displayName', 'popDisplayName']) ?? _pickString(data, ['popDisplayName']);
    final job = _pickString(adult, ['job', 'work', 'profession']);
    final hobby = _pickString(adult, ['hobby', 'hobbies', 'passion', 'passTime']);
    final address = _pickString(adult, ['address', 'location', 'city']);
    final skin = _pickString(adult, ['skinTone', 'skin', 'complexion']);
    final photo = _pickString(adult, ['photoUrl', 'photo']) ?? _pickString(data, ['adultPhotoUrl']);
    final voice = _pickString(adult, ['voiceIntroUrl', 'voiceUrl', 'voiceNoteUrl']) ?? _pickString(data, ['voiceIntroUrl']);
    final ageVal = adult['age'];
    int? age;
    if (ageVal is int) age = ageVal;
    if (ageVal is String) age = int.tryParse(ageVal.trim());
    final gender = _pickString(adult, ['gender', 'genre']) ?? _pickString(data, ['genre', 'gender']);
    final male = gender != null && (gender.toLowerCase().startsWith('h') || gender.toLowerCase().startsWith('m'));
    final pref = _pickString(adult, ['preferences', 'womenPreferences']);
    if (displayName == null || displayName.trim().isEmpty) return false;
    if (male && (pref == null || pref.trim().isEmpty)) return false;
    if (job == null || job.trim().isEmpty) return false;
    if (hobby == null || hobby.trim().isEmpty) return false;
    if (address == null || address.trim().isEmpty) return false;
    if (skin == null || skin.trim().isEmpty) return false;
    if (photo == null || photo.trim().isEmpty) return false;
    if (voice == null || voice.trim().isEmpty) return false;
    if (age == null || age < 18) return false;
    return true;
  }

  Future<void> _loadCandidates() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final collections = ['classic_users', 'pro_users', 'enterprise_users', 'users'];
      final List<_Candidate> candidates = [];
      final Set<String> seen = {};
      for (final col in collections) {
        final snap = await FirebaseFirestore.instance.collection(col).limit(40).get();
        for (final doc in snap.docs) {
          if (uid != null && doc.id == uid) continue;
          if (seen.contains(doc.id)) continue;
          final c = _docToCandidate(doc, col);
          if (c == null) continue;
          seen.add(doc.id);
          candidates.add(c);
        }
      }

      candidates.shuffle(Random());
      final episode = candidates.take(_episodeSize).toList();
      _pool
        ..clear()
        ..addAll(episode.map((c) => _BalloonCandidate(c)));
      _kept.clear();
      _poppedCount = 0;
      _finalChoice = null;
    } catch (e) {
      _loadError = 'Erreur chargement profils: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  _Candidate? _docToCandidate(QueryDocumentSnapshot<Map<String, dynamic>> doc, String col) {
    final d = doc.data();
    if (d.isEmpty) return null;
    if (d['adultDiscoverable'] == false || d['adult_discoverable'] == false || d['discoverable'] == false) {
      return null;
    }
    if (d['isValidated'] == false) return null;
    final adult = (d['adultProfile'] is Map) ? Map<String, dynamic>.from(d['adultProfile']) : <String, dynamic>{};
    final displayName = _pickString(adult, ['displayName', 'popDisplayName']) ?? _pickString(d, ['popDisplayName']);
    final name = displayName ??
        _pickString(d, ['displayName', 'name', 'fullName']) ??
        '${_pickString(d, ['firstName', 'first_name']) ?? ''} ${_pickString(d, ['lastName', 'last_name']) ?? ''}'.trim();
    if (name.isEmpty) return null;
    final birth = d['birthDate'];
    int? age = _ageFrom(birth);
    if (age == null) {
      final ageVal = adult['age'];
      if (ageVal is int) age = ageVal;
      if (ageVal is String) age = int.tryParse(ageVal.trim());
    }
    if (age == null || age < 18) return null;
    final city = _pickString(d, ['cityLabel', 'city', 'address', 'location']) ?? 'Ville inconnue';
    final job = _pickString(adult, ['job', 'work', 'profession']);
    final hobby = _pickString(adult, ['hobby', 'hobbies', 'passion', 'passTime']);
    final address = _pickString(adult, ['address', 'location', 'city']) ?? city;
    final pref = _pickString(adult, ['preferences', 'womenPreferences']);
    final gender = _pickString(adult, ['gender', 'genre']) ?? _pickString(d, ['gender', 'genre']);
    final skinTone = _pickString(adult, ['skinTone', 'skin', 'complexion']);
    final voiceIntroUrl = _pickString(adult, ['voiceIntroUrl', 'voiceUrl', 'voiceNoteUrl']) ?? _pickString(d, ['voiceIntroUrl']);
    final vibe = _pickString(adult, ['bio', 'about', 'headline', 'status', 'description']) ??
        _joinNonEmpty([job, hobby], separator: ' • ') ??
        _pickString(d, ['bio', 'about', 'headline', 'status', 'description']) ??
        'Profil disponible';
    final tags = _mergeTags(_pickTags(d), _pickTags(adult));
    final photo = _pickString(adult, ['photoUrl', 'photo']) ??
        _pickString(d, ['adultPhotoUrl']) ??
        _pickString(d, ['photoUrl', 'avatarUrl', 'imageUrl', 'profilePhoto', 'profilePhotoUrl']);
    final badge = _profileBadge(col, d);
    if (badge != null && !tags.contains(badge)) tags.add(badge);
    return _Candidate(
      id: doc.id,
      name: name,
      age: age,
      city: city,
      vibe: vibe,
      tags: tags,
      photoUrl: photo,
      job: job,
      hobby: hobby,
      address: address,
      preferences: pref,
      gender: gender,
      skinTone: skinTone,
      voiceIntroUrl: voiceIntroUrl,
    );
  }

  String? _pickString(Map<String, dynamic> data, List<String> keys) {
    for (final k in keys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  List<String> _pickTags(Map<String, dynamic> data) {
    final List<String> tags = [];
    for (final key in ['tags', 'interests', 'hobbies', 'skills']) {
      final v = data[key];
      if (v is List) {
        tags.addAll(v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty));
      }
    }
    return tags.take(5).toList();
  }

  List<String> _mergeTags(List<String> a, List<String> b) {
    final seen = <String>{};
    final out = <String>[];
    for (final t in [...a, ...b]) {
      final clean = t.trim();
      if (clean.isEmpty || seen.contains(clean)) continue;
      seen.add(clean);
      out.add(clean);
    }
    return out.take(5).toList();
  }

  String? _joinNonEmpty(List<String?> parts, {String separator = ' • '}) {
    final clean = parts.where((e) => e != null && e.trim().isNotEmpty).map((e) => e!.trim()).toList();
    if (clean.isEmpty) return null;
    return clean.join(separator);
  }

  int? _ageFrom(dynamic birth) {
    DateTime? dt;
    if (birth is Timestamp) {
      dt = birth.toDate();
    } else if (birth is String) {
      dt = DateTime.tryParse(birth.trim());
    } else if (birth is int) {
      dt = DateTime.fromMillisecondsSinceEpoch(birth);
    } else if (birth is DateTime) {
      dt = birth;
    }
    if (dt == null) return null;
    final now = DateTime.now();
    int years = now.year - dt.year;
    final m = now.month - dt.month;
    if (m < 0 || (m == 0 && now.day < dt.day)) years--;
    return years;
  }

  String? _profileBadge(String col, Map<String, dynamic> data) {
    final pt = data['profileType'];
    if (pt == 1 || col == 'pro_users') return 'Pro';
    if (pt == 2 || col == 'enterprise_users') return 'Entreprise';
    if (col == 'classic_users') return 'Classique';
    return null;
  }

  void _popCandidate(String id) {
    final item = _pool.firstWhere((e) => e.id == id, orElse: () => _BalloonCandidate.empty());
    if (item.isEmpty || item.removing || item.popped) return;
    _playPop();
    HapticFeedback.lightImpact();
    setState(() => item.popped = true);
    Future.delayed(const Duration(milliseconds: 880), () {
      if (!mounted) return;
      setState(() {
        _pool.removeWhere((e) => e.id == id);
        _poppedCount += 1;
        _maybeFinalize();
      });
    });
  }

  void _keepCandidate(String id) {
    final item = _pool.firstWhere((e) => e.id == id, orElse: () => _BalloonCandidate.empty());
    if (item.isEmpty || item.removing || item.popped) return;
    HapticFeedback.selectionClick();
    setState(() {
      item.kept = true;
      item.removing = true;
    });
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) return;
      setState(() {
        _pool.removeWhere((e) => e.id == id);
        _kept.add(item);
        _maybeFinalize();
      });
    });
  }

  String _chatIdForPair(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  Future<void> _openContactChat(_Candidate candidate) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous pour contacter cette personne.')),
      );
      return;
    }
    if (candidate.id == me.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous ne pouvez pas vous contacter vous-même.')),
      );
      return;
    }

    final chatId = _chatIdForPair(me.uid, candidate.id);
    final chatRef = FirebaseFirestore.instance.collection(_adultChatCollection).doc(chatId);
    final meName = _displayNameCtrl.text.trim().isNotEmpty
        ? _displayNameCtrl.text.trim()
        : (me.displayName ?? me.email ?? 'Moi');
    final candidateName = candidate.name.trim().isEmpty ? 'Utilisateur' : candidate.name.trim();

    final chatSnap = await chatRef.get();
    if (!chatSnap.exists) {
      await chatRef.set({
        'participants': [me.uid, candidate.id],
        'participantNames': {
          me.uid: meName,
          candidate.id: candidateName,
        },
        'status': 'pending',
        'requestedBy': me.uid,
        'requestedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Demande de chat envoyée à $candidateName.')),
        );
      }
      return;
    }

    final chatData = chatSnap.data() ?? <String, dynamic>{};
    final status = (chatData['status'] ?? 'accepted').toString();
    final requestedBy = (chatData['requestedBy'] ?? '').toString();

    if (status == 'accepted') {
      await _showContactChatSheet(
        candidate: candidate,
        chatId: chatId,
        meName: meName,
      );
      return;
    }

    if (status == 'blocked') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ce chat est bloqué.')),
        );
      }
      return;
    }

    if (status == 'pending') {
      if (requestedBy == me.uid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Demande en attente de validation.')),
          );
        }
        return;
      }
      final accept = await _askAcceptChatRequest(candidateName);
      if (accept == null) return;
      if (!accept) {
        await chatRef.set({
          'status': 'rejected',
          'rejectedBy': me.uid,
          'rejectedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Demande refusée.')),
          );
        }
        return;
      }
      await chatRef.set({
        'status': 'accepted',
        'acceptedBy': me.uid,
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _showContactChatSheet(
        candidate: candidate,
        chatId: chatId,
        meName: meName,
      );
      return;
    }

    await chatRef.set({
      'participants': [me.uid, candidate.id],
      'participantNames': {
        me.uid: meName,
        candidate.id: candidateName,
      },
      'status': 'pending',
      'requestedBy': me.uid,
      'requestedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nouvelle demande de chat envoyée à $candidateName.')),
      );
    }
  }

  Future<bool?> _askAcceptChatRequest(String name) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Demande de chat'),
        content: Text('$name veut discuter avec vous. Accepter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Refuser'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Accepter'),
          ),
        ],
      ),
    );
  }

  Future<void> _showContactChatSheet({
    required _Candidate candidate,
    required String chatId,
    required String meName,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final inputCtrl = TextEditingController();
    var sending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final messagesRef = FirebaseFirestore.instance
            .collection(_adultChatCollection)
            .doc(chatId)
            .collection('messages');
        final stream = messagesRef.orderBy('createdAt', descending: false).limit(120).snapshots();
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              height: MediaQuery.of(ctx).size.height * 0.64,
              decoration: BoxDecoration(
                color: Theme.of(ctx).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Chat avec ${candidate.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: stream,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final docs = snap.data?.docs ?? const [];
                        if (docs.isEmpty) {
                          return const Center(
                            child: Text('Démarre la conversation 👋'),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          itemCount: docs.length,
                          itemBuilder: (_, i) {
                            final d = docs[i].data();
                            final senderId = (d['senderId'] ?? '').toString();
                            final isMe = senderId == me.uid;
                            final text = (d['text'] ?? '').toString();
                            final createdAt = d['createdAt'];
                            final ts = createdAt is Timestamp ? createdAt : null;
                            return _chatBubble(
                              text: text,
                              isMe: isMe,
                              timeLabel: _chatTimeLabel(ts),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: inputCtrl,
                              minLines: 1,
                              maxLines: 3,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) async {
                                final text = inputCtrl.text.trim();
                                if (text.isEmpty || sending) return;
                                setModalState(() => sending = true);
                                final ok = await _sendContactMessage(
                                  chatId: chatId,
                                  toUserId: candidate.id,
                                  toUserName: candidate.name,
                                  fromUserName: meName,
                                  text: text,
                                );
                                if (!ok && ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(content: Text('Chat non autorisé : demande en attente.')),
                                  );
                                }
                                inputCtrl.clear();
                                if (ctx.mounted) setModalState(() => sending = false);
                              },
                              decoration: InputDecoration(
                                hintText: 'Écris un message…',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: sending
                                ? null
                                : () async {
                                    final text = inputCtrl.text.trim();
                                    if (text.isEmpty) return;
                                    setModalState(() => sending = true);
                                    final ok = await _sendContactMessage(
                                      chatId: chatId,
                                      toUserId: candidate.id,
                                      toUserName: candidate.name,
                                      fromUserName: meName,
                                      text: text,
                                    );
                                    if (!ok && ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(content: Text('Chat non autorisé : demande en attente.')),
                                      );
                                    }
                                    inputCtrl.clear();
                                    if (ctx.mounted) setModalState(() => sending = false);
                                  },
                            icon: sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                            tooltip: 'Envoyer',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    inputCtrl.dispose();
  }

  Future<bool> _sendContactMessage({
    required String chatId,
    required String toUserId,
    required String toUserName,
    required String fromUserName,
    required String text,
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return false;
    final chatRef = FirebaseFirestore.instance.collection(_adultChatCollection).doc(chatId);
    final chatSnap = await chatRef.get();
    if (!chatSnap.exists) return false;
    final chatData = chatSnap.data() ?? <String, dynamic>{};
    final status = (chatData['status'] ?? 'accepted').toString();
    if (status != 'accepted') return false;

    await chatRef.set({
      'participants': [me.uid, toUserId],
      'participantNames': {
        me.uid: fromUserName,
        toUserId: toUserName,
      },
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': text,
      'lastSenderId': me.uid,
    }, SetOptions(merge: true));

    await chatRef.collection('messages').add({
      'senderId': me.uid,
      'receiverId': toUserId,
      'senderName': fromUserName,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  Widget _chatBubble({
    required String text,
    required bool isMe,
    required String timeLabel,
  }) {
    final bubbleColor = isMe ? const Color(0xFFE85D04) : const Color(0xFF2A2D34);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 2),
            Text(
              timeLabel,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  String _chatTimeLabel(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _maybeFinalize() {
    if (_pool.isNotEmpty) return;
    if (_finalChoice != null) return;
    if (_kept.length == 1) {
      _finalChoice = _kept.first;
    }
  }

  Future<void> _playPop() async {
    try {
      await _popPlayer.stop();
      await _popPlayer.play(AssetSource('sounds/pop.mp3'), volume: 0.8);
    } catch (_) {}
  }

  bool get _isMale => _gender.toLowerCase().startsWith('h') || _gender.toLowerCase().startsWith('m');

  Future<void> _pickAdultPhoto() async {
    if (_photoPicking) return;
    setState(() => _photoPicking = true);
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _adultPhotoBytes = bytes;
        _adultPhotoChanged = true;
      });
    } finally {
      if (mounted) setState(() => _photoPicking = false);
    }
  }

  Future<void> _initVoiceRecorder() async {
    try {
      if (!kIsWeb) {
        final permission = await Permission.microphone.request();
        if (!permission.isGranted) return;
      }
      await _voiceRecorder.openRecorder();
      _voiceRecorderReady = true;
    } catch (e) {
      debugPrint('Voice recorder init failed: $e');
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_voiceBusy) return;
    if (_isRecordingVoice) {
      await _stopVoiceRecording();
      return;
    }
    await _startVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    if (_voiceBusy) return;
    _voiceBusy = true;
    if (mounted) setState(() {});
    try {
      if (!_voiceRecorderReady) {
        await _initVoiceRecorder();
      }
      if (!_voiceRecorderReady) {
        _profileError = 'Micro non disponible.';
        return;
      }
      final started = await _startRecorderWithFallback();
      if (!started) {
        _profileError = 'Micro indisponible ou codec non supporte sur cet appareil.';
        return;
      }
      if (!mounted) return;
      setState(() {
        _voiceSeconds = 0;
        _isRecordingVoice = true;
        _profileError = null;
      });
      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_isRecordingVoice) {
          timer.cancel();
          return;
        }
        setState(() => _voiceSeconds += 1);
        if (_voiceSeconds >= _maxVoiceSeconds) {
          unawaited(_stopVoiceRecording());
        }
      });
    } catch (e) {
      _profileError = 'Impossible de demarrer l\'enregistrement.';
      debugPrint('Voice record start failed: $e');
    } finally {
      _voiceBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _stopVoiceRecording() async {
    if (_voiceBusy) return;
    _voiceBusy = true;
    if (mounted) setState(() {});
    try {
      _voiceTimer?.cancel();
      _voiceTimer = null;
      final path = await _voiceRecorder.stopRecorder();
      if (!mounted) return;
      setState(() => _isRecordingVoice = false);
      if (_recordingToStream) {
        final bytes = Uint8List.fromList(_voiceStreamBuffer);
        await _disposeVoiceStreamCapture();
        if (bytes.isEmpty) {
          _profileError = 'Impossible de lire la note vocale enregistree.';
          return;
        }
        final ext = _currentRecordingExt.trim().isEmpty ? 'webm' : _currentRecordingExt;
        setState(() {
          _voiceIntroBytes = bytes;
          _voiceIntroExt = ext;
          _voiceIntroName = 'note_vocale.$ext';
          _voiceIntroChanged = true;
          _profileError = null;
        });
        return;
      }
      if (path == null || path.trim().isEmpty) {
        _profileError = 'Enregistrement invalide.';
        return;
      }
      final bytes = await _recordedPathToBytes(path);
      if (bytes == null || bytes.isEmpty) {
        _profileError = 'Impossible de lire la note vocale enregistree.';
        return;
      }
      final ext = _extensionFromPath(path, fallback: _currentRecordingExt);
      setState(() {
        _voiceIntroBytes = bytes;
        _voiceIntroExt = ext;
        _voiceIntroName = 'note_vocale.$ext';
        _voiceIntroChanged = true;
        _profileError = null;
      });
    } catch (e) {
      _profileError = 'Impossible d\'arreter l\'enregistrement.';
      debugPrint('Voice record stop failed: $e');
    } finally {
      _voiceBusy = false;
      if (mounted) setState(() {});
    }
  }

  Future<bool> _startRecorderWithFallback() async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final options = _recorderOptionsForPlatform();
    for (final option in options) {
      try {
        final supported = await _voiceRecorder.isEncoderSupported(option.codec);
        if (!supported) continue;
        if (kIsWeb) {
          await _prepareVoiceStreamCapture();
          await _voiceRecorder.startRecorder(
            codec: option.codec,
            toStream: _voiceStreamController!.sink,
          );
          _recordingToStream = true;
        } else {
          await _voiceRecorder.startRecorder(
            toFile: 'voice_intro_$stamp.${option.ext}',
            codec: option.codec,
          );
          _recordingToStream = false;
        }
        _currentRecordingExt = option.ext;
        return true;
      } catch (e) {
        await _disposeVoiceStreamCapture();
        debugPrint('Voice record candidate failed (${option.codec}): $e');
      }
    }

    try {
      if (kIsWeb) {
        await _prepareVoiceStreamCapture();
        await _voiceRecorder.startRecorder(
          codec: Codec.defaultCodec,
          toStream: _voiceStreamController!.sink,
        );
        _recordingToStream = true;
      } else {
        await _voiceRecorder.startRecorder(codec: Codec.defaultCodec);
        _recordingToStream = false;
      }
      _currentRecordingExt = kIsWeb ? 'webm' : 'm4a';
      return true;
    } catch (e) {
      await _disposeVoiceStreamCapture();
      debugPrint('Voice record fallback failed: $e');
      return false;
    }
  }

  List<_RecorderOption> _recorderOptionsForPlatform() {
    if (kIsWeb) {
      return const [
        _RecorderOption(Codec.opusWebM, 'webm'),
        _RecorderOption(Codec.aacMP4, 'm4a'),
        _RecorderOption(Codec.aacADTS, 'aac'),
      ];
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return const [
          _RecorderOption(Codec.pcm16WAV, 'wav'),
          _RecorderOption(Codec.aacMP4, 'm4a'),
          _RecorderOption(Codec.aacADTS, 'aac'),
        ];
      default:
        return const [
          _RecorderOption(Codec.aacMP4, 'm4a'),
          _RecorderOption(Codec.aacADTS, 'aac'),
          _RecorderOption(Codec.pcm16WAV, 'wav'),
        ];
    }
  }

  String _extensionFromPath(String path, {String fallback = 'm4a'}) {
    final clean = path.split('?').first;
    final dot = clean.lastIndexOf('.');
    if (dot == -1 || dot == clean.length - 1) return fallback;
    return clean.substring(dot + 1).toLowerCase();
  }

  Future<void> _prepareVoiceStreamCapture() async {
    await _disposeVoiceStreamCapture();
    _voiceStreamBuffer.clear();
    _voiceStreamController = StreamController<Uint8List>();
    _voiceStreamSub = _voiceStreamController!.stream.listen((chunk) {
      _voiceStreamBuffer.addAll(chunk);
    });
  }

  Future<void> _disposeVoiceStreamCapture() async {
    await _voiceStreamSub?.cancel();
    _voiceStreamSub = null;
    final controller = _voiceStreamController;
    _voiceStreamController = null;
    if (controller != null) {
      await controller.close();
    }
    _recordingToStream = false;
  }

  Future<Uint8List?> _recordedPathToBytes(String path) async {
    try {
      final x = XFile(path);
      final bytes = await x.readAsBytes();
      if (bytes.isNotEmpty) return bytes;
    } catch (_) {}
    try {
      final uri = Uri.tryParse(path);
      if (uri != null && (uri.isScheme('http') || uri.isScheme('https') || uri.isScheme('blob'))) {
        final resp = await http.get(uri);
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          return resp.bodyBytes;
        }
      }
    } catch (_) {}
    return null;
  }

  String _voiceDurationLabel() {
    final m = (_voiceSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_voiceSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _clearVoiceIntro() {
    setState(() {
      _voiceIntroBytes = null;
      _voiceIntroName = null;
      _voiceIntroExt = 'm4a';
      _voiceIntroUrl = null;
      _voiceIntroChanged = true;
      _voicePlaying = false;
    });
    unawaited(_voicePlayer.stop());
  }

  Future<String?> _uploadAdultPhoto(String uid) async {
    if (!_adultPhotoChanged || _adultPhotoBytes == null) return _adultPhotoUrl;
    if (!SupabaseService.isInitialized) {
      throw Exception('Supabase non initialisé. Vérifie SUPABASE_URL et SUPABASE_ANON_KEY.');
    }
    final objectPath = 'adult_profiles/$uid/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    return await SupabaseService.uploadBytesNamed(
      _adultPhotoBytes!,
      objectPath,
      'Poptheballon',
      contentType: 'image/jpeg',
    );
  }

  String _audioContentType(String ext) {
    switch (ext) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'aac':
        return 'audio/aac';
      case 'webm':
        return 'audio/webm';
      case 'm4a':
      default:
        return 'audio/mp4';
    }
  }

  Future<String?> _uploadVoiceIntro(String uid) async {
    if (!_voiceIntroChanged || _voiceIntroBytes == null) return _voiceIntroUrl;
    if (!SupabaseService.isInitialized) {
      throw Exception('Supabase non initialise. Verifie SUPABASE_URL et SUPABASE_ANON_KEY.');
    }
    final ext = _voiceIntroExt.trim().isEmpty ? 'm4a' : _voiceIntroExt.trim().toLowerCase();
    final objectPath = 'adult_profiles/$uid/voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
    return await SupabaseService.uploadBytesNamed(
      _voiceIntroBytes!,
      objectPath,
      'Poptheballon',
      contentType: _audioContentType(ext),
    );
  }

  Future<void> _saveAdultProfile() async {
    if (_savingProfile) return;
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _userRef == null) {
        _profileError = 'Utilisateur non connecté.';
        return;
      }
      final displayName = _displayNameCtrl.text.trim();
      final job = _jobCtrl.text.trim();
      final hobby = _hobbyCtrl.text.trim();
      final address = _addressCtrl.text.trim();
      final age = int.tryParse(_ageCtrl.text.trim());
      final preferences = _preferencesCtrl.text.trim();
      final skinTone = _skinToneOther ? _skinToneOtherCtrl.text.trim() : _skinTone;

      if (displayName.isEmpty) {
        _profileError = 'Ajoutez un nom d\'affichage pour Pop the Ballon.';
        return;
      }
      if (job.isEmpty || hobby.isEmpty || address.isEmpty || skinTone.isEmpty) {
        _profileError = 'Tous les champs sont requis.';
        return;
      }
      if (age == null || age < 18) {
        _profileError = 'L’âge doit être ≥ 18.';
        return;
      }
      if (_isMale && preferences.isEmpty) {
        _profileError = 'Précisez vos préférences.';
        return;
      }
      if (!SupabaseService.isInitialized) {
        _profileError = 'Supabase non initialisé. Vérifiez la configuration.';
        return;
      }
      await _ensureSupabaseAuthWithFallback();

      final photoUrl = await _uploadAdultPhoto(user.uid);
      if (photoUrl == null || photoUrl.trim().isEmpty) {
        _profileError = 'Ajoutez une photo pour l’espace adulte.';
        return;
      }
      final voiceIntroUrl = await _uploadVoiceIntro(user.uid);
      if (voiceIntroUrl == null || voiceIntroUrl.trim().isEmpty) {
        _profileError = 'Ajoutez une note vocale de presentation.';
        return;
      }

      final adultProfile = <String, dynamic>{
        'displayName': displayName,
        'popDisplayName': displayName,
        'job': job,
        'hobby': hobby,
        'age': age,
        'skinTone': skinTone,
        'address': address,
        'gender': _gender,
        'preferences': _isMale ? preferences : '',
        'photoUrl': photoUrl,
        'voiceIntroUrl': voiceIntroUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _userRef!.set({
        'adultProfile': adultProfile,
        'popDisplayName': displayName,
        'adultProfileComplete': true,
        'adultPhotoUrl': photoUrl,
        'voiceIntroUrl': voiceIntroUrl,
        'adultProfileUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _adultPhotoUrl = photoUrl;
      _voiceIntroUrl = voiceIntroUrl;
      _voiceIntroChanged = false;
      _adultPhotoChanged = false;
      _profileGate = false;
      _editingProfile = false;
      _profileError = null;
      await _loadCandidates();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('401') || msg.contains('403') || msg.contains('permission')) {
        _profileError =
            'Upload refusé par la policy Storage. Autorisez le bucket Poptheballon pour role authenticated ou anon.';
      } else {
        _profileError = 'Erreur sauvegarde: $e';
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _ensureSupabaseAuthWithFallback() async {
    final session = SupabaseService.client.auth.currentSession;
    if (session != null) return;
    try {
      await SupabaseService.client.auth.signInAnonymously();
    } catch (e) {
      debugPrint('Supabase anonymous auth unavailable, fallback to anon policy: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F1416) : const Color(0xFFF7F8FA);
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white70 : Colors.black54;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: bg,
        iconTheme: IconThemeData(color: text),
        title: Text('Pop the Ballon', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
        actions: _profileGate
            ? null
            : _editingProfile
                ? [
                    IconButton(
                      onPressed: () => setState(() => _editingProfile = false),
                      tooltip: 'Fermer',
                      icon: const Icon(Icons.close),
                    ),
                  ]
                : [
                    IconButton(
                      onPressed: _openEditProfile,
                      tooltip: 'Modifier mon profil',
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: _openMyProfilePreview,
                      tooltip: 'Mon profil',
                      icon: const Icon(Icons.person_outline),
                    ),
                    IconButton(onPressed: _loadCandidates, icon: const Icon(Icons.refresh)),
                  ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              bg,
              isDark ? const Color(0xFF1A1F24) : const Color(0xFFF0F4FF),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _profileChecking
            ? const Center(child: CircularProgressIndicator())
            : (_profileGate || _editingProfile)
                ? _profileGateView(text: text, sub: sub, isDark: isDark)
                : Column(
                    children: [
                      _hero(text: text, sub: sub, isDark: isDark),
                      _stats(text: text, sub: sub),
                      if (_kept.isNotEmpty) _shortlist(text: text, sub: sub),
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : (_loadError != null)
                                ? _errorState(text: text, sub: sub)
                                : _pool.isEmpty
                                    ? _endState(text: text, sub: sub, isDark: isDark)
                                    : ListView.builder(
                                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                        itemCount: _pool.length,
                                        itemBuilder: (_, i) => _candidateTile(_pool[i], text, sub, isDark),
                                      ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _profileGateView({required Color text, required Color sub, required bool isDark}) {
    final accent = const Color(0xFFE85D04);
    final card = isDark ? Colors.white.withOpacity(0.06) : Colors.white;
    final isEditing = _editingProfile && !_profileGate;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFFE85D04).withOpacity(0.9),
                const Color(0xFFFF477E).withOpacity(0.9),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.15), blurRadius: 22, offset: const Offset(0, 12))],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
                child: const Icon(Icons.workspace_premium, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Profil adulte requis', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      'Complétez votre profil pour participer à Pop the Ballon.',
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.25 : 0.08), blurRadius: 18, offset: const Offset(0, 10))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Infos personnelles', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _field(
                controller: _displayNameCtrl,
                label: 'Nom d\'affichage Pop the Ballon',
                icon: Icons.badge_outlined,
                text: text,
                sub: sub,
              ),
              const SizedBox(height: 10),
              _field(
                controller: _jobCtrl,
                label: 'Travail / Profession',
                icon: Icons.work_outline,
                text: text,
                sub: sub,
              ),
              const SizedBox(height: 10),
              _field(
                controller: _hobbyCtrl,
                label: 'Passe-temps favori',
                icon: Icons.sports_tennis_outlined,
                text: text,
                sub: sub,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      controller: _ageCtrl,
                      label: 'Âge',
                      icon: Icons.cake_outlined,
                      text: text,
                      sub: sub,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: _fieldDecoration('Genre', text, sub, icon: Icons.person_outline),
                      items: const [
                        DropdownMenuItem(value: 'Homme', child: Text('Homme')),
                        DropdownMenuItem(value: 'Femme', child: Text('Femme')),
                        DropdownMenuItem(value: 'Autre', child: Text('Autre')),
                      ],
                      onChanged: (v) => setState(() => _gender = v ?? 'Homme'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _skinTone,
                decoration: _fieldDecoration('Teint', text, sub, icon: Icons.palette_outlined),
                items: const [
                  DropdownMenuItem(value: 'Clair', child: Text('Clair')),
                  DropdownMenuItem(value: 'Moyen', child: Text('Moyen')),
                  DropdownMenuItem(value: 'Foncé', child: Text('Foncé')),
                  DropdownMenuItem(value: 'Très foncé', child: Text('Très foncé')),
                  DropdownMenuItem(value: 'Autre', child: Text('Autre')),
                ],
                onChanged: (v) {
                  final sel = v ?? 'Moyen';
                  setState(() {
                    _skinTone = sel;
                    _skinToneOther = sel == 'Autre';
                  });
                },
              ),
              if (_skinToneOther) ...[
                const SizedBox(height: 10),
                _field(
                  controller: _skinToneOtherCtrl,
                  label: 'Précisez votre teint',
                  icon: Icons.edit_outlined,
                  text: text,
                  sub: sub,
                ),
              ],
              const SizedBox(height: 10),
              _field(
                controller: _addressCtrl,
                label: 'Adresse / Ville',
                icon: Icons.location_on_outlined,
                text: text,
                sub: sub,
              ),
              const SizedBox(height: 10),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: _isMale ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                firstChild: _field(
                  controller: _preferencesCtrl,
                  label: 'Préférences (femmes)',
                  icon: Icons.favorite_border,
                  text: text,
                  sub: sub,
                ),
                secondChild: const SizedBox.shrink(),
              ),
              const SizedBox(height: 14),
              Text('Photo adulte', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _photoPicking ? null : _pickAdultPhoto,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(isDark ? 0.18 : 0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withOpacity(0.25)),
                  ),
                  child: Center(
                    child: _adultPhotoBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(_adultPhotoBytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                          )
                        : (_adultPhotoUrl != null && _adultPhotoUrl!.isNotEmpty)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.network(_adultPhotoUrl!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_a_photo_outlined, color: accent),
                                  const SizedBox(height: 6),
                                  Text('Ajouter une photo', style: TextStyle(color: sub)),
                                  const SizedBox(height: 2),
                                  Text('Uniquement pour l’espace adulte', style: TextStyle(color: sub, fontSize: 11)),
                                ],
                              ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Note vocale de presentation', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(isDark ? 0.18 : 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isRecordingVoice
                          ? 'Enregistrement en cours ${_voiceDurationLabel()} / 00:${_maxVoiceSeconds.toString().padLeft(2, '0')}'
                          : (_voiceIntroName ?? (_voiceIntroUrl != null ? 'Note vocale deja enregistree' : 'Aucune note vocale')),
                      style: TextStyle(color: sub, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _voiceBusy ? null : _toggleVoiceRecording,
                            icon: Icon(_isRecordingVoice ? Icons.stop_circle_outlined : Icons.mic_none_outlined),
                            label: Text(_isRecordingVoice ? 'Arreter' : 'Enregistrer'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: (_voiceIntroBytes == null && (_voiceIntroUrl == null || _voiceIntroUrl!.isEmpty))
                              ? null
                              : () => _toggleVoicePlayback(
                                    url: _voiceIntroUrl,
                                    previewBytes: _voiceIntroBytes,
                                  ),
                          icon: Icon(_voicePlaying ? Icons.stop : Icons.play_arrow),
                          label: Text(_voicePlaying ? 'Stop' : 'Ecouter'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Supprimer',
                          onPressed: (_voiceIntroBytes == null && (_voiceIntroUrl == null || _voiceIntroUrl!.isEmpty))
                              ? null
                              : _clearVoiceIntro,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_profileError != null) ...[
                const SizedBox(height: 10),
                Text(_profileError!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openMyProfilePreview,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Visualiser mon profil'),
                ),
              ),
              if (isEditing) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _editingProfile = false),
                    icon: const Icon(Icons.close),
                    label: const Text('Annuler'),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _savingProfile ? null : _saveAdultProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(_savingProfile ? 'Enregistrement...' : (isEditing ? 'Enregistrer les modifications' : 'Enregistrer et continuer')),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Votre photo adulte n’apparaît que dans cet espace.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String label, Color text, Color sub, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: sub),
      prefixIcon: icon != null ? Icon(icon, color: sub) : null,
      filled: true,
      fillColor: Colors.black.withOpacity(0.03),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color text,
    required Color sub,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: TextStyle(color: text),
      decoration: _fieldDecoration(label, text, sub, icon: icon),
    );
  }

  Widget _hero({required Color text, required Color sub, required bool isDark}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFE85D04).withOpacity(isDark ? 0.8 : 0.9),
            const Color(0xFFFF477E).withOpacity(isDark ? 0.8 : 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.25 : 0.12), blurRadius: 22, offset: const Offset(0, 12))],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
            child: const Icon(Icons.bubble_chart_outlined, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pop the Ballon', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Tape le ballon pour éliminer • Garde les meilleurs profils', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats({required Color text, required Color sub}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          _statChip('Restants', _pool.length.toString(), text),
          const SizedBox(width: 8),
          _statChip('Pop', _poppedCount.toString(), text),
          const SizedBox(width: 8),
          _statChip('Gardés', _kept.length.toString(), text),
          const Spacer(),
          Text('Épisode $_episodeSize profils', style: TextStyle(color: sub, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _shortlist({required Color text, required Color sub}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Shortlist', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kept.map((c) => _pill('${c.data.name}, ${c.data.age}', text)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _candidateTile(_BalloonCandidate item, Color text, Color sub, bool isDark) {
    final color = _balloonColor(item.data.name.hashCode);
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      child: item.removing
          ? const SizedBox.shrink()
          : AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: item.removing ? 0.0 : 1.0,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: () => _openCandidateProfile(item.data),
                    child: Container(
                      margin: const EdgeInsets.only(top: 28, bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.08), blurRadius: 16, offset: const Offset(0, 8))],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _avatar(item.data.name, color, photoUrl: item.data.photoUrl),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${item.data.name}, ${item.data.age}', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text(item.data.city, style: TextStyle(color: sub)),
                                const SizedBox(height: 6),
                                Text(item.data.vibe, style: TextStyle(color: sub)),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  children: item.data.tags.map((t) => _tag(t, sub)).toList(),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () => _openCandidateProfile(item.data),
                                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                                  icon: const Icon(Icons.visibility_outlined, size: 18),
                                  label: const Text('Voir profil'),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        onPressed: () => _keepCandidate(item.id),
                                        icon: const Icon(Icons.favorite_border),
                                        color: Colors.pinkAccent,
                                        tooltip: 'Garder',
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        onPressed: () => _openContactChat(item.data),
                                        icon: const Icon(Icons.chat_bubble_outline),
                                        color: Colors.lightBlueAccent,
                                        tooltip: 'Contacter',
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: -24,
                    right: 10,
                    child: GestureDetector(
                      onTap: () => _popCandidate(item.id),
                      child: _balloon(color, item.popped),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _balloon(Color color, bool popped) {
    final balloonCore = SizedBox(
      width: 104,
      height: 132,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          if (popped) Positioned.fill(child: IgnorePointer(child: _BurstEffect(color: color))),
          AnimatedScale(
            duration: const Duration(milliseconds: 220),
            scale: popped ? 0.2 : 1,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: popped ? 0 : 1,
              child: Column(
                children: [
                  Container(
                    width: 82,
                    height: 102,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [color.withOpacity(0.98), color.withOpacity(0.7), color.withOpacity(0.52)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(52),
                      boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 9))],
                    ),
                    child: Stack(
                      children: [
                        Align(
                          alignment: const Alignment(-0.35, -0.58),
                          child: Container(
                            width: 20,
                            height: 26,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.52),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        Align(
                          alignment: const Alignment(0.35, -0.2),
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.45), shape: BoxShape.circle),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 14,
                    height: 9,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.84),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(2), bottom: Radius.circular(8)),
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 16,
                    color: Colors.black.withOpacity(0.2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (popped) return balloonCore;
    return AnimatedBuilder(
      animation: _balloonMotionCtrl,
      child: balloonCore,
      builder: (context, child) {
        final t = _balloonMotionCtrl.value * 2 * pi;
        final swayX = sin(t) * 3.4;
        final swayY = cos(t * 1.7) * 1.7;
        final tilt = sin(t) * 0.035;
        return Transform.translate(
          offset: Offset(swayX, swayY),
          child: Transform.rotate(
            angle: tilt,
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _toggleVoicePlayback({
    String? url,
    Uint8List? previewBytes,
  }) async {
    try {
      if (_voicePlaying) {
        await _voicePlayer.stop();
        if (mounted) setState(() => _voicePlaying = false);
        return;
      }
      if (previewBytes != null && previewBytes.isNotEmpty) {
        await _voicePlayer.play(BytesSource(previewBytes), volume: 1.0);
        if (mounted) setState(() => _voicePlaying = true);
        return;
      }
      if (url != null && url.trim().isNotEmpty) {
        await _voicePlayer.play(UrlSource(url.trim()), volume: 1.0);
        if (mounted) setState(() => _voicePlaying = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _voicePlaying = false;
          _profileError = 'Impossible de lire la note vocale.';
        });
      }
    }
  }

  void _openCandidateProfile(_Candidate candidate) {
    _openProfileSheet(candidate, title: 'Profil');
  }

  void _openMyProfilePreview() {
    final profile = _buildMyProfileCandidate();
    _openProfileSheet(
      profile,
      title: 'Mon profil',
      previewBytes: _adultPhotoBytes,
      previewVoiceBytes: _voiceIntroBytes,
    );
  }

  _Candidate _buildMyProfileCandidate() {
    final age = int.tryParse(_ageCtrl.text.trim()) ?? 18;
    final display = _displayNameCtrl.text.trim().isNotEmpty ? _displayNameCtrl.text.trim() : 'Mon profil';
    final city = _addressCtrl.text.trim().isNotEmpty ? _addressCtrl.text.trim() : 'Adresse non renseignee';
    final skinTone = _skinToneOther ? _skinToneOtherCtrl.text.trim() : _skinTone;
    final vibe = _joinNonEmpty([_jobCtrl.text.trim(), _hobbyCtrl.text.trim()]) ?? 'Profil en cours de creation';
    return _Candidate(
      id: 'me',
      name: display,
      age: age,
      city: city,
      vibe: vibe,
      tags: const <String>[],
      photoUrl: _adultPhotoUrl,
      job: _jobCtrl.text.trim(),
      hobby: _hobbyCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      preferences: _preferencesCtrl.text.trim(),
      gender: _gender,
      skinTone: skinTone,
      voiceIntroUrl: _voiceIntroUrl,
    );
  }

  void _openProfileSheet(
    _Candidate candidate, {
    required String title,
    Uint8List? previewBytes,
    Uint8List? previewVoiceBytes,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white70 : Colors.black54;
    final accentA = const Color(0xFFE85D04);
    final accentB = const Color(0xFFFF477E);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF0F1416) : const Color(0xFFF7F8FA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        final hasZoomablePhoto =
            (previewBytes != null && previewBytes.isNotEmpty) ||
            (candidate.photoUrl != null && candidate.photoUrl!.trim().isNotEmpty);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accentA.withOpacity(0.9), accentB.withOpacity(0.9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MouseRegion(
                        cursor: hasZoomablePhoto ? SystemMouseCursors.click : MouseCursor.defer,
                        child: GestureDetector(
                          onTap: hasZoomablePhoto
                              ? () => _openPhotoZoom(previewBytes: previewBytes, url: candidate.photoUrl)
                              : null,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: previewBytes != null && previewBytes.isNotEmpty
                                    ? Image.memory(previewBytes, width: 60, height: 60, fit: BoxFit.cover)
                                    : _avatar(candidate.name, Colors.white, photoUrl: candidate.photoUrl),
                              ),
                              if (hasZoomablePhoto)
                                Positioned(
                                  right: -6,
                                  bottom: -6,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.55),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.zoom_in, color: Colors.white, size: 14),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text('${candidate.name}, ${candidate.age}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                            const SizedBox(height: 2),
                            Text(candidate.city, style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('A propos', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(candidate.vibe, style: TextStyle(color: sub, height: 1.45)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill('Age ${candidate.age}', text),
                          _pill(candidate.city, text),
                          if ((candidate.gender ?? '').trim().isNotEmpty) _pill(candidate.gender!.trim(), text),
                          if ((candidate.skinTone ?? '').trim().isNotEmpty) _pill('Teint ${candidate.skinTone!.trim()}', text),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _profileInfoCard(
                  text: text,
                  sub: sub,
                  job: candidate.job,
                  hobby: candidate.hobby,
                  address: candidate.address,
                  preferences: candidate.preferences,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mic_none_outlined, color: sub),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Note vocale de presentation',
                          style: TextStyle(color: text, fontWeight: FontWeight.w700),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: ((candidate.voiceIntroUrl == null || candidate.voiceIntroUrl!.trim().isEmpty) &&
                                (previewVoiceBytes == null || previewVoiceBytes.isEmpty))
                            ? null
                            : () => _toggleVoicePlayback(
                                  url: candidate.voiceIntroUrl,
                                  previewBytes: previewVoiceBytes,
                                ),
                        icon: Icon(_voicePlaying ? Icons.stop : Icons.play_arrow),
                        label: Text(_voicePlaying ? 'Stop' : 'Ecouter'),
                      ),
                    ],
                  ),
                ),
                if (candidate.tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Centres d\'interet', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: candidate.tags.map((t) => _tag(t, sub)).toList(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _openPhotoZoom({Uint8List? previewBytes, String? url}) {
    final hasBytes = previewBytes != null && previewBytes.isNotEmpty;
    final cleanUrl = (url ?? '').trim();
    if (!hasBytes && cleanUrl.isEmpty) return;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.all(8),
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.82,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: hasBytes
                          ? Image.memory(previewBytes, fit: BoxFit.contain)
                          : Image.network(cleanUrl, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Fermer',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _profileInfoCard({
    required Color text,
    required Color sub,
    String? job,
    String? hobby,
    String? address,
    String? preferences,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _profileInfoRow('Travail', job, text, sub),
          _profileInfoRow('Passe-temps', hobby, text, sub),
          _profileInfoRow('Adresse', address, text, sub),
          _profileInfoRow('Preferences', preferences, text, sub),
        ],
      ),
    );
  }

  Widget _profileInfoRow(String label, String? value, Color text, Color sub) {
    final display = (value == null || value.trim().isEmpty) ? 'Non renseigne' : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: text, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(display, style: TextStyle(color: sub)),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String name, Color color, {String? photoUrl}) {
    final clean = name.trim();
    final initial = clean.isNotEmpty ? clean.substring(0, 1).toUpperCase() : '?';
    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          photoUrl,
          width: 46,
          height: 46,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatarFallback(initial, color),
        ),
      );
    }
    return _avatarFallback(initial, color);
  }

  Widget _avatarFallback(String initial, Color color) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(initial, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _tag(String text, Color sub) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: sub, fontSize: 11)),
    );
  }

  Widget _statChip(String label, String value, Color text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(value, style: TextStyle(color: text, fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: text.withOpacity(0.7), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _pill(String text, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.pinkAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _endState({required Color text, required Color sub, required bool isDark}) {
    if (_finalChoice != null) return _finalView(text: text, sub: sub, isDark: isDark);
    if (_kept.length > 1) return _finalSelection(text: text, sub: sub);
    return _emptyState(text: text, sub: sub);
  }

  Widget _finalSelection({required Color text, required Color sub}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text('Choisissez le finaliste', style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 10),
        ..._kept.map((c) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _avatar(c.data.name, _balloonColor(c.data.name.hashCode), photoUrl: c.data.photoUrl),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${c.data.name}, ${c.data.age}', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () => setState(() => _finalChoice = c),
                  child: const Text('Choisir'),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _loadCandidates,
          icon: const Icon(Icons.refresh),
          label: const Text('Nouvel épisode'),
        ),
      ],
    );
  }

  Widget _finalView({required Color text, required Color sub, required bool isDark}) {
    final c = _finalChoice!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined, size: 48, color: Colors.orangeAccent),
            const SizedBox(height: 10),
            Text('Finaliste', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _avatar(c.data.name, _balloonColor(c.data.name.hashCode), photoUrl: c.data.photoUrl),
            const SizedBox(height: 8),
            Text('${c.data.name}, ${c.data.age}', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(c.data.city, style: TextStyle(color: sub)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _loadCandidates,
              icon: const Icon(Icons.refresh),
              label: const Text('Nouvel épisode'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState({required Color text, required Color sub}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_outlined, size: 48, color: Colors.orangeAccent),
          const SizedBox(height: 10),
          Text('Fin de la partie', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Relance pour rejouer', style: TextStyle(color: sub)),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _loadCandidates,
            icon: const Icon(Icons.refresh),
            label: const Text('Rejouer'),
          ),
        ],
      ),
    );
  }

  Widget _errorState({required Color text, required Color sub}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 10),
          Text(_loadError ?? 'Erreur chargement', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Réessayez', style: TextStyle(color: sub)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loadCandidates,
            icon: const Icon(Icons.refresh),
            label: const Text('Recharger'),
          ),
        ],
      ),
    );
  }

  Color _balloonColor(int seed) {
    final rng = Random(seed);
    final palette = [
      const Color(0xFF00CBA9),
      const Color(0xFFE85D04),
      const Color(0xFFFF477E),
      const Color(0xFF5E60CE),
      const Color(0xFF48BFE3),
      const Color(0xFFFFB703),
    ];
    return palette[rng.nextInt(palette.length)];
  }
}

class _Candidate {
  final String id;
  final String name;
  final int age;
  final String city;
  final String vibe;
  final List<String> tags;
  final String? photoUrl;
  final String? job;
  final String? hobby;
  final String? address;
  final String? preferences;
  final String? gender;
  final String? skinTone;
  final String? voiceIntroUrl;
  _Candidate({
    required this.id,
    required this.name,
    required this.age,
    required this.city,
    required this.vibe,
    required this.tags,
    this.photoUrl,
    this.job,
    this.hobby,
    this.address,
    this.preferences,
    this.gender,
    this.skinTone,
    this.voiceIntroUrl,
  });
}

class _BalloonCandidate {
  final String id;
  final _Candidate data;
  bool popped = false;
  bool removing = false;
  bool kept = false;

  _BalloonCandidate(this.data) : id = data.id;
  _BalloonCandidate.empty()
      : id = '_empty',
        data = _Candidate(
          id: '_empty',
          name: '',
          age: 0,
          city: '',
          vibe: '',
          tags: const [],
          job: '',
          hobby: '',
          address: '',
          preferences: '',
          gender: '',
          skinTone: '',
          voiceIntroUrl: '',
        ),
        popped = false,
        removing = true,
        kept = false;

  bool get isEmpty => id == '_empty';
}

class _BurstEffect extends StatelessWidget {
  final Color color;
  const _BurstEffect({required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 360),
      builder: (context, t, _) {
        final opacity = (1 - t).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: 0.4 + (t * 0.9),
            child: CustomPaint(
              painter: _BurstPainter(color: color, progress: t),
            ),
          ),
        );
      },
    );
  }
}

class _BurstPainter extends CustomPainter {
  final Color color;
  final double progress;
  _BurstPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const rays = 12;
    final outer = 36.0 * progress;
    final inner = 7.0 + (10 * progress);
    final rayPaint = Paint()
      ..color = color.withOpacity(0.92)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final centerFlash = Paint()..color = Colors.white.withOpacity((0.9 - progress).clamp(0.0, 0.9));
    final shockPaint = Paint()
      ..color = color.withOpacity((0.55 - (progress * 0.5)).clamp(0.0, 0.55))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    canvas.drawCircle(c, 5.5 + (8.5 * progress), centerFlash);
    canvas.drawCircle(c, 9 + (18 * progress), shockPaint);

    for (var i = 0; i < rays; i++) {
      final angle = (pi * 2 / rays) * i;
      final dx = cos(angle);
      final dy = sin(angle);
      final p1 = Offset(c.dx + dx * inner, c.dy + dy * inner);
      final p2 = Offset(c.dx + dx * (inner + outer), c.dy + dy * (inner + outer));
      canvas.drawLine(p1, p2, rayPaint);
      canvas.drawCircle(p2, 1.8 * (1 - progress).clamp(0.2, 1.0), rayPaint);
    }

    for (var i = 0; i < 8; i++) {
      final angle = ((pi * 2 / 8) * i) + (i.isEven ? 0.14 : -0.12);
      final radius = 10 + (34 * progress);
      final center = Offset(c.dx + cos(angle) * radius, c.dy + sin(angle) * radius);
      final fragW = 3.6 + (2.2 * (1 - progress));
      final fragH = 7.2 + (3.8 * (1 - progress));
      final rect = Rect.fromCenter(center: center, width: fragW, height: fragH);
      final fragPaint = Paint()
        ..color = Color.lerp(color, Colors.white, 0.16)!.withOpacity((0.95 - progress).clamp(0.0, 0.95));
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle + progress);
      canvas.translate(-center.dx, -center.dy);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2.2)), fragPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BurstPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _UserDoc {
  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> data;
  _UserDoc(this.ref, this.data);
}

class _RecorderOption {
  final Codec codec;
  final String ext;
  const _RecorderOption(this.codec, this.ext);
}
