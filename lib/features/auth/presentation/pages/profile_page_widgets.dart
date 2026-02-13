import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui'; 

class ProfilePageWidgets {
  // --- TUILE D'ACTION (S'adapte au thème Dark/Light) ---
  static Widget buildActionTile(String title, String sub, IconData icon, Color color, bool isDark, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E3E3B).withOpacity(0.5) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? color.withOpacity(0.2) : color.withOpacity(0.5), 
          width: 1.5
        ),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.1), 
            child: Icon(icon, color: color)
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, 
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87)),
                Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ]
            )
          ),
          Icon(Icons.arrow_forward_ios, size: 14, color: isDark ? Colors.white38 : Colors.grey),
        ],
      ),
      ),
    );
  }

  // --- CARTE PREMIUM ---
  static Widget buildPremiumCard(
    bool isDark,
    Color textColor, {
    required double usedGb,
    double? totalGb,
    String? sourceLabel,
    DateTime? updatedAt,
    bool isRefreshing = false,
    VoidCallback? onRefresh,
  }) {
    final bg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final accent = Colors.orange;
    final iconColor = isDark ? Colors.greenAccent : Colors.green;
    final subtitleColor = isDark ? Colors.white70 : Colors.black54;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween, 
            children: [
              Row(
                children: [
                  Icon(Icons.wifi_tethering, color: iconColor, size: 22),
                  const SizedBox(width: 10),
                  Text("Lualaba Premium", style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
                ]
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                    decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(10)), 
                    child: const Text("ACTIF", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onRefresh,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white10 : Colors.black12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: isRefreshing
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.refresh, size: 16, color: textColor.withOpacity(0.8)),
                    ),
                  ),
                ],
              ),
            ]
          ),
          const SizedBox(height: 20),
          Text(_formatDataLabel(usedGb, totalGb, sourceLabel: sourceLabel, updatedAt: updatedAt), style: TextStyle(color: _statusColor(subtitleColor, sourceLabel), fontSize: 12)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _progressValue(usedGb, totalGb), 
              backgroundColor: isDark ? Colors.white10 : Colors.grey[200], 
              color: accent, 
              minHeight: 8
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween, 
            children: [
              Text("Accès prioritaire au réseau activé", style: TextStyle(color: subtitleColor.withOpacity(0.9), fontSize: 11)),
              Icon(Icons.verified_user_outlined, color: subtitleColor.withOpacity(0.9), size: 14),
            ]
          ),
        ],
      ),
    );
  }

  static String _formatDataLabel(double usedGb, double? totalGb, {String? sourceLabel, DateTime? updatedAt}) {
    String used = _formatSize(usedGb);
    String suffix = '';
    if (updatedAt != null) {
      final y = updatedAt.year.toString().padLeft(4, '0');
      final m = updatedAt.month.toString().padLeft(2, '0');
      final d = updatedAt.day.toString().padLeft(2, '0');
      final hh = updatedAt.hour.toString().padLeft(2, '0');
      final mm = updatedAt.minute.toString().padLeft(2, '0');
      suffix = " (MàJ: $y-$m-$d $hh:$mm)";
    }
    if (sourceLabel != null && sourceLabel.isNotEmpty) {
      final src = sourceLabel.toLowerCase() == 'live' ? 'live' : 'cache';
      suffix = "$suffix [$src]";
    }
    if (totalGb == null || !totalGb.isFinite || totalGb <= 0) {
      return "Data LAN Utilisée : $used / Illimité$suffix";
    }
    String total = _formatSize(totalGb);
    return "Data LAN Utilisée : $used / $total$suffix";
  }

  static double _progressValue(double usedGb, double? totalGb) {
    if (totalGb == null || !totalGb.isFinite || totalGb <= 0) return 0.0;
    final v = usedGb / totalGb;
    if (!v.isFinite) return 0.0;
    return v.clamp(0.0, 1.0);
  }

  static String _formatSize(double? gb) {
    if (gb == null || !gb.isFinite) return "0.00GB";
    if (gb < 1) {
      final mb = gb * 1024;
      return "${mb.toStringAsFixed(0)}MB";
    }
    return "${gb.toStringAsFixed(2)}GB";
  }

  static Color _statusColor(Color base, String? sourceLabel) {
    if (sourceLabel == null || sourceLabel.isEmpty) return base;
    if (sourceLabel.toLowerCase() == 'live') return Colors.greenAccent;
    return base;
  }

  // --- TITRE DE SECTION ---
  static Widget sectionTitle(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12, top: 10), 
      child: Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5))
    );
  }

  // --- TUILES DE RÉGLAGES ---
  static Widget settingsTile(IconData icon, String title, Color bg, Color text, {String? trailing, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: text.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: text.withOpacity(0.8), size: 20)
        ),
        title: Text(title, style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w500)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min, 
          children: [
            if (trailing != null) Text(trailing, style: const TextStyle(color: Color(0xFF00CBA9), fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
          ]
        ),
      ),
    );
  }

  static Widget settingsSwitchTile(IconData icon, String title, bool value, Color bg, Color text, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: text.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: text.withOpacity(0.8), size: 20)
        ),
        title: Text(title, style: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w500)),
        trailing: CupertinoSwitch(
          value: value, 
          activeTrackColor: const Color(0xFF00CBA9), 
          onChanged: onChanged
        ),
      ),
    );
  }

  // --- BOUTON DE DÉCONNEXION (Appelé depuis le Dashboard) ---
  static Widget logoutButton(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: ElevatedButton.icon(
        onPressed: () => _showModernLogoutDialog(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.redAccent.withOpacity(0.1),
          foregroundColor: Colors.redAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          side: BorderSide(color: Colors.redAccent.withOpacity(0.3), width: 1),
        ),
        icon: const Icon(Icons.power_settings_new_rounded, size: 20),
        label: const Text("Déconnexion", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 13)),
      ),
    );
  }

  // --- DIALOGUE ELITE (Look Dark Premium avec logo.png) ---
  static void _showModernLogoutDialog(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color cardBg = isDark ? const Color(0xFF0F171A) : Colors.white;
    final Color text = isDark ? Colors.white : Colors.black87;
    final Color sub = isDark ? Colors.white.withOpacity(0.5) : Colors.black54;
    final Color border = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(isDark ? 0.8 : 0.3),
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, child) {
        final curvedValue = Curves.easeOutBack.transform(anim1.value);
        
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6 * anim1.value, sigmaY: 6 * anim1.value),
          child: Transform.scale(
            scale: curvedValue,
            child: Opacity(
              opacity: anim1.value,
              child: AlertDialog(
                backgroundColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
                content: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: cardBg.withOpacity(isDark ? 0.95 : 1.0),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: border, width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 35),
                      
                      // LOGO PERSONNEL
                      Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.orange.withOpacity(0.15), blurRadius: 40, spreadRadius: 2)
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/logo.png',
                            width: 70,
                            height: 70,
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, stack) => const Icon(Icons.wifi_tethering, color: Colors.orange, size: 50),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 25),
                      Text(
                        "LUALABA KONNECT",
                        style: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 4),
                      ),
                      const SizedBox(height: 15),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: Text(
                          "Souhaitez-vous vraiment quitter\nvotre espace sécurisé ?",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: sub, fontSize: 13, height: 1.6),
                        ),
                      ),
                      const SizedBox(height: 40),
                      
                      // BOUTONS D'ACTION
                      Container(
                        height: 70,
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: border)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => Navigator.pop(context),
                                child: Center(
                                  child: Text("RESTER", style: TextStyle(color: sub, fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                            ),
                            VerticalDivider(color: border, width: 1),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  // Nettoyage SharedPreferences
                                  final prefs = await SharedPreferences.getInstance();
                                  await prefs.setBool('remember_me', false);
                                  
                                  // Déconnexion Firebase
                                  await FirebaseAuth.instance.signOut();
                                  
                                  if (context.mounted) {
                                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                                  }
                                },
                                child: const Center(
                                  child: Text("DÉCONNEXION", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
