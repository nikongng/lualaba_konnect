import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Widgets pour la page profil
class ProfilePageWidgets {
  static Widget buildActionTile(String title, String sub, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.5), width: 1.5)),
      child: Row(children: [
        CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
        const SizedBox(width: 15),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ])),
        const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      ]),
    );
  }

  static Widget buildPremiumCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF0F171A), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Row(children: [
              Icon(Icons.wifi, color: Colors.greenAccent, size: 20),
              SizedBox(width: 8),
              Text("Lualaba Premium", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8)), child: const Text("Actif", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 15),
          const Text("Data LAN Utilisée : 45GB / Illimité", style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: 0.45, backgroundColor: Colors.white10, color: Colors.orange.withOpacity(0.8), minHeight: 6),
          const SizedBox(height: 15),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("Accès prioritaire activé", style: TextStyle(color: Colors.white38, fontSize: 11)),
            Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 12),
          ]),
        ],
      ),
    );
  }

  static Widget sectionTitle(String title, Color color) {
    return Padding(padding: const EdgeInsets.only(left: 8, bottom: 12), child: Text(title, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)));
  }

  static Widget settingsTile(IconData icon, String title, Color bg, Color text, {String? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: Icon(icon, color: text.withOpacity(0.7)),
        title: Text(title, style: TextStyle(color: text, fontSize: 15)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (trailing != null) Text(trailing, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          const SizedBox(width: 5),
          const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        ]),
      ),
    );
  }

  static Widget settingsSwitchTile(IconData icon, String title, bool value, Color bg, Color text, [Function(bool)? onChanged]) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: Icon(icon, color: text.withOpacity(0.7)),
        title: Text(title, style: TextStyle(color: text, fontSize: 15)),
        trailing: CupertinoSwitch(value: value, activeTrackColor: Colors.orange, onChanged: onChanged ?? (v){}),
      ),
    );
  }

  static Widget logoutButton() {
    return Center(
      child: TextButton.icon(
        onPressed: () => FirebaseAuth.instance.signOut(),
        icon: const Icon(Icons.logout, color: Colors.redAccent),
        label: const Text("Se déconnecter", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}