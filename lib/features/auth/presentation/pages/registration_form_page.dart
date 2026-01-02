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
// --- AJOUTS FIREBASE ---
import 'package:firebase_auth/firebase_auth.dart';
import 'otp_verification_page.dart';

class RegistrationFormPage extends StatefulWidget {
  final int profileType; // 0: Classique, 1: Pro, 2: Entreprise
  const RegistrationFormPage({super.key, required this.profileType});

  @override
  State<RegistrationFormPage> createState() => _RegistrationFormPageState();
}

class _RegistrationFormPageState extends State<RegistrationFormPage>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 2;

  // --- INSTANCE FIREBASE ---
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // --- ÉTATS CHARGEMENT ---
  bool _isLoading = false;
  String _loadingMessage = "";
  double _uploadProgress = 0.0;
  late AnimationController _waveController;
  Uint8List? _faceImageBytesWeb; 

  // --- CONTRÔLEURS ---
  final _firstNameController = TextEditingController(); 
  final _lastNameController = TextEditingController();  
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _rccmController = TextEditingController();
  final _idNatController = TextEditingController();
  final _nationalityController = TextEditingController();
  final _professionController = TextEditingController();
  final _experienceController = TextEditingController();
  final _currentCompanyController = TextEditingController();
  final _bioController = TextEditingController();

  final Map<String, FocusNode> _focusNodes = {
    'prenom': FocusNode(),
    'nom': FocusNode(),
    'phone': FocusNode(),
    'address': FocusNode(),
    'email': FocusNode(),
    'pass': FocusNode(),
    'confirm': FocusNode(),
    'bio': FocusNode(),
  };

  bool _obscurePass = true;
  final bool _obscureConfirm = true;
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
    _rccmController.dispose();
    _idNatController.dispose();
    _nationalityController.dispose();
    _professionController.dispose();
    _experienceController.dispose();
    _currentCompanyController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  bool _isEmailValid(String email) => RegExp(
        r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@gmail\.com$",
      ).hasMatch(email);

  bool _isPhoneValid(String phone) {
    String clean = phone.replaceAll(' ', '');
    // Comme le +243 est géré automatiquement, on vérifie juste qu'il y a 9 chiffres
    return clean.length >= 9;
  }

  bool _isPasswordMatch() =>
      _passwordController.text.length >= 6 &&
      _passwordController.text == _confirmPasswordController.text;

  Future<void> _startFinalization() async {
    if (widget.profileType != 2 && _selectedDate == null) {
      _showError("Veuillez renseigner votre date de naissance.");
      return;
    }
    
    if (widget.profileType != 2) {
      final age = DateTime.now().year - _selectedDate!.year;
      if (age < 18) {
        _showError("Dossier rejeté : Vous devez avoir au moins 18 ans.");
        return;
      }
    }

    if (_identityFile == null) {
      _showError("Veuillez charger votre pièce d'identité.");
      return;
    }

    setState(() {
      _isLoading = true;
      _uploadProgress = 0.0;
      _loadingMessage = "Initialisation...";
    });

    Future<void> smoothProgress(double target) async {
      while (_uploadProgress < target) {
        await Future.delayed(const Duration(milliseconds: 10));
        setState(() {
          _uploadProgress += 0.005;
          if (_uploadProgress > target) _uploadProgress = target;
        });
      }
    }

    try {
      setState(() => _loadingMessage = "Lecture du document PDF...");
      await smoothProgress(0.25);

      Uint8List bytes = kIsWeb ? _pdfBytesWeb! : await _identityFile!.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      String pdfText = PdfTextExtractor(document).extractText();
      document.dispose();

      setState(() => _loadingMessage = "Analyse de conformité...");
      await smoothProgress(0.55);

      String nomSaisi = _lastNameController.text.trim().toUpperCase();
      bool isAutomaticSuccess = pdfText.toUpperCase().contains(nomSaisi);

      setState(() => _loadingMessage = "Vérification biométrique...");
      await smoothProgress(0.85);
      await Future.delayed(const Duration(seconds: 1));

      setState(() => _loadingMessage = "Sécurisation profil...");
      await smoothProgress(1.0);

      await Future.delayed(const Duration(milliseconds: 500));
      _completeRegistration(isAutomaticSuccess);
    } catch (e) {
      await smoothProgress(1.0);
      _completeRegistration(false);
    }
  }

