import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lualaba_konnect/shared/widgets/account_badge.dart';
import 'package:url_launcher/url_launcher.dart';


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

  // Nouveaux : timer de revalidation
  Timer? _userRefreshTimer;

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

  Future<void> _updateLocalCache(String name, String? photoUrl, bool certified, {String? collection}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_display_name', name);
      await prefs.setBool('user_is_certified', certified);
      if (collection != null && collection.isNotEmpty) {
        await prefs.setString('user_collection', collection);
      }
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
              await _updateLocalCache(first, null, _isCertified, collection: _collection);
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
          // Tenter de recharger le cache local (au cas où _fetchAndCache a écrit)
          if (mounted) {
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

    // Rechercher la collection active (priorité: enterprise > pro > classic > users)
    // Même si un cache existe, on vérifie pour éviter les collections obsolètes.
    final collections = ['enterprise_users', 'pro_users', 'classic_users', 'users'];
    for (String col in collections) {
      try {
        final doc = await FirebaseFirestore.instance.collection(col).doc(uid).get();
        if (doc.exists) {
          if (_collection != col) {
            _collection = col;
            await prefs.setString('user_collection', col);
          }
          break;
        }
      } catch (e) {
        debugPrint('[DEBUG] chercher collection $col erreur: $e');
      }
    }

    // si on a trouvé une collection, on s'abonne au document (Stream)
    if (_collection != null && mounted) {
      setState(() {
        _userStream = FirebaseFirestore.instance.collection(_collection!).doc(uid).snapshots();
      });
    }
  }

  // ================== ACTIONS IMAGES ==================
  String _appendUrlVersion(String url, int version) {
    if (url.isEmpty) return url;
    return url.contains('?') ? '$url&v=$version' : '$url?v=$version';
  }

  void _showPhotoUpdatedToast() {
    if (!mounted) return;
    final overlay = Overlay.of(context);

    late OverlayEntry entry;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 300),
    );
    final animation = CurvedAnimation(parent: controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInOutCubic);
    final scaleAnimation = Tween<double>(begin: 0.955, end: 1.0).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInOutCubic),
    );

    entry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          left: 16,
          right: 16,
          bottom: 18,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(animation),
              child: ScaleTransition(
                scale: scaleAnimation,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF8A00),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFFB14D)),
                        boxShadow: const [
                          BoxShadow(color: Color(0x66FF8A00), blurRadius: 18, offset: Offset(0, 10)),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Photo de profil mise à jour',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    controller.forward();
    Future.delayed(const Duration(milliseconds: 2000), () async {
      if (!mounted) return;
      await controller.reverse();
      entry.remove();
      controller.dispose();
    });
  }

  void _showCustomToast(String message) {
    if (!mounted) return;
    final overlay = Overlay.of(context);

    late OverlayEntry entry;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 300),
    );
    final animation = CurvedAnimation(parent: controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInOutCubic);
    final scaleAnimation = Tween<double>(begin: 0.955, end: 1.0).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInOutCubic),
    );

    entry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          left: 16,
          right: 16,
          bottom: 18,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(animation),
              child: ScaleTransition(
                scale: scaleAnimation,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF8A00),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFFB14D)),
                        boxShadow: const [
                          BoxShadow(color: Color(0x66FF8A00), blurRadius: 18, offset: Offset(0, 10)),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    controller.forward();
    Future.delayed(const Duration(milliseconds: 2000), () async {
      if (!mounted) return;
      await controller.reverse();
      entry.remove();
      controller.dispose();
    });
  }

