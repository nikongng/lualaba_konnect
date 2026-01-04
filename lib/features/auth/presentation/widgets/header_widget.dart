import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:io';
import 'dart:async';

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

class _HeaderWidgetState extends State<HeaderWidget> with SingleTickerProviderStateMixin {
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  static const String _storageKey = "user_profile_image_path";
  Timer? _syncTimer;
  
  late String _dateString;
  late String _greeting;
  late AnimationController _pulseController;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null);
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (timer) {  });
    _updateDateTime();
    _loadSavedImage();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        setState(() => _isSyncing = true);
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _isSyncing = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
    _syncTimer?.cancel();
  }

  Future<void> _loadSavedImage() async {
    final prefs = await SharedPreferences.getInstance();
    final String? path = prefs.getString(_storageKey);
    if (path != null && File(path).existsSync()) {
      setState(() => _imageFile = File(path));
    }
  }

  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: widget.isDark ? const Color(0xFF1A1A1A) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF00CBA9)),
              title: Text('Galerie', style: TextStyle(color: widget.textColor)),
              onTap: () => _handleImageSelection(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF00CBA9)),
              title: Text('Appareil Photo', style: TextStyle(color: widget.textColor)),
              onTap: () => _handleImageSelection(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImageSelection(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, image.path);
      setState(() => _imageFile = File(image.path));
    }
    if (mounted) Navigator.pop(context);
  }

  void _updateDateTime() {
    final now = DateTime.now();
    _dateString = DateFormat('EEEE dd MMMM', 'fr_FR').format(now);
    _dateString = _dateString[0].toUpperCase() + _dateString.substring(1);

    int hour = now.hour;
    if (hour < 12) _greeting = "Bonjour";
    else if (hour < 18) _greeting = "Bon après-midi";
    else _greeting = "Bonsoir";
  }

  @override
  Widget build(BuildContext context) {
    _updateDateTime();

    return Row(
      children: [
        // Partie gauche : Avatar + Infos (Flexible pour s'adapter à l'écran)
        Expanded(
          child: Row(
            children: [
              _buildAvatar(),
              const SizedBox(width: 12),
              // Expanded ici pour que la colonne de texte ne pousse pas le bouton SOS hors écran
              Expanded(
                child: _buildInfoColumn(), 
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _buildSOSButton(),
      ],
    );
  }

  Widget _buildAvatar() {
    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF00CBA9).withOpacity(0.5), width: 2),
            ),
            child: CircleAvatar(
              radius: 26, // Taille légèrement réduite pour plus d'élégance
              backgroundColor: widget.isDark ? Colors.grey[900] : Colors.grey[200],
              backgroundImage: _imageFile != null 
                  ? FileImage(_imageFile!) as ImageProvider
                  : const NetworkImage('https://i.pravatar.cc/150?img=3'),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Color(0xFF00CBA9), shape: BoxShape.circle),
            child: const Icon(Icons.edit, color: Colors.white, size: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // S'adapte à la taille du contenu
      children: [
        _buildDynamicTitle(),
        const SizedBox(height: 2),
        Text(
          "$_greeting, Ir Punga",
          style: TextStyle(
            color: widget.textColor, 
            fontSize: 16, // Taille réduite pour un meilleur rendu
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis, // Ajoute "..." si le texte est trop long
          maxLines: 1,
        ),
        Text(
          _dateString,
          style: TextStyle(
            color: widget.isDark ? Colors.white60 : Colors.black45, 
            fontSize: 12, // Taille réduite
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }

  Widget _buildDynamicTitle() {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.5, end: 1.0).animate(_pulseController),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isSyncing ? Colors.orange : const Color(0xFF00CBA9),
            ),
          ),
          const SizedBox(width: 6),
          Flexible( // Permet au titre de se réduire si nécessaire
            child: Text(
              _isSyncing ? "SYNCHRONISATION..." : "LUALABACONNECT",
              style: TextStyle(
                color: _isSyncing ? Colors.orange : const Color(0xFF00CBA9),
                fontSize: 9, // Légèrement réduit
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSOSButton() {
    return GestureDetector(
      onTap: widget.onSOSPressed,
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 1.1).animate(
          CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
        ),
        child: Container(
          height: 48, width: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFD32F2F),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: const Color(0xFFD32F2F).withOpacity(0.3), blurRadius: 8, spreadRadius: 1),
            ],
          ),
          child: const Center(
            child: Text("SOS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ),
      ),
    );
  }
}