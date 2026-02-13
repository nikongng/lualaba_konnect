import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdultSpacePage extends StatefulWidget {
  const AdultSpacePage({super.key});

  @override
  State<AdultSpacePage> createState() => _AdultSpacePageState();
}

class _AdultSpacePageState extends State<AdultSpacePage> with WidgetsBindingObserver {
  static const Duration _sessionTtl = Duration(minutes: 10);

  bool _loading = true;
  bool _allowed = false;
  bool _ageBlocked = false;
  bool _identityBlocked = false;
  bool _missingBirthDate = false;
  DateTime? _birthDate;

  bool _blurThumbs = true;
  bool _hidePreview = true;
  bool _discoverable = true;

  String? _uid;
  DocumentReference<Map<String, dynamic>>? _userRef;
  Map<String, dynamic> _userData = <String, dynamic>{};
  String _userCollection = '';

  String? _pinHash;
  String? _pinPlain;
  bool _pinConfigured = false;
  bool _pinVerified = false;
  String? _pinError;
  DateTime? _sessionExpiry;
  Timer? _sessionTimer;
  final TextEditingController _pinCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkSessionExpiry();
    }
  }

  bool _isDark() => Theme.of(context).brightness == Brightness.dark;

  String _sessionKey() => 'adult_session_expiry_${_uid ?? ''}';

  Future<void> _loadAll() async {
    await _loadPrefs();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _uid = user.uid;

    final doc = await _fetchUserDoc(user.uid);
    if (doc != null) {
      _userRef = doc.ref;
      _userData = doc.data;
      _userCollection = doc.collection;

      final rawBirth = _userData['birthDate'];
      if (rawBirth is Timestamp) {
        _birthDate = rawBirth.toDate();
      } else if (rawBirth is String) {
        _birthDate = DateTime.tryParse(rawBirth.trim());
      }

      final validated = _userData['isValidated'];
      if (validated is bool && validated == false) {
        _identityBlocked = true;
      }

      final ph = (_userData['adultPinHash'] ?? '').toString().trim();
      final pp = (_userData['adultPin'] ?? '').toString().trim();
      _pinHash = ph.isEmpty ? null : ph;
      _pinPlain = pp.isEmpty ? null : pp;
      _pinConfigured = (_pinHash != null && _pinHash!.isNotEmpty) || (_pinPlain != null && _pinPlain!.isNotEmpty);
    }

    final age = _birthDate == null ? null : _ageFrom(_birthDate!);
    if (age != null) {
      _ageBlocked = age < 18;
      _allowed = age >= 18;
      _missingBirthDate = false;
    } else {
      _allowed = false;
      _ageBlocked = false;
      _missingBirthDate = true;
    }

    final prefs = await SharedPreferences.getInstance();
    final expiryMs = prefs.getInt(_sessionKey());
    if (expiryMs != null) {
      _sessionExpiry = DateTime.fromMillisecondsSinceEpoch(expiryMs);
    }
    _pinVerified = _sessionActive();
    _startSessionTimer();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _blurThumbs = prefs.getBool('adult_blur_thumbs') ?? true;
    _hidePreview = prefs.getBool('adult_hide_preview') ?? true;
    _discoverable = prefs.getBool('adult_discoverable') ?? true;
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
        return _UserDoc(snap.reference, snap.data() ?? <String, dynamic>{}, col);
      } catch (_) {}
    }
    return null;
  }

  int _ageFrom(DateTime birth) {
    final now = DateTime.now();
    int years = now.year - birth.year;
    final m = now.month - birth.month;
    if (m < 0 || (m == 0 && now.day < birth.day)) years--;
    return years;
  }

  Future<void> _confirmAdult() async {}

  bool _sessionActive() {
    if (_sessionExpiry == null) return false;
    return _sessionExpiry!.isAfter(DateTime.now());
  }

  Future<void> _setSessionActive() async {
    final expiry = DateTime.now().add(_sessionTtl);
    _sessionExpiry = expiry;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionKey(), expiry.millisecondsSinceEpoch);
    _pinVerified = true;
    _pinError = null;
    if (mounted) setState(() {});
  }

  void _bumpSession() {
    if (!_pinVerified) return;
    _setSessionActive();
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkSessionExpiry());
  }

  void _checkSessionExpiry() {
    if (!_pinVerified) return;
    if (!_sessionActive()) {
      _pinVerified = false;
      _pinError = 'Session expirée. Entrez votre code PIN.';
      if (mounted) setState(() {});
    }
  }

  String _hashPin(String pin) {
    final uid = _uid ?? '';
    final raw = '$uid:$pin';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Future<bool> _verifyPin(String pin) async {
    if (_pinHash != null && _pinHash!.isNotEmpty) {
      return _hashPin(pin) == _pinHash;
    }
    if (_pinPlain != null && _pinPlain!.isNotEmpty) {
      if (pin == _pinPlain) {
        await _savePinHash(pin);
        return true;
      }
    }
    return false;
  }

  Future<void> _savePinHash(String pin) async {
    if (_userRef == null) return;
    final hash = _hashPin(pin);
    await _userRef!.set({
      'adultPinHash': hash,
      'adultPinUpdatedAt': FieldValue.serverTimestamp(),
      'adultPin': FieldValue.delete(),
    }, SetOptions(merge: true));
    _pinHash = hash;
    _pinPlain = null;
    _pinConfigured = true;
  }

  Future<void> _submitPin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _pinError = 'Entrez le code PIN.');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _pinError = 'Le PIN doit contenir 4 chiffres.');
      return;
    }
    if (!_pinConfigured) {
      setState(() => _pinError = 'Code non configuré. Contactez un administrateur.');
      return;
    }
    final ok = await _verifyPin(pin);
    if (!ok) {
      setState(() => _pinError = 'Code incorrect.');
      return;
    }
    _pinCtrl.clear();
    await _setSessionActive();
  }

  Future<void> _changePin() async {
    if (_userRef == null) return;
    final cur = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        final isDark = _isDark();
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF111B21) : Colors.white,
          title: const Text('Changer le code PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cur,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(labelText: 'PIN actuel'),
              ),
              TextField(
                controller: next,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(labelText: 'Nouveau PIN'),
              ),
              TextField(
                controller: confirm,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(labelText: 'Confirmer'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Valider')),
          ],
        );
      },
    );
    if (ok != true) return;

    final curPin = cur.text.trim();
    final newPin = next.text.trim();
    final confPin = confirm.text.trim();

    if (curPin.isEmpty || newPin.isEmpty) {
      _snack('Tous les champs sont requis.');
      return;
    }
    if (newPin != confPin) {
      _snack('Les codes ne correspondent pas.');
      return;
    }
    if (!RegExp(r'^\d{4}$').hasMatch(newPin)) {
      _snack('Le PIN doit contenir 4 chiffres.');
      return;
    }

    final okPin = await _verifyPin(curPin);
    if (!okPin) {
      _snack('PIN actuel incorrect.');
      return;
    }

    await _savePinHash(newPin);
    await _setSessionActive();
    _snack('PIN mis à jour.');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark();
    final bg = isDark ? const Color(0xFF0F1416) : const Color(0xFFF7F8FA);
    final card = isDark ? Colors.white10 : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text('Espace Adultes', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
        iconTheme: IconThemeData(color: text),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ageBlocked
              ? _blockedView(text: text, sub: sub)
              : _missingBirthDate
                  ? _missingBirthView(text: text, sub: sub, card: card)
                  : _identityBlocked
                      ? _identityView(text: text, sub: sub)
                      : !_pinVerified
                          ? _pinView(text: text, sub: sub, card: card)
                          : Listener(
                              onPointerDown: (_) => _bumpSession(),
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                                children: [
                                  _hero(text: text, sub: sub, card: card),
                                  const SizedBox(height: 14),
                                  _sectionTitle('DÉCOUVRIR', isDark),
                                  _tile(
                                    title: 'POP THE BALLON',
                                    subtitle: 'Jeu interactif',
                                    icon: Icons.bubble_chart_outlined,
                                    color: Colors.pinkAccent,
                                    onTap: () => _snack('Bientot disponible'),
                                    card: card,
                                    text: text,
                                    sub: sub,
                                  ),
                                  _tile(
                                    title: 'QUICK PLEASURE',
                                    subtitle: 'Match rapide',
                                    icon: Icons.flash_on_outlined,
                                    color: Colors.deepOrangeAccent,
                                    onTap: () => _snack('Bientot disponible'),
                                    card: card,
                                    text: text,
                                    sub: sub,
                                  ),
                                  _tile(
                                    title: 'ARC EN CIEL',
                                    subtitle: 'Communauté',
                                    icon: Icons.color_lens_outlined,
                                    color: Colors.purpleAccent,
                                    onTap: () => _snack('Bientot disponible'),
                                    card: card,
                                    text: text,
                                    sub: sub,
                                  ),
                                  _tile(
                                    title: 'MON CAFE',
                                    subtitle: 'Espace détente',
                                    icon: Icons.coffee_outlined,
                                    color: Colors.brown,
                                    onTap: () => _snack('Bientot disponible'),
                                    card: card,
                                    text: text,
                                    sub: sub,
                                  ),
                                  _tile(
                                    title: 'ESCORT',
                                    subtitle: 'Services',
                                    icon: Icons.shield_outlined,
                                    color: Colors.redAccent,
                                    onTap: () => _snack('Bientot disponible'),
                                    card: card,
                                    text: text,
                                    sub: sub,
                                  ),
                                  _tile(
                                    title: 'MY SUGAR',
                                    subtitle: 'Rencontres premium',
                                    icon: Icons.diamond_outlined,
                                    color: Colors.amber,
                                    onTap: () => _snack('Bientot disponible'),
                                    card: card,
                                    text: text,
                                    sub: sub,
                                  ),
                                  _tile(
                                    title: 'FIND GIRLFRIENDS',
                                    subtitle: 'Rencontres',
                                    icon: Icons.favorite_outline,
                                    color: Colors.redAccent,
                                    onTap: () => _snack('Bientot disponible'),
                                    card: card,
                                    text: text,
                                    sub: sub,
                                  ),
                                  const SizedBox(height: 14),
                                  _sectionTitle('PRÉFÉRENCES', isDark),
                                  _switchTile(
                                    label: 'Flouter les vignettes',
                                    value: _blurThumbs,
                                    onChanged: (v) async {
                                      setState(() => _blurThumbs = v);
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setBool('adult_blur_thumbs', v);
                                    },
                                  ),
                                  _switchTile(
                                    label: 'Masquer les aperçus',
                                    value: _hidePreview,
                                    onChanged: (v) async {
                                      setState(() => _hidePreview = v);
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setBool('adult_hide_preview', v);
                                    },
                                  ),
                                  _switchTile(
                                    label: 'Apparaître dans les suggestions',
                                    value: _discoverable,
                                    onChanged: (v) async {
                                      setState(() => _discoverable = v);
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setBool('adult_discoverable', v);
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  _sectionTitle('SÉCURITÉ', isDark),
                                  _tile(
                                    title: 'Changer le code PIN',
                                    subtitle: 'Mise à jour du code',
                                    icon: Icons.lock_outline,
                                    color: Colors.teal,
                                    onTap: _changePin,
                                    card: card,
                                    text: text,
                                    sub: sub,
                                  ),
                                  const SizedBox(height: 14),
                                  _sectionTitle('CONFIDENTIALITÉ', isDark),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
                                    child: Text(
                                      'Le contenu adulte est masqué par défaut. Vous pouvez ajuster vos préférences ci‑dessus. '
                                      'Nous recommandons un usage discret sur les appareils partagés.',
                                      style: TextStyle(color: sub, height: 1.3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
    );
  }

  Widget _hero({required Color text, required Color sub, required Color card}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.redAccent.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.12), shape: BoxShape.circle),
            child: const Icon(Icons.whatshot, color: Colors.redAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Contenu réservé aux adultes', style: TextStyle(color: text, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Accès contrôlé et préférences personnalisables', style: TextStyle(color: sub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blockedView({required Color text, required Color sub}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text('Accès refusé', style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 8),
            Text('Votre âge ne permet pas l’accès à cet espace.', textAlign: TextAlign.center, style: TextStyle(color: sub)),
          ],
        ),
      ),
    );
  }

  Widget _identityView({required Color text, required Color sub}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_outlined, color: Colors.orangeAccent, size: 40),
            const SizedBox(height: 12),
            Text('Vérification requise', style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'Votre identité doit être vérifiée pour accéder à cet espace.',
              textAlign: TextAlign.center,
              style: TextStyle(color: sub),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gateView({required Color text, required Color sub, required Color card}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 38),
              const SizedBox(height: 10),
              Text('Confirmation d’âge', style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                _birthDate == null
                    ? 'Confirmez que vous avez 18 ans ou plus pour continuer.'
                    : 'Vérification en cours.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _missingBirthView({required Color text, required Color sub, required Color card}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 36),
              const SizedBox(height: 10),
              Text('Date de naissance requise', style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                'Complétez votre date de naissance dans votre profil pour accéder à cet espace.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pinView({required Color text, required Color sub, required Color card}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, color: Colors.redAccent, size: 36),
              const SizedBox(height: 10),
              Text('Code PIN requis', style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                _pinConfigured
                    ? 'Entrez le code Ã  4 chiffres fourni par un administrateur.'
                    : 'Code non configuré. Contactez un administrateur.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub),
              ),
              const SizedBox(height: 12),
              if (_pinConfigured)
                TextField(
                  controller: _pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Code PIN (4 chiffres)',
                    errorText: _pinError,
                  ),
                  onSubmitted: (_) => _submitPin(),
                ),
              if (!_pinConfigured && _pinError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_pinError!, style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _pinConfigured ? _submitPin : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                child: const Text('Entrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, bool isDark) {
    return Padding(
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

  Widget _tile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required Color card,
    required Color text,
    required Color sub,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: TextStyle(color: text, fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: TextStyle(color: sub)),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }

  Widget _switchTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = _isDark();
    final text = isDark ? Colors.white : Colors.black87;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF00CBA9),
      title: Text(label, style: TextStyle(color: text, fontWeight: FontWeight.w700)),
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _UserDoc {
  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> data;
  final String collection;
  _UserDoc(this.ref, this.data, this.collection);
}