Future<void> _handleImageUpload(ImageSource source) async {
  final XFile? image = await _picker.pickImage(
    source: source,
    imageQuality: 70,
  );
  if (image == null || _collection == null) return;

  setState(() => _isUploading = true);

  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final bytes = await image.readAsBytes();
    final filePath = 'users/${user.uid}.jpg';

    // 🔥 UPLOAD SUPABASE
    await Supabase.instance.client.storage
        .from('profiles')
        .uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    // 🔗 URL PUBLIQUE SUPABASE
    final publicUrl = Supabase.instance.client.storage
        .from('profiles')
        .getPublicUrl(filePath);
    final versionedUrl = _appendUrlVersion(publicUrl, DateTime.now().millisecondsSinceEpoch);

    // 📝 UPDATE FIRESTORE AVEC L’URL SUPABASE
    await FirebaseFirestore.instance
        .collection(_collection!)
        .doc(user.uid)
        .update({
          'photoUrl': versionedUrl,
        });

    if (mounted) {
      setState(() => _cachedPhotoUrl = versionedUrl);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCustomToast('Photo de profil mise a jour');
      });
    }

    // UI mise à jour automatiquement via StreamBuilder
  } catch (e) {
    debugPrint('❌ Erreur upload Supabase: $e');
  } finally {
    if (mounted) setState(() => _isUploading = false);
  }
}

  Future<void> _viewPhoto() async {
    if (_cachedPhotoUrl == null || _cachedPhotoUrl!.isEmpty) {
      _showCustomToast('Aucune photo de profil');
      return;
    }
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(
            imageUrl: _cachedPhotoUrl!,
            cacheManager: ProfileCacheManager.instance,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Future<void> _downloadPhoto() async {
    if (_cachedPhotoUrl == null || _cachedPhotoUrl!.isEmpty) {
      _showCustomToast('Aucune photo de profil');
      return;
    }
    final uri = Uri.tryParse(_cachedPhotoUrl!);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _deletePhoto() async {
    if (_collection == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _isUploading = true);
    try {
      final filePath = 'users/${user.uid}.jpg';
      await Supabase.instance.client.storage.from('profiles').remove([filePath]);
      await FirebaseFirestore.instance.collection(_collection!).doc(user.uid).update({'photoUrl': ''});
      if (mounted) {
        setState(() => _cachedPhotoUrl = '');
        _showCustomToast('Photo supprimee');
      }
    } catch (e) {
      debugPrint('❌ Erreur suppression photo: $e');
      if (mounted) _showCustomToast('Erreur suppression photo');
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
        // Appliquer chaque mise à jour Firestore (temps réel)
        if (snapshot.hasData && snapshot.data!.exists) {
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

            // Appliquer la mise à jour hors-build pour éviter setState pendant le build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final nextName = fetchedName.isNotEmpty ? fetchedName : _userName;
              final nextPhoto = fetchedPhoto ?? _cachedPhotoUrl;
              final needsUpdate = nextName != _userName || nextPhoto != _cachedPhotoUrl || fetchedCert != _isCertified;
              if (needsUpdate) {
                setState(() {
                  _userName = nextName;
                  _cachedPhotoUrl = nextPhoto;
                  _isCertified = fetchedCert;
                });
              }
            });

            // Mettre à jour le cache local de façon asynchrone (sans bloquer)
            _updateLocalCache(
              fetchedName.isNotEmpty ? fetchedName : _userName,
              fetchedPhoto,
              fetchedCert,
              collection: _collection,
            );
          } catch (e) {
            debugPrint('[DEBUG] erreur traitement snapshot: $e');
          }
        }

        return _buildHeaderContent();
      },
    );
  }

  Widget _buildHeaderContent() {
    debugPrint('[HeaderWidget] render name=$_userName cert=$_isCertified collection=$_collection');
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
                  if (_isCertified || _collection == 'pro_users' || _collection == 'enterprise_users') ...[
                    const SizedBox(width: 4),
                    AccountBadges(isCertified: _isCertified, accountType: _collection, fontSize: 11),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white70 : Colors.black54;
    final hasPhoto = _cachedPhotoUrl != null && _cachedPhotoUrl!.isNotEmpty;
    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.remove_red_eye_outlined, color: sub),
              title: Text('Voir la photo', style: TextStyle(color: textColor)),
              onTap: hasPhoto ? () => {Navigator.pop(context), _viewPhoto()} : null,
            ),
            ListTile(
              leading: Icon(Icons.download, color: sub),
              title: Text('Telecharger la photo', style: TextStyle(color: textColor)),
              onTap: hasPhoto ? () => {Navigator.pop(context), _downloadPhoto()} : null,
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: sub),
              title: Text('Galerie', style: TextStyle(color: textColor)),
              onTap: () => {Navigator.pop(context), _handleImageUpload(ImageSource.gallery)},
            ),
            ListTile(
              leading: Icon(Icons.camera_alt, color: sub),
              title: Text('Appareil Photo', style: TextStyle(color: textColor)),
              onTap: () => {Navigator.pop(context), _handleImageUpload(ImageSource.camera)},
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text('Supprimer la photo', style: TextStyle(color: textColor)),
              onTap: hasPhoto ? () => {Navigator.pop(context), _deletePhoto()} : null,
            ),
          ],
        ),
      ),
    );
  }
}
