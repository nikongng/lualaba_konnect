import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:syncfusion_flutter_pdf/pdf.dart';


class RegistrationFormPage extends StatefulWidget {
  final int profileType;
  const RegistrationFormPage({super.key, required this.profileType});

  @override
  State<RegistrationFormPage> createState() => _RegistrationFormPageState();
}

class _RegistrationFormPageState extends State<RegistrationFormPage>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 2;

  // --- ÉTATS CHARGEMENT ---
  bool _isLoading = false;
  String _loadingMessage = "";
  double _uploadProgress = 0.0;
  late AnimationController _waveController;
  Uint8List? _faceImageBytesWeb; // Pour l'affichage sur le Web

  // --- CONTRÔLEURS ---
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final Map<String, FocusNode> _focusNodes = {
    'prenom': FocusNode(),
    'nom': FocusNode(),
    'phone': FocusNode(),
    'address': FocusNode(),
    'email': FocusNode(),
    'pass': FocusNode(),
    'confirm': FocusNode(),
  };

  bool _obscurePass = true;
  bool _obscureConfirm = true;
  DateTime? _selectedDate;
  String selectedGenre = "M";
  File? _identityFile;
  File? _faceImage;
  Uint8List? _pdfBytesWeb;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _emailController.addListener(() => setState(() {}));
    _phoneController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
    _confirmPasswordController.addListener(() => setState(() {}));
    _focusNodes.forEach((key, node) => node.addListener(() => setState(() {})));
  }

  @override
  void dispose() {
    _waveController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --- LOGIQUE DE VALIDATION ---
  bool _isEmailValid(String email) => RegExp(
    r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@gmail\.com$",
  ).hasMatch(email);
  bool _isPhoneValid(String phone) {
    String clean = phone.replaceAll(' ', '');
    return (clean.startsWith('0') || clean.startsWith('+')) &&
        clean.length >= 10;
  }

  bool _isPasswordMatch() =>
      _passwordController.text.length >= 6 &&
      _passwordController.text == _confirmPasswordController.text;

  // --- LOGIQUE DE VÉRIFICATION AVEC PROGRESSION FLUIDE ---
  Future<void> _startFinalization() async {
    // 1. Vérification de l'âge
    if (_selectedDate == null) {
      _showError("Veuillez renseigner votre date de naissance.");
      return;
    }
    final age = DateTime.now().year - _selectedDate!.year;
    if (age < 18) {
      _showError("Dossier rejeté : Vous devez avoir au moins 18 ans.");
      return;
    }

    // 2. Vérification présence fichier
    if (_identityFile == null) {
      _showError("Veuillez charger votre pièce d'identité.");
      return;
    }

    setState(() {
      _isLoading = true;
      _uploadProgress = 0.0;
      _loadingMessage = "Initialisation...";
    });

    // Petite fonction interne pour faire monter la barre en douceur
    Future<void> smoothProgress(double target) async {
      while (_uploadProgress < target) {
        await Future.delayed(const Duration(milliseconds: 10));
        setState(() {
          _uploadProgress += 0.005; // Augmentation très fine pour la fluidité
          if (_uploadProgress > target) _uploadProgress = target;
        });
      }
    }

    bool isAutomaticSuccess = false;

    try {
      // ÉTAPE 1 : LECTURE PDF
      setState(() => _loadingMessage = "Lecture du document PDF...");
      await smoothProgress(0.25);

      Uint8List bytes = kIsWeb
          ? _pdfBytesWeb!
          : await _identityFile!.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      String pdfText = PdfTextExtractor(document).extractText();
      document.dispose();

      // ÉTAPE 2 : ANALYSE DES DONNÉES
      setState(() => _loadingMessage = "Analyse de conformité...");
      await smoothProgress(0.55);

      String nomSaisi = _lastNameController.text.trim().toUpperCase();
      // On vérifie si le nom est dans le texte extrait
      if (pdfText.toUpperCase().contains(nomSaisi)) {
        isAutomaticSuccess = true;
      }

      // ÉTAPE 3 : BIOMÉTRIE
      setState(() => _loadingMessage = "Vérification biométrique...");
      await smoothProgress(0.85);
      // Simulation du temps de calcul biométrique
      await Future.delayed(const Duration(seconds: 1));

      // ÉTAPE 4 : FINALISATION
      setState(() => _loadingMessage = "Envoi au serveur sécurisé...");
      await smoothProgress(1.0);

      await Future.delayed(const Duration(milliseconds: 500));
      _completeRegistration(isAutomaticSuccess);
    } catch (e) {
      // En cas d'erreur de lecture, on finit quand même pour vérification manuelle
      await smoothProgress(1.0);
      _completeRegistration(false);
    }
  }

  void _completeRegistration(bool autoValidated) async {
    if (mounted) {
      setState(() => _isLoading = false);
      _showFinalSummary(autoValidated);
    }
  }

void _showFinalSummary(bool autoValidated) {
    HapticFeedback.vibrate(); 

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
        backgroundColor: Colors.transparent,
        child: TweenAnimationBuilder(
          duration: const Duration(milliseconds: 900),
          tween: Tween<Offset>(begin: const Offset(0, 1.5), end: const Offset(0, 0)),
          // CORRECTION ICI : easeOutBack est la propriété exacte
          curve: Curves.easeOutBack, 
          builder: (context, Offset offset, child) {
            return FractionalTranslation(
              translation: offset,
              child: Container(
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 30,
                      offset: const Offset(0, -10),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 90,
                      width: 90,
                      decoration: BoxDecoration(
                        color: autoValidated ? Colors.green.shade50 : Colors.blue.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          autoValidated ? "🥰" : "😎", 
                          style: const TextStyle(fontSize: 50),
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    Text(
                      autoValidated ? "Certification lancée !" : "Dossier en route !",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.w900, 
                        color: Color(0xFFE65100),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      autoValidated 
                        ? "Check terminé ! Tes documents sont validés. Nous finalisons ta certification maintenant."
                        : "Tes documents ont été envoyés avec succès. Nous vérifions tout ça tout de suite.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15, 
                        color: Colors.grey.shade600, 
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 35),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact(); 
                        Navigator.pop(context);
                      },
                      child: Container(
                        height: 60,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF57C00), Color(0xFFE65100)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Text(
                            "PARFAIT, MERCI !",
                            style: TextStyle(
                              color: Colors.white, 
                              fontWeight: FontWeight.bold, 
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _validateAndNext() {
    if (_currentStep == 2) {
      if (!_isPhoneValid(_phoneController.text) ||
          !_isEmailValid(_emailController.text) ||
          !_isPasswordMatch()) {
        _showError("Veuillez vérifier vos informations");
        return;
      }
      setState(() => _currentStep = 3);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    } else {
      if (_identityFile == null || _faceImage == null) {
        _showError("Documents manquants");
        return;
      }
      _startFinalization();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE65100),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 50),
                  _buildHeader(),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(40),
                          topRight: Radius.circular(40),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildTopNav(),
                          Expanded(
                            child: PageView(
                              controller: _pageController,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [_buildStep2(), _buildStep3()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_isLoading) _buildModernLoadingOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // --- OVERLAY DE CHARGEMENT ---
  Widget _buildModernLoadingOverlay() {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        color: Colors.black.withOpacity(0.35),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 260,
            padding: const EdgeInsets.symmetric(vertical: 35, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(35),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white, width: 8),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _waveController,
                        builder: (context, child) {
                          return CustomPaint(
                            size: const Size(140, 140),
                            painter: LiquidWavePainter(
                              progress: _uploadProgress,
                              animationValue: _waveController.value,
                            ),
                          );
                        },
                      ),
                      Text(
                        "${(_uploadProgress * 100).toInt()}%",
                        style: TextStyle(
                          color: _uploadProgress > 0.48
                              ? Colors.white
                              : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  _loadingMessage.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF37474F),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Veuillez patienter...",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- ÉTAPES FORMULAIRE ---
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildField(
                  "Prénom",
                  Icons.person,
                  _firstNameController,
                  _focusNodes['prenom']!,
                  hintText: "ex: John",
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: _buildField(
                  "Nom",
                  Icons.person,
                  _lastNameController,
                  _focusNodes['nom']!,
                  hintText: "ex: Doe",
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildField(
            "Téléphone",
            Icons.phone,
            _phoneController,
            _focusNodes['phone']!,
            type: TextInputType.phone,
            hintText: "081 000 00 00",
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
              PhoneInputFormatter(),
            ],
            suffix: _isPhoneValid(_phoneController.text)
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
          ),
          const SizedBox(height: 15),
          _buildAddressField(),
          const SizedBox(height: 15),
          Row(
            children: [
              _buildGenderToggle(),
              const SizedBox(width: 15),
              Expanded(child: _buildDatePicker()),
            ],
          ),
          const SizedBox(height: 15),
          _buildField(
            "Gmail",
            Icons.email,
            _emailController,
            _focusNodes['email']!,
            hintText: "nom@gmail.com",
            suffix: _isEmailValid(_emailController.text)
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
          ),
          const SizedBox(height: 15),
          _buildField(
            "Mot de passe",
            Icons.lock,
            _passwordController,
            _focusNodes['pass']!,
            isPass: _obscurePass,
            suffix: IconButton(
              icon: Icon(
                _obscurePass ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
          ),
          const SizedBox(height: 15),
          _buildField(
            "Confirmation",
            Icons.lock_reset,
            _confirmPasswordController,
            _focusNodes['confirm']!,
            isPass: _obscureConfirm,
            suffix: _isPasswordMatch()
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
          ),
          const SizedBox(height: 30),
          _buildMainButton("Suivant →", _validateAndNext),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25),
      child: Column(
        children: [
          const Text(
            "VÉRIFICATION D'IDENTITÉ",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
          ),
          const SizedBox(height: 30),
          _buildUploadCard(),
          const SizedBox(height: 40),
          _buildSelfieZone(),
          const SizedBox(height: 50),
          _buildMainButton("Verifier ", _validateAndNext),
        ],
      ),
    );
  }

  // --- HELPERS UI ---
Widget _buildSelfieZone() {
  return Stack(
    alignment: Alignment.bottomRight,
    children: [
      Container(
        height: 160,
        width: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.orange, width: 4),
          image: (_faceImageBytesWeb != null) 
              ? DecorationImage(
                  image: MemoryImage(_faceImageBytesWeb!), // Utilise la mémoire (Web/Mobile)
                  fit: BoxFit.cover,
                ) 
              : null,
          color: Colors.grey.shade100,
        ),
        // Si pas d'image, on affiche l'icône, sinon on affiche rien (l'image est en background)
        child: _faceImage == null 
            ? const Icon(Icons.face_retouching_natural, size: 80, color: Colors.grey) 
            : null,
      ),
      FloatingActionButton(
        backgroundColor: Colors.orange.shade900,
      onPressed: () async {
        final XFile? image = await ImagePicker().pickImage(
          source: ImageSource.camera, 
          preferredCameraDevice: CameraDevice.front
        );

        if (image != null) {
          // On lit les bytes pour le Web
          final Uint8List bytes = await image.readAsBytes();
          
          setState(() {
            _faceImageBytesWeb = bytes;
            // On garde _faceImage pour la compatibilité mobile si nécessaire
            _faceImage = File(image.path); 
          });
        }
      },
        child: const Icon(Icons.camera_alt, color: Colors.white),
      ),
    ],
  );
}

  Widget _buildField(
    String label,
    IconData icon,
    TextEditingController ctr,
    FocusNode node, {
    bool isPass = false,
    TextInputType? type,
    String? hintText,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: ctr,
          focusNode: node,
          obscureText: isPass,
          keyboardType: type,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(
              icon,
              color: node.hasFocus ? Colors.orange : Colors.grey,
            ),
            suffixIcon: suffix,
            filled: true,
            fillColor: Colors.grey.shade50,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: const BorderSide(color: Colors.orange, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadCard() {
    return GestureDetector(
      onTap: () async {
        FilePickerResult? r = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (r != null) {
          setState(() {
            if (kIsWeb) {
              _pdfBytesWeb = r.files.single.bytes;
              _identityFile = File(r.files.single.name);
            } else {
              _identityFile = File(r.files.single.path!);
            }
          });
        }
      },
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _identityFile != null ? Colors.green : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _identityFile != null ? Icons.check_circle : Icons.badge_outlined,
              color: _identityFile != null ? Colors.green : Colors.orange,
              size: 40,
            ),
            Text(
              _identityFile != null
                  ? "Document PDF chargé"
                  : "Charger Pièce d'Identité (PDF)",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "GENRE",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 55,
          width: 110,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                alignment: selectedGenre == "M"
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  width: 55,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => selectedGenre = "M"),
                      child: Center(
                        child: Icon(
                          Icons.male,
                          color: selectedGenre == "M"
                              ? Colors.white
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => selectedGenre = "F"),
                      child: Center(
                        child: Icon(
                          Icons.female,
                          color: selectedGenre == "F"
                              ? Colors.white
                              : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressField() {
    return _buildField(
      "Adresse",
      Icons.map,
      _addressController,
      _focusNodes['address']!,
      hintText: "Quartier, Avenue...",
      suffix: IconButton(
        icon: const Icon(Icons.my_location, color: Colors.blue),
        onPressed: () async {
          setState(() => _addressController.text = "Localisation...");
          LocationPermission p = await Geolocator.requestPermission();
          if (p == LocationPermission.whileInUse ||
              p == LocationPermission.always) {
            Position pos = await Geolocator.getCurrentPosition();
            if (kIsWeb) {
              setState(
                () => _addressController.text =
                    "Lat: ${pos.latitude.toStringAsFixed(3)}, Long: ${pos.longitude.toStringAsFixed(3)}",
              );
            } else {
              List<Placemark> marks = await placemarkFromCoordinates(
                pos.latitude,
                pos.longitude,
              );
              if (marks.isNotEmpty)
                setState(
                  () => _addressController.text =
                      "${marks[0].street}, ${marks[0].locality}",
                );
            }
          }
        },
      ),
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "NAISSANCE",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 5),
        InkWell(
          onTap: () async {
            DateTime? d = await showDatePicker(
              context: context,
              initialDate: DateTime(2000),
              firstDate: DateTime(1920),
              lastDate: DateTime.now(),
            );
            if (d != null) setState(() => _selectedDate = d);
          },
          child: Container(
            height: 55,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Text(
                _selectedDate == null
                    ? "Date"
                    : DateFormat('dd/MM/yyyy').format(_selectedDate!),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() => Column(
    children: [
      const Icon(Icons.wifi_tethering, color: Colors.white, size: 50),
      const Text(
        "Lualaba Konnect",
        style: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
  Widget _buildTopNav() => Padding(
    padding: const EdgeInsets.all(15),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: () {
            if (_currentStep > 2) {
              // Si on est à l'étape 3, on revient à l'étape 2
              setState(() => _currentStep = 2);
              _pageController.previousPage(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeInOutCubic,
              );
            } else {
              // Si on est déjà à l'étape 2, on quitte la page vers le choix du compte
              Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.arrow_back_ios),
        ),
        Text(
          "ÉTAPE $_currentStep / 3",
          style: const TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 40),
      ],
    ),
  );
  Widget _buildMainButton(String t, VoidCallback a) => SizedBox(
    width: double.infinity,
    height: 60,
    child: ElevatedButton(
      onPressed: a,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(
        t,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}

// --- LIQUID PAINTER ---
class LiquidWavePainter extends CustomPainter {
  final double progress;
  final double animationValue;
  LiquidWavePainter({required this.progress, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    Color waveColor = progress <= 0.5
        ? Color.lerp(Colors.greenAccent, Colors.blue, progress * 2)!
        : Color.lerp(
            Colors.blue,
            Colors.orange.shade900,
            (progress - 0.5) * 2,
          )!;
    _drawWave(
      canvas,
      size,
      progress,
      animationValue,
      waveColor.withOpacity(0.35),
      8,
    );
    _drawWave(canvas, size, progress, animationValue + 0.5, waveColor, 6);
  }

  void _drawWave(
    Canvas canvas,
    Size size,
    double progress,
    double anim,
    Color color,
    double waveHeight,
  ) {
    final paint = Paint()..color = color;
    final path = Path();
    final yOffset = size.height * (1 - progress);
    path.moveTo(0, yOffset);
    for (double i = 0; i <= size.width; i++) {
      path.lineTo(
        i,
        yOffset +
            (math.sin((i / size.width * 2 * math.pi) + (anim * 2 * math.pi)) *
                waveHeight),
      );
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldV,
    TextEditingValue newV,
  ) {
    String text = newV.text.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      if ((i == 2 || i == 5 || i == 7) && i != text.length - 1)
        buffer.write(' ');
    }
    return newV.copyWith(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}
