import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lualaba_konnect/core/app_navigator.dart';

class FullScreenIntentService {
  static const MethodChannel _channel = MethodChannel(
    'lualaba_konnect/sos_launch',
  );

  static bool _promptShownThisSession = false;
  static bool _promptInProgress = false;

  static Future<bool> canUseFullScreenIntent() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      final allowed = await _channel.invokeMethod<bool>(
        'canUseFullScreenIntent',
      );
      return allowed ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> openSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openFullScreenIntentSettings',
      );
      return opened ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> promptIfNeeded() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_promptShownThisSession) return;
    if (_promptInProgress) return;
    final allowed = await canUseFullScreenIntent();
    if (allowed) return;

    _promptInProgress = true;
    try {
      await AppNavigator.runWhenReady(() async {
        await Future.delayed(const Duration(milliseconds: 700));
        final context = appNavigatorKey.currentContext;
        if (context == null) return;
        if (!context.mounted) return;

        final openSettingsNow = await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          barrierDismissible: true,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Activer les alertes SOS plein ecran'),
              content: const Text(
                'Sur Android 14 et plus, autorise les notifications plein ecran '
                'pour que les SOS puissent sonner et reveiller l ecran meme si '
                'le telephone est verrouille.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Plus tard'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Ouvrir les reglages'),
                ),
              ],
            );
          },
        );

        if (openSettingsNow == true) {
          _promptShownThisSession = true;
          await openSettings();
        } else if (openSettingsNow == false) {
          _promptShownThisSession = true;
        }
      });
    } finally {
      _promptInProgress = false;
    }
  }
}
