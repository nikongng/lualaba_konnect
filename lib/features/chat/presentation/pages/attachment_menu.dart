import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:camera/camera.dart';

const Color tgBar = Color(0xFF17212B);

class TelegramAttachmentSheet extends StatefulWidget {
  final Function(AssetEntity) onImageSelected;
  final VoidCallback onCameraTap;
  final VoidCallback onGalleryTap;
  final VoidCallback onFileTap;
  final VoidCallback onLocationTap;
  final VoidCallback onContactTap; // AJOUTÉ
  final VoidCallback onMusicTap;   // AJOUTÉ
  final VoidCallback onPollTap;    // AJOUTÉ

  const TelegramAttachmentSheet({
    super.key,
    required this.onImageSelected,
    required this.onCameraTap,
    required this.onGalleryTap,
    required this.onFileTap,
    required this.onLocationTap,
    required this.onContactTap,
    required this.onMusicTap,
    required this.onPollTap,
  });

  @override
  State<TelegramAttachmentSheet> createState() => _TelegramAttachmentSheetState();
}

class _TelegramAttachmentSheetState extends State<TelegramAttachmentSheet> {
  List<AssetEntity> _recentPhotos = [];
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
    _loadRecentPhotos();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _cameraController = CameraController(cameras[0], ResolutionPreset.low, enableAudio: false);
        await _cameraController!.initialize();
        if (mounted) setState(() => _isCameraInitialized = true);
      }
    } catch (e) { print("Erreur Caméra Menu: $e"); }
  }

  Future<void> _loadRecentPhotos() async {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth || ps.hasAccess) {
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(type: RequestType.image, onlyAll: true);
      if (albums.isNotEmpty) {
        List<AssetEntity> media = await albums[0].getAssetListPaged(page: 0, size: 20);
        if (mounted) setState(() => _recentPhotos = media);
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: tgBar, 
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 15),
          
          // --- GALERIE HORIZONTALE + CAMERA LIVE ---
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _recentPhotos.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return GestureDetector(
                    onTap: widget.onCameraTap,
                    child: Container(
                      width: 100, margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                      clipBehavior: Clip.antiAlias,
                      child: _isCameraInitialized ? CameraPreview(_cameraController!) : const Icon(Icons.camera_alt, color: Colors.white24),
                    ),
                  );
                }
                final asset = _recentPhotos[index - 1];
                return GestureDetector(
                  onTap: () => widget.onImageSelected(asset),
                  child: Container(
                    width: 100, margin: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: FutureBuilder<Uint8List?>(
                        future: asset.thumbnailData,
                        builder: (context, snapshot) => snapshot.hasData ? Image.memory(snapshot.data!, fit: BoxFit.cover) : Container(color: Colors.white10),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 20),

          // --- GRILLE D'ICONES COMPLETE ---
          Padding(
            padding: const EdgeInsets.only(bottom: 30),
            child: Wrap(
              spacing: 25,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: [
                _buildAction(Icons.photo, Colors.blue, "Galerie", widget.onGalleryTap),
                _buildAction(Icons.insert_drive_file, Colors.orange, "Fichier", widget.onFileTap),
                _buildAction(Icons.location_on, Colors.green, "Position", widget.onLocationTap),
                _buildAction(Icons.poll, Colors.cyan, "Sondage", widget.onPollTap),
                _buildAction(Icons.person, Colors.blueAccent, "Contact", widget.onContactTap),
                _buildAction(Icons.music_note, Colors.redAccent, "Musique", widget.onMusicTap),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAction(IconData icon, Color color, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 70,
        child: Column(
          children: [
            Container(
              height: 55, width: 55,
              decoration: BoxDecoration(
                shape: BoxShape.circle, 
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  colors: [color.withOpacity(0.6), color]
                )
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}