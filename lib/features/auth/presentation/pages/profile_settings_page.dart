import 'dart:io';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lualaba_konnect/core/supabase_service.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'package:lualaba_konnect/core/theme_controller.dart';
import 'package:lualaba_konnect/core/auth_error_messages.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  bool _settingsLoaded = false;
  bool _notificationsEnabled = true;
  bool _mediaWifiOnly = false;
  String _mediaDownloadPref = 'ask';
  String _chatTheme = 'system';
  bool _showPhoneToContacts = true;
  bool _showOnlinePresence = true;
  bool _showProfilePhotos = true;
  bool _showBio = true;
  bool _showStatus = true;

  DocumentReference<Map<String, dynamic>>? _userRef;
  Map<String, dynamic> _userData = <String, dynamic>{};
  String _userCollection = '';

  String? _photoUrl;
  String _email = '';
  int? _profileType;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _genderCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();
  final _nationalityCtrl = TextEditingController();
  final _professionCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController();
  final _currentCompanyCtrl = TextEditingController();
  final _rccmCtrl = TextEditingController();
  final _idNatCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _bioCtrl.dispose();
    _emailCtrl.dispose();
    _genderCtrl.dispose();
    _birthDateCtrl.dispose();
    _nationalityCtrl.dispose();
    _professionCtrl.dispose();
    _experienceCtrl.dispose();
    _currentCompanyCtrl.dispose();
    _rccmCtrl.dispose();
    _idNatCtrl.dispose();
    super.dispose();
  }

  bool _isDark() => Theme.of(context).brightness == Brightness.dark;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : Colors.black87,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _safeStr(dynamic v) => (v ?? '').toString().trim();

  Future<void> _load() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    _email = _safeStr(u.email);
    _emailCtrl.text = _email;

    try {
      await _loadSettings();
      final prefs = await SharedPreferences.getInstance();
      final preferred = _safeStr(prefs.getString('user_collection'));
      final cols = <String>{
        if (preferred.isNotEmpty) preferred,
        'classic_users',
        'pro_users',
        'enterprise_users',
        'users',
      }.toList();

      DocumentSnapshot<Map<String, dynamic>>? found;
      String foundCol = '';

      for (final col in cols) {
        try {
          final snap = await FirebaseFirestore.instance.collection(col).doc(u.uid).get();
          if (snap.exists) {
            found = snap;
            foundCol = col;
            break;
          }
        } catch (_) {}
      }

      if (found == null || !found.exists) {
        if (mounted) setState(() => _loading = false);
        _snack('Profil introuvable.', error: true);
        return;
      }

      _userRef = found.reference;
      _userData = found.data() ?? <String, dynamic>{};
      _userCollection = foundCol;
      _profileType = _userData['profileType'] is int ? _userData['profileType'] as int : null;

      _photoUrl = _safeStr(_userData['photoUrl']);
      if (_photoUrl == null || _photoUrl!.isEmpty) {
        _photoUrl = _safeStr(_userData['photo']);
      }
      if (_photoUrl == null || _photoUrl!.isEmpty) {
        _photoUrl = _safeStr(u.photoURL);
      }

      _firstNameCtrl.text = _safeStr(_userData['firstName']);
      _lastNameCtrl.text = _safeStr(_userData['lastName']);
      _phoneCtrl.text = _safeStr(_userData['phone']);
      _addressCtrl.text = _safeStr(_userData['address']);
      _bioCtrl.text = _safeStr(_userData['bio']);
      _genderCtrl.text = _safeStr(_userData['genre']);
      _birthDateCtrl.text = _safeStr(_userData['birthDate']);
      _nationalityCtrl.text = _safeStr(_userData['nationality']);
      _professionCtrl.text = _safeStr(_userData['profession']);
      _experienceCtrl.text = _safeStr(_userData['experience']);
      _currentCompanyCtrl.text = _safeStr(_userData['currentCompany']);
      _rccmCtrl.text = _safeStr(_userData['rccm']);
      _idNatCtrl.text = _safeStr(_userData['idNat']);

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _snack('Erreur chargement profil: $e', error: true);
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _mediaWifiOnly = prefs.getBool('media_download_wifi_only') ?? false;
      _mediaDownloadPref = prefs.getString('media_download_pref') ?? 'ask';
      _chatTheme = prefs.getString('chat_theme') ?? 'system';
      _showPhoneToContacts = prefs.getBool('show_phone_to_contacts') ?? true;
      _showOnlinePresence = prefs.getBool('show_online_presence') ?? true;
      _showProfilePhotos = prefs.getBool('show_profile_photos') ?? true;
      _showBio = prefs.getBool('show_bio') ?? true;
      _showStatus = prefs.getBool('show_status') ?? true;
    } catch (_) {}
    _settingsLoaded = true;
  }

  String _displayNamePreview() {
    final fn = _safeStr(_firstNameCtrl.text);
    final ln = _safeStr(_lastNameCtrl.text);
    final full = ('$fn $ln').trim();
    return full.isNotEmpty ? full : (_email.isNotEmpty ? _email : 'Utilisateur');
  }

  String _accountTypeLabel() {
    if (_profileType == 1 || _userCollection == 'pro_users') return 'Pro';
    if (_profileType == 2 || _userCollection == 'enterprise_users') return 'Entreprise';
    return 'Classique';
  }

  bool get _isPro =>
      _profileType == 1 ||
      _userCollection == 'pro_users';

  bool get _isEnterprise =>
      _profileType == 2 ||
      _userCollection == 'enterprise_users';

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    DateTime? initial;
    try {
      if (_birthDateCtrl.text.trim().isNotEmpty) {
        initial = DateTime.tryParse(_birthDateCtrl.text.trim());
      }
    } catch (_) {}
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1950, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null) {
      final y = picked.year.toString().padLeft(4, '0');
      final m = picked.month.toString().padLeft(2, '0');
      final d = picked.day.toString().padLeft(2, '0');
      _birthDateCtrl.text = '$y-$m-$d';
      if (mounted) setState(() {});
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    if (!SupabaseService.isInitialized) {
      _snack("Supabase n'est pas initialisé.", error: true);
      return;
    }

    XFile? picked;
    try {
      picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    } catch (e) {
      _snack('Impossible de choisir une photo: $e', error: true);
      return;
    }
    if (picked == null) return;

    setState(() => _uploadingPhoto = true);
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final objectPath = 'avatars/${u.uid}/$ts.jpg';
      const bucket = 'profiles';

      String url;
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        url = await SupabaseService.uploadBytesNamed(
          bytes,
          objectPath,
          bucket,
          contentType: 'image/jpeg',
        );
      } else {
        url = await SupabaseService.uploadFileNamed(
          File(picked.path),
          objectPath,
          bucket,
          contentType: 'image/jpeg',
        );
      }

      await FirebaseAuth.instance.currentUser?.updatePhotoURL(url);
      if (_userRef != null) {
        await _userRef!.set({'photoUrl': url}, SetOptions(merge: true));
      }

      if (!mounted) return;
      setState(() => _photoUrl = url);
      _snack('Photo de profil mise à jour.');
    } catch (e) {
      _snack('Erreur upload photo: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _save() async {
    if (_userRef == null) {
      _snack('Profil introuvable.', error: true);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    setState(() => _saving = true);
    try {
      final fn = _safeStr(_firstNameCtrl.text);
      final ln = _safeStr(_lastNameCtrl.text);
      final fullName = ('$fn $ln').trim();

      final update = <String, dynamic>{
        'firstName': fn,
        'lastName': ln,
        'phone': _safeStr(_phoneCtrl.text),
        'address': _safeStr(_addressCtrl.text),
        'bio': _safeStr(_bioCtrl.text),
        'genre': _safeStr(_genderCtrl.text),
        'birthDate': _safeStr(_birthDateCtrl.text),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_isPro || _isEnterprise) {
        update['nationality'] = _safeStr(_nationalityCtrl.text);
        update['profession'] = _safeStr(_professionCtrl.text);
        update['experience'] = _safeStr(_experienceCtrl.text);
        update['currentCompany'] = _safeStr(_currentCompanyCtrl.text);
      }
      if (_isEnterprise) {
        update['rccm'] = _safeStr(_rccmCtrl.text);
        update['idNat'] = _safeStr(_idNatCtrl.text);
      }
      if (_email.isNotEmpty) {
        update['email'] = _email;
      }

      await _userRef!.set(update, SetOptions(merge: true));
      if (fullName.isNotEmpty) {
        await u.updateDisplayName(fullName);
      }

      // Keep minimal cache up to date (used by dashboard/header in some places)
      try {
        final prefs = await SharedPreferences.getInstance();
        if (_userCollection.isNotEmpty) {
          await prefs.setString('user_collection', _userCollection);
        }
        if (fullName.isNotEmpty) {
          await prefs.setString('user_display_name', fullName);
          final initials = fullName
              .split(RegExp(r'\s+'))
              .where((p) => p.trim().isNotEmpty)
              .take(2)
              .map((p) => p.trim()[0].toUpperCase())
              .join();
          await prefs.setString('user_initials', initials.isEmpty ? 'U' : initials);
        }
      } catch (_) {}

      _snack('Profil mis à jour.');
    } catch (e) {
      _snack('Erreur sauvegarde: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark();
    final bg = isDark ? const Color(0xFF0F171A) : const Color(0xFFF7F8FA);
    final card = isDark ? Colors.white10 : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Profil', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: text),
        actions: [
          TextButton(
            onPressed: (_saving || _loading) ? null : _save,
            child: Text(_saving ? '...' : 'Enregistrer', style: TextStyle(color: _saving ? sub : const Color(0xFF00CBA9), fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor: Colors.black12,
                              backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty) ? NetworkImage(_photoUrl!) : null,
                              child: (_photoUrl == null || _photoUrl!.isEmpty)
                                  ? Text(
                                      _displayNamePreview().isNotEmpty ? _displayNamePreview()[0].toUpperCase() : 'U',
                                      style: TextStyle(color: text, fontSize: 22, fontWeight: FontWeight.w900),
                                    )
                                  : null,
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: InkWell(
                                onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF111B21) : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                                  ),
                                  child: _uploadingPhoto
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                      : Icon(Icons.camera_alt, size: 16, color: sub),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_displayNamePreview(), style: TextStyle(color: text, fontWeight: FontWeight.w900, fontSize: 16)),
                              const SizedBox(height: 4),
                              if (_email.isNotEmpty) Text(_email, style: TextStyle(color: sub, fontWeight: FontWeight.w600)),
                              if (_userCollection.isNotEmpty || _profileType != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00CBA9).withOpacity(isDark ? 0.12 : 0.10),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFF00CBA9).withOpacity(0.25)),
                                  ),
                                  child: Text(
                                    _accountTypeLabel(),
                                    style: const TextStyle(color: Color(0xFF00CBA9), fontSize: 12, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _field(
                            label: 'Prénom',
                            controller: _firstNameCtrl,
                            text: text,
                            isDark: isDark,
                            validator: (v) => _safeStr(v).isEmpty ? 'Entrer ton prénom' : null,
                          ),
                          const SizedBox(height: 12),
                          _field(
                            label: 'Nom',
                            controller: _lastNameCtrl,
                            text: text,
                            isDark: isDark,
                            validator: (v) => _safeStr(v).isEmpty ? 'Entrer ton nom' : null,
                          ),
                          const SizedBox(height: 12),
                          _field(
                            label: 'Téléphone',
                            controller: _phoneCtrl,
                            text: text,
                            isDark: isDark,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          _field(
                            label: 'Adresse',
                            controller: _addressCtrl,
                            text: text,
                            isDark: isDark,
                            keyboardType: TextInputType.streetAddress,
                          ),
                          const SizedBox(height: 12),
                          _field(
                            label: 'Email',
                            controller: _emailCtrl,
                            text: text,
                            isDark: isDark,
                            readOnly: true,
                          ),
                          const SizedBox(height: 12),
                          _field(
                            label: 'Genre',
                            controller: _genderCtrl,
                            text: text,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 12),
                          _field(
                            label: 'Date de naissance',
                            controller: _birthDateCtrl,
                            text: text,
                            isDark: isDark,
                            readOnly: true,
                            onTap: _pickBirthDate,
                          ),
                          const SizedBox(height: 12),
                          _field(
                            label: 'Bio',
                            controller: _bioCtrl,
                            text: text,
                            isDark: isDark,
                            maxLines: 3,
                          ),
                          if (_isPro || _isEnterprise) ...[
                            const SizedBox(height: 12),
                            _field(
                              label: 'Nationalité',
                              controller: _nationalityCtrl,
                              text: text,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 12),
                            _field(
                              label: 'Profession',
                              controller: _professionCtrl,
                              text: text,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 12),
                            _field(
                              label: 'Expérience',
                              controller: _experienceCtrl,
                              text: text,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 12),
                            _field(
                              label: 'Entreprise actuelle',
                              controller: _currentCompanyCtrl,
                              text: text,
                              isDark: isDark,
                            ),
                          ],
                          if (_isEnterprise) ...[
                            const SizedBox(height: 12),
                            _field(
                              label: 'RCCM',
                              controller: _rccmCtrl,
                              text: text,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 12),
                            _field(
                              label: 'ID.NAT',
                              controller: _idNatCtrl,
                              text: text,
                              isDark: isDark,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle('PARAMÈTRES'),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      children: [
                        _settingsSwitch(
                          label: 'Notifications',
                          value: _notificationsEnabled,
                          onChanged: (v) async {
                            setState(() => _notificationsEnabled = v);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('notifications_enabled', v);
                            await NotificationService.setEnabled(v);
                          },
                        ),
                        _settingsSwitch(
                          label: 'Mode sombre',
                          value: ThemeController.instance.isDark,
                          onChanged: (v) async {
                            await ThemeController.instance.toggle(v);
                            if (mounted) setState(() {});
                          },
                        ),
                        _settingsDropdown(
                          label: 'Téléchargement auto',
                          value: _mediaDownloadPref,
                          items: const {
                            'always': 'Toujours',
                            'ask': 'Demander',
                            'never': 'Jamais',
                          },
                          onChanged: (v) async {
                            setState(() => _mediaDownloadPref = v);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('media_download_pref', v);
                          },
                        ),
                        _settingsSwitch(
                          label: 'Télécharger uniquement en Wi‑Fi',
                          value: _mediaWifiOnly,
                          onChanged: (v) async {
                            setState(() => _mediaWifiOnly = v);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('media_download_wifi_only', v);
                          },
                        ),
                        _settingsDropdown(
                          label: 'Thème discussion',
                          value: _chatTheme,
                          items: const {
                            'system': 'Système',
                            'light': 'Clair',
                            'dark': 'Sombre',
                          },
                          onChanged: (v) async {
                            setState(() => _chatTheme = v);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('chat_theme', v);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionTitle('CONFIDENTIALITÉ'),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      children: [
                        _settingsSwitch(
                          label: 'Visible pour les contacts',
                          value: _showPhoneToContacts,
                          onChanged: (v) async {
                            setState(() => _showPhoneToContacts = v);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('show_phone_to_contacts', v);
                          },
                        ),
                        _settingsSwitch(
                          label: 'Présence en ligne',
                          value: _showOnlinePresence,
                          onChanged: (v) async {
                            setState(() => _showOnlinePresence = v);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('show_online_presence', v);
                          },
                        ),
                        _settingsSwitch(
                          label: 'Photos de profil',
                          value: _showProfilePhotos,
                          onChanged: (v) async {
                            setState(() => _showProfilePhotos = v);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('show_profile_photos', v);
                          },
                        ),
                        _settingsSwitch(
                          label: 'Bio',
                          value: _showBio,
                          onChanged: (v) async {
                            setState(() => _showBio = v);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('show_bio', v);
                          },
                        ),
                        _settingsSwitch(
                          label: 'Statut',
                          value: _showStatus,
                          onChanged: (v) async {
                            setState(() => _showStatus = v);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('show_status', v);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _sectionTitle('SÉCURITÉ'),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
                    child: Column(
                      children: [
                        _settingsTile(
                          label: 'Changer mot de passe',
                          subtitle: 'Email de réinitialisation',
                          onTap: () async {
                            final u = FirebaseAuth.instance.currentUser;
                            if (u?.email == null || u!.email!.isEmpty) {
                              _snack('Email introuvable.', error: true);
                              return;
                            }
                            try {
                              await FirebaseAuth.instance.sendPasswordResetEmail(email: u.email!);
                              _snack('Lien de réinitialisation envoyé.');
                            } catch (e) {
                              _snack('Erreur: $e', error: true);
                            }
                          },
                        ),
                        _settingsTile(
                          label: 'Changer email',
                          subtitle: 'Mettre à jour l\'adresse',
                          onTap: () async {
                            final u = FirebaseAuth.instance.currentUser;
                            if (u == null) return;
                            final ctrl = TextEditingController(text: _email);
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                backgroundColor: isDark ? const Color(0xFF111B21) : Colors.white,
                                title: Text('Changer email', style: TextStyle(color: text)),
                                content: TextField(
                                  controller: ctrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(labelText: 'Nouvel email'),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Valider')),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            final newEmail = _safeStr(ctrl.text);
                            if (newEmail.isEmpty) return;
                            try {
                              await u.updateEmail(newEmail);
                              _email = newEmail;
                              _emailCtrl.text = newEmail;
                              if (_userRef != null) {
                                await _userRef!.set({'email': newEmail}, SetOptions(merge: true));
                              }
                              if (mounted) setState(() {});
                              _snack('Email mis à jour.');
                            } on FirebaseAuthException catch (e) {
                              _snack(AuthErrorMessages.fromFirebaseAuthException(e), error: true);
                            } catch (e) {
                              _snack('Erreur: $e', error: true);
                            }
                          },
                        ),
                        _settingsTile(
                          label: 'Appareils connectés',
                          subtitle: 'Liste des appareils',
                          onTap: () async {
                            final devices = (_userData['devices'] is List)
                                ? List<String>.from(_userData['devices'])
                                : <String>[];
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: isDark ? const Color(0xFF111B21) : Colors.white,
                              builder: (ctx) {
                                final subc = isDark ? Colors.white70 : Colors.black54;
                                return SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('Appareils connectés', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 10),
                                        if (devices.isEmpty)
                                          Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Text('Aucun appareil connecté', style: TextStyle(color: subc)),
                                          )
                                        else
                                          ...devices.map((d) => ListTile(
                                                leading: const Icon(Icons.devices_other),
                                                title: Text(d, style: TextStyle(color: text)),
                                                subtitle: Text('Dernière activité', style: TextStyle(color: subc)),
                                              )),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        _settingsTile(
                          label: 'Supprimer le compte',
                          subtitle: 'Action définitive',
                          onTap: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                backgroundColor: isDark ? const Color(0xFF111B21) : Colors.white,
                                title: Text('Supprimer le compte', style: TextStyle(color: text)),
                                content: Text(
                                  'Cette action est définitive. Voulez-vous continuer ?',
                                  style: TextStyle(color: sub),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                                  TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
                                ],
                              ),
                            );
                            if (ok != true) return;
                            try {
                              await FirebaseAuth.instance.currentUser?.delete();
                              if (!mounted) return;
                              Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                            } on FirebaseAuthException catch (e) {
                              _snack(AuthErrorMessages.fromFirebaseAuthException(e), error: true);
                            } catch (e) {
                              _snack('Erreur: $e', error: true);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required Color text,
    required bool isDark,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool readOnly = false,
    VoidCallback? onTap,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
    );
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      readOnly: readOnly,
      onTap: onTap,
      style: TextStyle(color: text, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w700),
        filled: true,
        fillColor: isDark ? Colors.white10 : const Color(0xFFF3F4F6),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: const BorderSide(color: Color(0xFF00CBA9), width: 1.2)),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    final isDark = _isDark();
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 6, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: isDark ? Colors.orangeAccent : Colors.orange.shade700,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _settingsSwitch({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = _isDark();
    final text = isDark ? Colors.white : Colors.black87;
    return SwitchListTile(
      value: value,
      onChanged: _settingsLoaded ? onChanged : null,
      activeThumbColor: const Color(0xFF00CBA9),
      title: Text(label, style: TextStyle(color: text, fontWeight: FontWeight.w700)),
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _settingsDropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) {
    final isDark = _isDark();
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white70 : Colors.black54;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: TextStyle(color: text, fontWeight: FontWeight.w700)),
      trailing: DropdownButton<String>(
        value: value,
        dropdownColor: isDark ? const Color(0xFF111B21) : Colors.white,
        onChanged: _settingsLoaded ? (v) => v == null ? null : onChanged(v) : null,
        items: items.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
      ),
      subtitle: _settingsLoaded ? Text(items[value] ?? value, style: TextStyle(color: sub)) : null,
    );
  }

  Widget _settingsTile({required String label, required VoidCallback onTap, String? subtitle}) {
    final isDark = _isDark();
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white70 : Colors.black54;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: TextStyle(color: text, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle ?? '', style: TextStyle(color: sub)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: onTap,
    );
  }
}
