import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isFrontCamera = false;
  bool _isRecording = false;
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      // Choose camera by lens direction if possible, fallback to first camera
      final desired = _isFrontCamera ? CameraLensDirection.front : CameraLensDirection.back;
      CameraDescription chosen = _cameras!.first;
      for (final c in _cameras!) {
        if (c.lensDirection == desired) { chosen = c; break; }
      }
      _controller = CameraController(
        chosen,
        ResolutionPreset.high,
        enableAudio: true,
      );

      try {
        await _controller!.initialize();
        if (mounted) setState(() => _isInitialized = true);
      } catch (e) {
        debugPrint("Erreur caméra: $e");
      }
    }
  }

  // MÉTHODE BUILD (C'est celle qui manquait ou était mal placée)
  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.orange)));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. APERÇU CAMÉRA (Plein écran)
          Center(
            child: CameraPreview(_controller!),
          ),

          // 2. BOUTONS DU HAUT (Flash et Fermer)
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
                IconButton(
                  icon: Icon(
                    _flashMode == FlashMode.off ? Icons.flash_off : Icons.flash_on,
                    color: _flashMode == FlashMode.off ? Colors.white : Colors.yellow,
                    size: 30,
                  ),
                  onPressed: _toggleFlash,
                ),
              ],
            ),
          ),

          // 3. BOUTONS DU BAS (Capture et Rotation)
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const SizedBox(width: 60), // Pour équilibrer le bouton rotation
                
                // BOUTON DE CAPTURE (Design Telegram)
                GestureDetector(
                  onTap: _takePicture,
                  onLongPressStart: (_) => _startVideoRecording(),
                  onLongPressUp: () => _stopVideoRecording(),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                            if (_isRecording)
                              SizedBox(
                                width: 90, height: 90,
                                child: CircularProgressIndicator(color: Colors.orange, strokeWidth: 4),
                              ),
                      Container(
                        width: 75, height: 75,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isRecording ? Colors.red : Colors.white,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                      ),
                    ],
                  ),
                ),

                // BOUTON ROTATION
                IconButton(
                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 35),
                  onPressed: _toggleCamera,
                ),
              ],
            ),
          ),
          
          if (_isRecording)
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Text("ENREGISTREMENT", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  // --- LOGIQUE DES ACTIONS ---

  void _toggleFlash() {
    setState(() {
      _flashMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
      _controller!.setFlashMode(_flashMode);
    });
  }

  void _toggleCamera() {
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _isInitialized = false;
    });
    _initCamera();
  }

  Future<void> _takePicture() async {
    if (_isRecording) return;
    final image = await _controller!.takePicture();
    if (mounted) Navigator.pop(context, image);
  }

  Future<void> _startVideoRecording() async {
    await _controller!.startVideoRecording();
    setState(() => _isRecording = true);
    HapticFeedback.heavyImpact();
  }

  Future<void> _stopVideoRecording() async {
    if (!_isRecording) return;
    final video = await _controller!.stopVideoRecording();
    setState(() => _isRecording = false);
    if (mounted) Navigator.pop(context, video);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}