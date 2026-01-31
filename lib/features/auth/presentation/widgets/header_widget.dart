import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

/// --- CONFIGURATION DU CACHE DES IMAGES (30 JOURS) ---
class ProfileCacheManager {
  static const key = 'userProfileCache';
  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 30), // Durée de rétention
      maxNrOfCacheObjects: 50,
    ),
  );
}

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // États de données (Initialisés avec le cache plus tard)
  String _userName = '...';
  String? _cachedPhotoUrl;
  bool _isCertified = false;
  String? _collection;

  // États UI
  bool _isConnected = false;
  bool _isUploading = false;
  final bool _isSyncing = false;
  late String _dateString;

  // Firebase & Timers
  Stream<DocumentSnapshot>? _userStream;
  Timer? _clockTimer;
  late AnimationController _pulseController;
  final ImagePicker _picker = ImagePicker();

  // Nouveaux : timer de revalidation et flag pour éviter multiples updates
  Timer? _userRefreshTimer;
  bool _hasUpdatedFromFirestore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeDateFormatting('fr_FR');
    _updateDateTime();
    _initAnimations();

    // 1) Charger le cache local immédiatement (affichage instantané)
    // 2) Puis initialiser l'écoute de l'auth (qui lancera la souscription Firestore)
    _loadLocalCache().then((_) => _initAuthListener());

    // Timer pour mettre à jour l'horloge toutes les minutes
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) => _updateDateTime());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _pulseController.dispose();
    _userRefreshTimer?.cancel();
    super.dispose();
  }

  // ================== GESTION DU CACHE LOCAL ==================

  Future<void> _loadLocalCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        // Utilise 'Utilisateur' si rien en cache (afin d'avoir toujours quelque chose)
        _userName = prefs.getString('user_display_name') ?? 'Utilisateur';
        _cachedPhotoUrl = prefs.getString('user_photoUrl');
        _collection = prefs.getString('user_collection');
        _isCertified = prefs.getBool('user_is_certified') ?? false;
      });
    }
  }

  Future<void> _updateLocalCache(String name, String? photoUrl, bool certified) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_display_name', name);
      await prefs.setBool('user_is_certified', certified);
      if (photoUrl != null && photoUrl.isNotEmpty) await prefs.setString('user_photoUrl', photoUrl);
    } catch (e) {
      // ignore les erreurs de sauvegarde silencieusement, mais log pour debug
      debugPrint('[DEBUG] _updateLocalCache error: $e');
    }
  }

  // ================== LOGIQUE FIREBASE ==================

  void _initAuthListener() {
    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (!mounted) return;
      setState(() => _isConnected = user != null);

      if (user != null) {
        // 1) Affichage immédiat depuis FirebaseAuth.displayName si disponible
        try {
          final displayFromAuth = user.displayName;
          if (displayFromAuth != null && displayFromAuth.trim().isNotEmpty) {
            final first = displayFromAuth.trim().split(RegExp(r'\s+')).first;
            // Mettre à jour seulement si on a une valeur par défaut ou différente
            if (_userName == 'Utilisateur' || _userName != first) {
              setState(() {
                _userName = first;
              });
              // mettre à jour cache local pour la prochaine fois
              await _updateLocalCache(first, null, _isCertified);
            }
          }
        } catch (e) {
          debugPrint('[DEBUG] displayName fallback error: $e');
        }

        // 2) Prépare la souscription Firestore (cherche la collection si nécessaire)
        await _setupUserStream(user.uid);

        // 3) Met en place une revalidation légère toutes les 10s si Firestore tarde
        _userRefreshTimer?.cancel();
        _userRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
          // Si nous n'avons pas encore mis à jour depuis Firestore, réessaye de charger cache/stream
          if (!_hasUpdatedFromFirestore && mounted) {
            // Tenter de recharger le cache local (au cas où _fetchAndCache a écrit)
            try {
              final prefs = await SharedPreferences.getInstance();
              final cachedName = prefs.getString('user_display_name');
              if (cachedName != null && cachedName.isNotEmpty && cachedName != _userName) {
                setState(() => _userName = cachedName);
              }
            } catch (e) {
              debugPrint('[DEBUG] userRefreshTimer error: $e');
            }
          }
        });
      } else {
        // utilisateur déconnecté : annuler timer
        _userRefreshTimer?.cancel();
      }
    });
  }

  Future<void> _setupUserStream(String uid) async {
    final prefs = await SharedPreferences.getInstance();

    // Si on n'a pas la collection en cache, on la cherche
    if (_collection == null || _collection!.isEmpty) {
      final collections = ['classic_users', 'pro_users', 'enterprise_users'];
      for (String col in collections) {
        try {
          final doc = await FirebaseFirestore.instance.collection(col).doc(uid).get();
          if (doc.exists) {
            _collection = col;
            await prefs.setString('user_collection', col);
            break;
          }
        } catch (e) {
          debugPrint('[DEBUG] chercher collection $col erreur: $e');
        }
      }
    }

    // si on a trouvé une collection, on s'abonne au document (Stream)
    if (_collection != null && mounted) {
      setState(() {
        _userStream = FirebaseFirestore.instance.collection(_collection!).doc(uid).snapshots();
        // reset flag pour accepter la prochaine update Firestore
        _hasUpdatedFromFirestore = false;
      });
    }
  }

  // ================== ACTIONS IMAGES ==================

  Future<void> _handleImageUpload(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source, imageQuality: 70);
    if (image == null || _collection == null) return;

    setState(() => _isUploading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final bytes = await image.readAsBytes();
      final ref = FirebaseStorage.instance.ref('profiles/${user.uid}.jpg');

      await ref.putData(bytes);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection(_collection!).doc(user.uid).update({'photoUrl': url});
      // on mettra à jour l'UI via le StreamBuilder quand Firestore notifie
    } catch (e) {
      debugPrint("Erreur upload: $e");
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ================== INTERFACE (BUILD) ==================

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _userStream,
      builder: (context, snapshot) {
        // Si Firestore a envoyé des données et qu'on ne les a pas encore appliquées
        if (snapshot.hasData && snapshot.data!.exists && !_hasUpdatedFromFirestore) {
          try {
            final data = snapshot.data!.data() as Map<String, dynamic>;

            // Extraction robuste du prénom (plusieurs clés possibles)
            final String fetchedName = (data['firstName'] ??
                    data['firstname'] ??
                    data['prenom'] ??
                    data['name'] ??
                    _userName)
                .toString()
                .trim()
                .split(RegExp(r'\s+'))
                .first;

            final String? fetchedPhoto = (data['photoUrl'] != null && data['photoUrl'].toString().isNotEmpty)
                ? data['photoUrl'].toString()
                : null;
            final bool fetchedCert = data['isCertified'] == true;

            // Marquer qu'on a bien appliqué la mise à jour Firestore (évite boucles)
            _hasUpdatedFromFirestore = true;

            // Appliquer la mise à jour hors-build pour éviter setState pendant le build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _userName = fetchedName.isNotEmpty ? fetchedName : _userName;
                _cachedPhotoUrl = fetchedPhoto ?? _cachedPhotoUrl;
                _isCertified = fetchedCert;
              });
            });

            // Mettre à jour le cache local de façon asynchrone (sans bloquer)
            _updateLocalCache(fetchedName.isNotEmpty ? fetchedName : _userName, fetchedPhoto, fetchedCert);
          } catch (e) {
            debugPrint('[DEBUG] erreur traitement snapshot: $e');
          }
        }

        return _buildHeaderContent();
      },
    );
  }

  Widget _buildHeaderContent() {
    return Row(
      children: [
        _buildAvatar(),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildBranding(),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _userName,
                      style: TextStyle(color: widget.textColor, fontWeight: FontWeight.bold, fontSize: 17),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_isCertified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, color: Colors.blue, size: 16),
                  ],
                ],
              ),
              Text(_dateString, style: TextStyle(fontSize: 12, color: widget.isDark ? Colors.white60 : Colors.black45)),
            ],
          ),
        ),
        _buildSOS(),
      ],
    );
  }

  Widget _buildAvatar() {
    return GestureDetector(
      onTap: () => _showPickerMenu(),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _isConnected ? Colors.green : Colors.red, width: 2),
            ),
            child: CircleAvatar(
              radius: 26,
              backgroundColor: Colors.grey[200],
              child: ClipOval(
                child: _cachedPhotoUrl != null && _cachedPhotoUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: _cachedPhotoUrl!,
                        cacheManager: ProfileCacheManager.instance,
                        fit: BoxFit.cover,
                        width: 52,
                        height: 52,
                        placeholder: (context, url) => _isUploading ? CircularProgressIndicator(strokeWidth: 2, color: Colors.orange) : const Icon(Icons.person),
                        errorWidget: (context, url, error) => const Icon(Icons.person, size: 30, color: Colors.grey),
                      )
                    : const Icon(Icons.person, size: 30, color: Colors.grey),
              ),
            ),
          ),
          const CircleAvatar(
            radius: 9,
            backgroundColor: Color(0xFF00CBA9),
            child: Icon(Icons.edit, size: 10, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildBranding() {
    return FadeTransition(
      opacity: _pulseController,
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00CBA9))),
          const SizedBox(width: 6),
          const Text("LBKONNECT", style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Color(0xFF00CBA9))),
        ],
      ),
    );
  }

Widget _buildSOS() {
    return GestureDetector(
      onTap: widget.onSOSPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: const Text("SOS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ),
    );
  }

  // ================== HELPERS UI ==================

  void _updateDateTime() {
    final now = DateTime.now();
    final formatted = DateFormat('EEEE dd MMMM', 'fr_FR').format(now);
    if (mounted) {
      setState(() => _dateString = formatted[0].toUpperCase() + formatted.substring(1));
    }
  }

  void _initAnimations() {
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  void _showPickerMenu() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galerie'), onTap: () => {Navigator.pop(context), _handleImageUpload(ImageSource.gallery)}),
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Appareil Photo'), onTap: () => {Navigator.pop(context), _handleImageUpload(ImageSource.camera)}),
          ],
        ),
      ),
    );
  }
}
