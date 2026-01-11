import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class HeaderWidget extends StatefulWidget {
  final bool isDark;
  final Color textColor;
  final VoidCallback onSOSPressed;

  const HeaderWidget({
    super.key,
    required this.isDark,
    required this.textColor,
    required this.onSOSPressed,
  });

  @override
  State<HeaderWidget> createState() => _HeaderWidgetState();
}

class _HeaderWidgetState extends State<HeaderWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ------------------ IMAGE ------------------
  final ImagePicker _picker = ImagePicker();
  File? _localImageFile;

  // ------------------ FIREBASE ------------------
  String? _collection;
  Stream<DocumentSnapshot>? _userStream;
  StreamSubscription<User?>? _authSub;

  // ------------------ TIMERS ------------------
  Timer? _syncTimer;
  Timer? _clockTimer;

  // ------------------ STATES ------------------
  bool _isConnected = false;
  bool _isInForeground = true;
  bool _isUploading = false;
  bool _isSyncing = false;
  bool _isCertified = false;

  // ------------------ UI DATA ------------------
  late String _dateString;
  late String _greeting;
  String _userName = 'Utilisateur';

  late AnimationController _pulseController;

  // ================== INIT ==================
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeDateFormatting('fr_FR');

    _initAuthListener();
    _initAnimations();
    _initTimers();
    _updateDateTime();
    _loadCollectionAndSetupStream();
  }

  // ================== DISPOSE ==================
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _syncTimer?.cancel();
    _clockTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ================== LIFECYCLE ==================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isInForeground = state == AppLifecycleState.resumed;
      if (_isInForeground) _updateDateTime();
    });
  }

  // ================== INIT HELPERS ==================
  void _initAuthListener() {
    _isConnected = FirebaseAuth.instance.currentUser != null;

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      setState(() {
        _isConnected = user != null;
        if (_isConnected) _loadCollectionAndSetupStream();
      });
    });
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
  }

  void _initTimers() {
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      setState(() => _isSyncing = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _isSyncing = false);
      });
    });

    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) _updateDateTime();
    });
  }

  // ================== DATA ==================
  Future<void> _loadCollectionAndSetupStream() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // utilisation d'une collection par défaut si la préférence n'existe pas
      final col = prefs.getString('user_collection') ?? 'users';
      setState(() {
        _collection = col;
        _userStream = FirebaseFirestore.instance
            .collection(_collection!)
            .doc(user.uid)
            .snapshots();
      });
    }
  }

  void _updateDateTime() {
    final now = DateTime.now();
    final formatted =
        DateFormat('EEEE dd MMMM', 'fr_FR').format(now);
    _dateString =
        formatted[0].toUpperCase() + formatted.substring(1);

    final hour = now.hour;
    _greeting = hour < 12
        ? "Bonjour"
        : hour < 18
            ? "Bon après-midi"
            : "Bonsoir";
  }

  // ================== IMAGE ==================
  Future<void> _pickImage() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Connexion requise")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor:
          widget.isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF00CBA9)),
              title: Text('Galerie', style: TextStyle(color: widget.textColor)),
              onTap: () => _handleImage(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF00CBA9)),
              title: Text('Appareil Photo', style: TextStyle(color: widget.textColor)),
              onTap: () => _handleImage(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImage(ImageSource source) async {
    Navigator.pop(context);
    final image = await _picker.pickImage(source: source, imageQuality: 70);
    if (image == null) return;

    final file = File(image.path);
    setState(() {
      _localImageFile = file;
      _isUploading = true;
    });

    await _uploadImage(file);
  }

  Future<void> _uploadImage(File file) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _collection == null) return;

      final ref = FirebaseStorage.instance
          .ref('users/${user.uid}/profile.jpg');

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection(_collection!)
          .doc(user.uid)
          .update({'photoUrl': url});
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ================== HELPERS ==================
  String _displayName(Map<String, dynamic>? data) {
    // Si pas de data, fallback sur displayName du user Firebase
    if (data == null) {
      final user = FirebaseAuth.instance.currentUser;
      final dn = user?.displayName;
      if (dn != null && dn.trim().isNotEmpty) return dn.split(' ').first;
      final mail = user?.email;
      if (mail != null && mail.trim().isNotEmpty) return _nameFromEmail(mail);
      return 'Utilisateur';
    }

    // Clés possibles pour prénom / nom
    final keysFirst = ['firstName', 'firstname', 'prenom', 'givenName', 'given_name'];
    final keysLast = ['lastName', 'lastname', 'nom', 'familyName', 'family_name'];

    String? first;
    String? last;

    for (var k in keysFirst) {
      if (data[k]?.toString().trim().isNotEmpty == true) {
        first = data[k].toString().trim();
        break;
      }
    }
    for (var k in keysLast) {
      if (data[k]?.toString().trim().isNotEmpty == true) {
        last = data[k].toString().trim();
        break;
      }
    }

    if (first != null && last != null) return '$first $last';
    if (first != null) return first;
    if (last != null) return last;

    // Champs alternatifs
    for (var k in ['name', 'displayName', 'fullName', 'fullname']) {
      if (data[k]?.toString().trim().isNotEmpty == true) {
        return data[k].toString().split(' ').first;
      }
    }

    // Enfin fallback sur displayName Firebase
    final dn = FirebaseAuth.instance.currentUser?.displayName;
    if (dn != null && dn.trim().isNotEmpty) return dn.split(' ').first;

    // try to extract a readable name from email as last resort
    final mail = FirebaseAuth.instance.currentUser?.email;
    if (mail != null && mail.trim().isNotEmpty) return _nameFromEmail(mail);

    return 'Utilisateur';
  }

  String _nameFromEmail(String email) {
    try {
      final local = email.split('@').first;
      final cleaned = local.replaceAll(RegExp(r'[._\-]'), ' ').trim();
      if (cleaned.isEmpty) return 'Utilisateur';
      final parts = cleaned.split(RegExp(r'\s+'));
      final first = parts.first;
      return first[0].toUpperCase() + (first.length > 1 ? first.substring(1) : '');
    } catch (e) {
      return 'Utilisateur';
    }
  }

  Color _borderColor() {
    if (!_isConnected) return Colors.red;
    if (_isInForeground) return Colors.green;
    return Colors.orange;
  }

  // ================== BUILD ==================
  @override
  Widget build(BuildContext context) {
    if (_userStream == null) {
      // si pas de stream, tenter d'afficher le displayName Firebase si disponible
      final authName = FirebaseAuth.instance.currentUser?.displayName;
      if (authName != null && authName.trim().isNotEmpty) {
        _userName = authName.split(' ').first;
      }
      return _buildHeader(null);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: _userStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          return _buildHeader(null);
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        debugPrint("USER DATA = $data");
        _isCertified = data?['isCertified'] == true;
        _userName = _displayName(data);

        return _buildHeader(data);
      },
    );
  }

  Widget _buildHeader(Map<String, dynamic>? data) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              _buildAvatar(data),
              const SizedBox(width: 12),
              Expanded(child: _buildInfo()),
            ],
          ),
        ),
        _buildSOS(),
      ],
    );
  }

  Widget _buildAvatar(Map<String, dynamic>? data) {
    final image = _localImageFile != null
        ? FileImage(_localImageFile!)
        : data?['photoUrl'] != null
            ? NetworkImage(data!['photoUrl'])
            : const NetworkImage('https://i.pravatar.cc/150?img=3');

    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _borderColor(), width: 2),
            ),
            child: CircleAvatar(
              radius: 26,
              backgroundImage: image as ImageProvider,
              child: _isUploading
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : null,
            ),
          ),
          const CircleAvatar(
            radius: 10,
            backgroundColor: Color(0xFF00CBA9),
            child: Icon(Icons.edit, size: 10, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitle(),
        Row(
          children: [
            Text(
              "$_greeting, $_userName",
              style: TextStyle(
                color: widget.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            if (_isCertified)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.verified,
                  color: Colors.blue,
                  size: 16,
                ),
              ),
          ],
        ),
        Text(
          _dateString,
          style: TextStyle(
            fontSize: 12,
            color: widget.isDark ? Colors.white60 : Colors.black45,
          ),
        ),
      ],
    );
  }

  Widget _buildTitle() {
    return FadeTransition(
      opacity: Tween(begin: 0.5, end: 1.0).animate(_pulseController),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isSyncing ? Colors.orange : const Color(0xFF00CBA9),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _isSyncing ? "SYNCHRONISATION..." : "LUALABACONNECT",
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: _isSyncing ? Colors.orange : const Color(0xFF00CBA9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSOS() {
    return GestureDetector(
      onTap: widget.onSOSPressed,
      child: ScaleTransition(
        scale: Tween(begin: 1.0, end: 1.1).animate(_pulseController),
        child: const CircleAvatar(
          radius: 24,
          backgroundColor: Color(0xFFD32F2F),
          child: Text("SOS",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