void _completeRegistration(bool autoValidated) async {
  if (mounted) {
    setState(() {
      _isLoading = true;
      _loadingMessage = "Envoi du code de certification...";
    });

    String cleanPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    String phoneForFirebase = "+243$cleanPhone";

    // --- TEST SANS CARTE BANCAIRE ---
    // Si c'est ton numéro fictif, on saute l'appel Firebase
    if (cleanPhone == "857263544") { 
      await Future.delayed(const Duration(seconds: 2)); // Simule un délai réseau
      setState(() => _isLoading = false);
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OTPVerificationPage(
            verificationId: "fake_id_for_test", // ID fictif
            phoneNumber: phoneForFirebase,
          ),
        ),
      );
      return; 
    }
    // ---------------------------------

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneForFirebase,
        // ... reste de ton code Firebase habituel
        verificationCompleted: (credential) async { /* ... */ },
        verificationFailed: (e) {
          setState(() => _isLoading = false);
          _showError("Erreur : ${e.message}");
        },
        codeSent: (id, token) {
          setState(() => _isLoading = false);
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => OTPVerificationPage(verificationId: id, phoneNumber: phoneForFirebase)
          ));
        },
        codeAutoRetrievalTimeout: (id) {},
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("Erreur : $e");
    }
  }
}
  void _validateAndNext() {
    if (_currentStep == 2) {
      if (!_isPhoneValid(_phoneController.text) || !_isEmailValid(_emailController.text) || !_isPasswordMatch()) {
        _showError("Vérifiez vos informations de base (Email, Phone, Pass)");
        return;
      }
      if (widget.profileType == 1) {
        if (_nationalityController.text.isEmpty || _professionController.text.isEmpty || _bioController.text.isEmpty) {
          _showError("Veuillez compléter votre profil professionnel");
          return;
        }
      }
      if (widget.profileType == 2) {
        if (_lastNameController.text.isEmpty || _rccmController.text.isEmpty || _idNatController.text.isEmpty || _bioController.text.isEmpty) {
          _showError("Veuillez remplir les champs obligatoires (RCCM, ID.NAT, Bio)");
          return;
        }
      }

      setState(() => _currentStep = 3);
      _pageController.nextPage(duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
    } else {
      if (_identityFile == null || _faceImage == null) {
        _showError("Documents manquants (PDF ou Selfie)");
        return;
      }
      _startFinalization();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
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
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(40), topRight: Radius.circular(40)),
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

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
      child: Column(
        children: [
          if (widget.profileType != 2)
            Row(
              children: [
                Expanded(child: _buildField("Prénom", Icons.person, _firstNameController, _focusNodes['prenom']!, hintText: "ex: John")),
                const SizedBox(width: 15),
                Expanded(child: _buildField("Nom", Icons.person, _lastNameController, _focusNodes['nom']!, hintText: "ex: Doe")),
              ],
            )
          else ...[
            _buildField("Nom de l'entreprise", Icons.business, _lastNameController, _focusNodes['nom']!, hintText: "Nom officiel"),
            const SizedBox(height: 15),
            _buildField("Nom court / Sigle", Icons.short_text, _firstNameController, _focusNodes['prenom']!, hintText: "ex: Lualaba K."),
          ],
          const SizedBox(height: 15),
          if (widget.profileType == 2) ...[
            Row(
              children: [
                Expanded(child: _buildField("N° RCCM", Icons.assignment, _rccmController, FocusNode())),
                const SizedBox(width: 15),
                Expanded(child: _buildField("ID. NAT", Icons.badge, _idNatController, FocusNode())),
              ],
            ),
            const SizedBox(height: 15),
          ],
          // MODIFICATION CHAMP TÉLÉPHONE
          _buildField(
            "Téléphone", 
            Icons.phone, 
            _phoneController, 
            _focusNodes['phone']!, 
            type: TextInputType.phone, 
            hintText: "81 000 00 00", 
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly, 
              PhoneInputFormatter(),
              LengthLimitingTextInputFormatter(12),
            ],
            prefix: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('+243', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
            ),
          ),
          const SizedBox(height: 15),
          _buildAddressField(),
          const SizedBox(height: 15),
          if (widget.profileType == 1) ...[
            Row(
              children: [
                Expanded(child: _buildField("Nationalité", Icons.flag, _nationalityController, FocusNode())),
                const SizedBox(width: 15),
                Expanded(child: _buildField("Profession", Icons.work, _professionController, FocusNode())),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: _buildField("Années Exp.", Icons.timeline, _experienceController, FocusNode(), type: TextInputType.number)),
                const SizedBox(width: 15),
                Expanded(child: _buildField("Employeur", Icons.business_center, _currentCompanyController, FocusNode())),
              ],
            ),
            const SizedBox(height: 15),
          ],
          if (widget.profileType != 2)
            Row(
              children: [
                _buildGenderToggle(),
                const SizedBox(width: 15),
                Expanded(child: _buildDatePicker()),
              ],
            ),
          const SizedBox(height: 15),
          _buildField("Gmail", Icons.email, _emailController, _focusNodes['email']!, hintText: "nom@gmail.com"),
          if (widget.profileType != 0) ...[
            const SizedBox(height: 15),
            _buildField(widget.profileType == 2 ? "Secteur d'activité" : "Ma Bio", Icons.edit_note, _bioController, _focusNodes['bio']!, hintText: "Décrivez brièvement..."),
          ],
          const SizedBox(height: 15),
          _buildField("Mot de passe", Icons.lock, _passwordController, _focusNodes['pass']!, isPass: _obscurePass, suffix: IconButton(icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscurePass = !_obscurePass))),
          const SizedBox(height: 15),
          _buildField("Confirmation", Icons.lock_reset, _confirmPasswordController, _focusNodes['confirm']!, isPass: _obscureConfirm, suffix: _isPasswordMatch() ? const Icon(Icons.check_circle, color: Colors.green) : null),
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
          const Text("VÉRIFICATION D'IDENTITÉ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
          const SizedBox(height: 30),
          _buildUploadCard(),
          const SizedBox(height: 40),
          _buildSelfieZone(),
          const SizedBox(height: 50),
          _buildMainButton("Vérifier", _validateAndNext),
        ],
      ),
    );
  }

  Widget _buildSelfieZone() {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          height: 160, width: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.orange, width: 4),
            image: (_faceImageBytesWeb != null) ? DecorationImage(image: MemoryImage(_faceImageBytesWeb!), fit: BoxFit.cover) : null,
            color: Colors.grey.shade100,
          ),
          child: _faceImage == null ? const Icon(Icons.face_retouching_natural, size: 80, color: Colors.grey) : null,
        ),
        FloatingActionButton(
          backgroundColor: Colors.orange.shade900,
          onPressed: () async {
            final XFile? image = await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.front);
            if (image != null) {
              final Uint8List bytes = await image.readAsBytes();
              setState(() { _faceImageBytesWeb = bytes; _faceImage = File(image.path); });
            }
          },
          child: const Icon(Icons.camera_alt, color: Colors.white),
        ),
      ],
    );
  }

  // MODIFICATION DE LA SIGNATURE DE _buildField POUR LE PREFIXE
  Widget _buildField(String label, IconData icon, TextEditingController ctr, FocusNode node, {bool isPass = false, TextInputType? type, String? hintText, List<TextInputFormatter>? inputFormatters, Widget? suffix, Widget? prefix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 5),
        TextField(
          controller: ctr, focusNode: node, obscureText: isPass, keyboardType: type, inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefix ?? Icon(icon, color: node.hasFocus ? Colors.orange : Colors.grey),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            suffixIcon: suffix, filled: true, fillColor: Colors.grey.shade50,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.orange, width: 2)),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadCard() {
    return GestureDetector(
      onTap: () async {
        FilePickerResult? r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
        if (r != null) {
          setState(() {
            if (kIsWeb) { _pdfBytesWeb = r.files.single.bytes; _identityFile = File(r.files.single.name); }
            else { _identityFile = File(r.files.single.path!); }
          });
        }
      },
      child: Container(
        height: 120, width: double.infinity,
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: _identityFile != null ? Colors.green : Colors.grey.shade300, width: 2)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_identityFile != null ? Icons.check_circle : Icons.badge_outlined, color: _identityFile != null ? Colors.green : Colors.orange, size: 40),
            Text(_identityFile != null ? "Document PDF chargé" : "Charger Pièce d'Identité (PDF)"),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("GENRE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 5),
        Container(
          height: 55, width: 110,
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(15)),
          child: Stack(
            children: [
              AnimatedAlign(
                alignment: selectedGenre == "M" ? Alignment.centerLeft : Alignment.centerRight,
                duration: const Duration(milliseconds: 250),
                child: Container(width: 55, decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(15))),
              ),
              Row(
                children: [
                  Expanded(child: GestureDetector(onTap: () => setState(() => selectedGenre = "M"), child: Center(child: Icon(Icons.male, color: selectedGenre == "M" ? Colors.white : Colors.grey)))),
                  Expanded(child: GestureDetector(onTap: () => setState(() => selectedGenre = "F"), child: Center(child: Icon(Icons.female, color: selectedGenre == "F" ? Colors.white : Colors.grey)))),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressField() {
    return _buildField("Adresse", Icons.map, _addressController, _focusNodes['address']!, hintText: "Quartier, Avenue...", suffix: IconButton(
      icon: const Icon(Icons.my_location, color: Colors.blue),
      onPressed: () async {
        setState(() => _addressController.text = "Localisation...");
        LocationPermission p = await Geolocator.requestPermission();
        if (p == LocationPermission.whileInUse || p == LocationPermission.always) {
          Position pos = await Geolocator.getCurrentPosition();
          if (kIsWeb) { setState(() => _addressController.text = "Lat: ${pos.latitude.toStringAsFixed(3)}, Long: ${pos.longitude.toStringAsFixed(3)}"); }
          else {
            List<Placemark> marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
            if (marks.isNotEmpty) setState(() => _addressController.text = "${marks[0].street}, ${marks[0].locality}");
          }
        }
      },
    ));
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("NAISSANCE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 5),
        InkWell(
          onTap: () async {
            DateTime? d = await showDatePicker(context: context, initialDate: DateTime(2000), firstDate: DateTime(1920), lastDate: DateTime.now());
            if (d != null) setState(() => _selectedDate = d);
          },
          child: Container(
            height: 55, decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)),
            child: Center(child: Text(_selectedDate == null ? "Date" : DateFormat('dd/MM/yyyy').format(_selectedDate!))),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() => Column(children: [const Icon(Icons.wifi_tethering, color: Colors.white, size: 50), const Text("Lualaba Konnect", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))]);

  Widget _buildTopNav() => Padding(
    padding: const EdgeInsets.all(15),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(onPressed: () {
          if (_currentStep > 2) { setState(() => _currentStep = 2); _pageController.previousPage(duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic); }
          else { Navigator.pop(context); }
        }, icon: const Icon(Icons.arrow_back_ios)),
        Text("ÉTAPE $_currentStep / 3", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        const SizedBox(width: 40),
      ],
    ),
  );

  Widget _buildMainButton(String t, VoidCallback a) => SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: a, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))));

  Widget _buildModernLoadingOverlay() {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        color: Colors.black.withOpacity(0.35),
        child: Center(
          child: Container(
            width: 260, padding: const EdgeInsets.symmetric(vertical: 35, horizontal: 20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: BorderRadius.circular(35)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 140, height: 140,
                  child: Stack(alignment: Alignment.center, children: [
                    AnimatedBuilder(animation: _waveController, builder: (context, child) {
                      return CustomPaint(size: const Size(140, 140), painter: LiquidWavePainter(progress: _uploadProgress, animationValue: _waveController.value));
                    }),
                    Text("${(_uploadProgress * 100).toInt()}%", style: TextStyle(color: _uploadProgress > 0.48 ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)),
                  ]),
                ),
                const SizedBox(height: 30),
                Text(_loadingMessage.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF37474F))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LiquidWavePainter extends CustomPainter {
  final double progress;
  final double animationValue;
  LiquidWavePainter({required this.progress, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    Color waveColor = progress <= 0.5 ? Color.lerp(Colors.greenAccent, Colors.blue, progress * 2)! : Color.lerp(Colors.blue, Colors.orange.shade900, (progress - 0.5) * 2)!;
    _drawWave(canvas, size, progress, animationValue, waveColor.withOpacity(0.35), 8);
    _drawWave(canvas, size, progress, animationValue + 0.5, waveColor, 6);
  }

  void _drawWave(Canvas canvas, Size size, double progress, double anim, Color color, double waveHeight) {
    final paint = Paint()..color = color;
    final path = Path();
    final yOffset = size.height * (1 - progress);
    path.moveTo(0, yOffset);
    for (double i = 0; i <= size.width; i++) {
      path.lineTo(i, yOffset + (math.sin((i / size.width * 2 * math.pi) + (anim * 2 * math.pi)) * waveHeight));
    }
    path.lineTo(size.width, size.height); path.lineTo(0, size.height); path.close();
    canvas.save(); canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, size.width, size.height)));
    canvas.drawPath(path, paint); canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// FORMATEUR AVEC ESPACES AUTOMATIQUES
class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');
    String newString = '';
    for (int i = 0; i < text.length; i++) {
      newString += text[i];
      if ((i == 1 || i == 4 || i == 6) && i != text.length - 1) {
        newString += ' ';
      }
    }
    return TextEditingValue(
      text: newString,
      selection: TextSelection.collapsed(offset: newString.length),
    );
  }
}