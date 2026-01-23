import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lualaba_konnect/features/auth/presentation/pages/AuthMainPage.dart';

class FinalSummaryDialog extends StatefulWidget {
  final bool autoValidated;
  final String? customMessage;
  final bool isError;
  final bool showRetryUploads;
  final Function? onRetryUploads;

  const FinalSummaryDialog({
    super.key,
    required this.autoValidated,
    this.customMessage,
    this.isError = false,
    this.showRetryUploads = false,
    this.onRetryUploads,
  });

  @override
  State<FinalSummaryDialog> createState() => _FinalSummaryDialogState();
}

class _FinalSummaryDialogState extends State<FinalSummaryDialog> {
  bool _isRetrying = false;

  Future<void> _handleRetry() async {
    if (widget.onRetryUploads != null) {
      setState(() => _isRetrying = true);
      Navigator.of(context).pop(); // Fermer le dialog
      await widget.onRetryUploads!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
      backgroundColor: Colors.transparent,
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
              height: 90, width: 90,
              decoration: BoxDecoration(
                color: widget.isError ? Colors.red.shade50 : (widget.autoValidated ? Colors.green.shade50 : Colors.blue.shade50),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(widget.isError ? "❌" : (widget.autoValidated ? "🥰" : "😎"), style: const TextStyle(fontSize: 50)),
              ),
            ),
            const SizedBox(height: 25),
            Text(
              widget.isError ? (widget.customMessage ?? "Une erreur est survenue.") : (widget.autoValidated ? "Certification lancée !" : "Dossier en route !"),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFFE65100)),
            ),
            const SizedBox(height: 15),
            // If there was a partial upload failure to Supabase, show a specific message
            if (widget.showRetryUploads && !widget.isError)
              Text(
                "L'envoi de vos fichiers a échoué, veuillez réessayer.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.red.shade700, height: 1.4, fontWeight: FontWeight.w700),
              )
            else if (!widget.isError)
              Text(
                widget.autoValidated
                  ? "Check terminé ! Tes documents sont validés. Nous finalisons ta certification maintenant."
                  : "Tes documents ont été envoyés avec succès. Nous vérifions tout ça tout de suite.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600, height: 1.4, fontWeight: FontWeight.w500),
              )
            else const SizedBox.shrink(),
            const SizedBox(height: 20),
            // Show retry button ONLY when Supabase upload failed (indicated by showRetryUploads)
            if (widget.showRetryUploads && !widget.isError) ...[
              SizedBox(
                height: 50,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isRetrying ? null : _handleRetry,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: _isRetrying
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Réessayer l\'envoi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
            ],

            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.of(context).pop(); // Fermer le Dialog
                if (!widget.isError) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthMainPage()),
                    (route) => false,
                  );
                }
              },
              child: Container(
                height: 60, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: !widget.isError ? const LinearGradient(colors: [Color(0xFFF57C00), Color(0xFFE65100)]) : null,
                  color: widget.isError ? Colors.orange.shade700 : null,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text("Se connecter", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showFinalSummaryDialog(
  BuildContext context, {
  required bool autoValidated,
  String? customMessage,
  bool isError = false,
  bool showRetryUploads = false,
  Function? onRetryUploads,
}) async {
  HapticFeedback.vibrate();

  // Petite pause pour s'assurer que le loader est bien retiré
  await Future.delayed(const Duration(milliseconds: 200));

  if (!context.mounted) return;

  debugPrint("Affichage du dialog final");
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => FinalSummaryDialog(
      autoValidated: autoValidated,
      customMessage: customMessage,
      isError: isError,
      showRetryUploads: showRetryUploads,
      onRetryUploads: onRetryUploads,
    ),
  );
}
