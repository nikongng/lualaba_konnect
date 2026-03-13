import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;
import 'package:lualaba_konnect/core/supabase_service.dart';
import 'health_user_context.dart';

class HealthDocumentsPage extends StatefulWidget {
  final HealthUserContext contextRef;

  const HealthDocumentsPage({
    super.key,
    required this.contextRef,
  });

  @override
  State<HealthDocumentsPage> createState() => _HealthDocumentsPageState();
}

class _HealthDocumentsPageState extends State<HealthDocumentsPage> {
  CollectionReference<Map<String, dynamic>> get _docsRef =>
      widget.contextRef.subCollection('health_documents');

  bool _uploading = false;
  String? _analyzingId;
  final Map<String, String> _analysisProgress = <String, String>{};

  Future<void> _pickAndUpload() async {
    if (!SupabaseService.isInitialized) {
      _snack('Supabase non initialise.', error: true);
      return;
    }
    setState(() => _uploading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _uploading = false);
        return;
      }

      final file = result.files.first;
      final name = file.name;

      final bytes =
          file.bytes ?? (file.path != null ? await File(file.path!).readAsBytes() : null);

      if (bytes == null) {
        throw Exception('Impossible de lire le fichier');
      }

      final mime = _mimeFromName(name);

      final objectPath =
          'health_docs/${widget.contextRef.userId}/${DateTime.now().millisecondsSinceEpoch}_$name';

      String url;

      if (!kIsWeb && file.path != null) {
        url = await SupabaseService.uploadFileNamed(
          File(file.path!),
          objectPath,
          'health_docs',
          contentType: mime,
        );
      } else {
        url = await SupabaseService.uploadBytesNamed(
          bytes,
          objectPath,
          'health_docs',
          contentType: mime,
        );
      }

      await _docsRef.add({
        'name': name,
        'url': url,
        'mime': mime,
        'size': bytes.length,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await widget.contextRef.userRef.set(
        {
          'health.documents': FieldValue.arrayUnion([name]),
          'health.documentHistory': FieldValue.arrayUnion([name]),
        },
        SetOptions(merge: true),
      );

      _snack('Document ajoute');
    } catch (e) {
      _snack('Erreur upload document: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _analyzeDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    if (_analyzingId != null) return;

    setState(() => _analyzingId = doc.id);

    try {
      final data = doc.data();
      final url = (data['url'] ?? '').toString();
      final mime = (data['mime'] ?? '').toString();

      if (url.isEmpty) throw Exception('URL manquant');

      final bytes = await _downloadBytes(url);

      final text = await _extractText(
        bytes,
        mime,
        onPdfPage: (current, total) {
          if (!mounted || _analyzingId != doc.id) return;

          setState(() => _analysisProgress[doc.id] = 'Page $current/$total');
        },
      );

      if (text.trim().isEmpty) {
        if (kIsWeb) {
          throw Exception('Analyse non disponible sur Web pour ce format');
        }

        throw Exception(
            'Aucun texte detecte. PDF probablement scanne: essayez une image ou un PDF texte.');
      }

      final summary = await _summarizeWithGemini(text);

      await doc.reference.set(
        {
          'analysisText': text,
          'analysisSummary': summary,
          'analysisAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      _snack('Analyse terminee');
    } catch (e) {
      _snack('Erreur analyse: $e', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _analyzingId = null;
          _analysisProgress.remove(doc.id);
        });
      }
    }
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final resp = await http.get(Uri.parse(url));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Telechargement echoue (${resp.statusCode})');
    }

    return resp.bodyBytes;
  }

  Future<String> _extractText(
    Uint8List bytes,
    String mime, {
    void Function(int current, int total)? onPdfPage,
  }) async {
    final lower = mime.toLowerCase();

    if (lower.contains('pdf')) {
      return _extractPdfText(bytes, onPage: onPdfPage);
    }

    if (lower.contains('image')) {
      return _extractImageText(bytes);
    }

    return '';
  }

  Future<String> _extractPdfText(
    Uint8List bytes, {
    void Function(int current, int total)? onPage,
  }) async {
    String text = '';

    try {
      final doc = syncfusion.PdfDocument(inputBytes: bytes);
      final extractor = syncfusion.PdfTextExtractor(doc);

      text = extractor.extractText();

      doc.dispose();
    } catch (_) {
      text = '';
    }

    if (text.trim().isNotEmpty) return text;

    if (kIsWeb) return '';

    try {
      final pdfDoc = await pdfx.PdfDocument.openData(bytes);

      final pageCount = pdfDoc.pagesCount;

      final maxPages = pageCount;

      final buffer = StringBuffer();

      for (var i = 1; i <= maxPages; i++) {
        onPage?.call(i, maxPages);

        final page = await pdfDoc.getPage(i);

        final pageImage = await page.render(
          width: page.width,
          height: page.height,
          format: pdfx.PdfPageImageFormat.png,
        );

        await page.close();

        if (pageImage != null) {
          final ocrText = await _extractImageText(pageImage.bytes);

          if (ocrText.trim().isNotEmpty) {
            buffer.writeln(ocrText);
          }
        }
      }

      await pdfDoc.close();

      return buffer.toString();
    } catch (_) {
      return '';
    }
  }

  Future<String> _extractImageText(Uint8List bytes) async {
    if (kIsWeb) return '';

    final dir = await getTemporaryDirectory();

    final file = File(
        '${dir.path}/health_doc_${DateTime.now().millisecondsSinceEpoch}.jpg');

    await file.writeAsBytes(bytes);

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

    final input = InputImage.fromFilePath(file.path);

    final recognized = await recognizer.processImage(input);

    await recognizer.close();

    return recognized.text;
  }

  Future<String> _summarizeWithGemini(String text) async {
    final apiKey = dotenv.maybeGet('GEMINI_API_KEY') ?? '';

    if (apiKey.isEmpty) return '';

    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );

    final clean = text.trim();

    final sample = clean.length > 8000 ? clean.substring(0, 8000) : clean;

    final prompt = [
      'Tu es un assistant medical.',
      'Resume ce document medical en francais, en 5-7 points courts.',
      'Texte:',
      sample,
    ].join('\n');

    final response = await model.generateContent([Content.text(prompt)]);

    return response.text?.trim() ?? '';
  }

  String _mimeFromName(String name) {
    final lower = name.toLowerCase();

    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';

    return 'application/octet-stream';
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : Colors.black87,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents medicaux'),
        actions: [
          if (_uploading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _pickAndUpload,
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _docsRef.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('Aucun document'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final doc = docs[i];

              final data = doc.data();

              final name = (data['name'] ?? '').toString();

              final summary = (data['analysisSummary'] ?? '').toString();

              final analyzing = _analyzingId == doc.id;

              final progress = _analysisProgress[doc.id];

              return ListTile(
                title: Text(name.isEmpty ? 'Document' : name),
                subtitle: Text(
                  analyzing && progress != null
                      ? 'Analyse en cours: $progress'
                      : (summary.isNotEmpty
                          ? summary
                          : 'Analyse non disponible'),
                ),
                trailing: analyzing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _analyzeDoc(doc),
                            icon: const Icon(Icons.psychology_outlined),
                          ),
                          IconButton(
                            onPressed: () => doc.reference.delete(),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
              );
            },
          );
        },
      ),
    );
  }
}