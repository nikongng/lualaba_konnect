import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:lualaba_konnect/core/notification_service.dart';
import 'health_user_context.dart';

class HealthNotificationScheduler {
  static Future<void> refreshForUser(HealthUserContext contextRef) async {
    if (kIsWeb) return;
    await NotificationService.initLocalOnly();

    final userSnap = await contextRef.userRef.get();
    final data = userSnap.data() ?? <String, dynamic>{};
    final health = (data['health'] is Map) ? Map<String, dynamic>.from(data['health'] as Map) : <String, dynamic>{};
    final medsEnabled = health['medicationNotifications'] == true;
    final apptEnabled = health['appointmentNotifications'] == true;
    final pharmacyEnabled = health['pharmacyNotifications'] != false;

    if (medsEnabled) {
      await _scheduleMedications(contextRef);
    }
    if (apptEnabled) {
      await _scheduleAppointments(contextRef);
    }
    if (pharmacyEnabled) {
      await _syncPharmacyAlerts(contextRef, health);
    } else {
      await _syncPharmacyAlertCache(
        contextRef,
        existing: _stringMap(health['pharmacyAlertSignatures']),
        next: const <String, String>{},
      );
    }
  }

  static Future<void> _scheduleMedications(HealthUserContext contextRef) async {
    final now = DateTime.now();
    final medsSnap = await contextRef.subCollection('health_medications').where('active', isEqualTo: true).get();

    for (final doc in medsSnap.docs) {
      final data = doc.data();
      final name = (data['name'] ?? '').toString().trim();
      final schedule = (data['schedule'] ?? '').toString();
      final start = _toDate(data['startDate']);
      final end = _toDate(data['endDate']);

      final times = _parseTimes(schedule);
      final List<_ClockTime> scheduleTimes = times.isEmpty ? <_ClockTime>[const _ClockTime(8, 0)] : times;

      for (int dayOffset = 0; dayOffset <= 1; dayOffset++) {
        for (int i = 0; i < scheduleTimes.length; i++) {
          final t = scheduleTimes[i];
          final target = DateTime(
            now.year,
            now.month,
            now.day + dayOffset,
            t.hour,
            t.minute,
          );

          if (start != null && target.isBefore(_dayStart(start))) continue;
          if (end != null && target.isAfter(_dayEnd(end))) continue;
          if (target.isBefore(now)) continue;

          final idKey =
              'med:${doc.id}:${target.year}${target.month.toString().padLeft(2, '0')}${target.day.toString().padLeft(2, '0')}:${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}';
          await NotificationService.scheduleNotification(
            id: NotificationService.stableIdForKey(idKey),
            title: 'Rappel medicament',
            body: name.isNotEmpty ? 'Prise: $name' : 'Vous avez un medicament a prendre',
            scheduledAt: target,
            payload: 'health_meds',
          );
        }
      }
    }
  }

  static Future<void> _scheduleAppointments(HealthUserContext contextRef) async {
    final now = DateTime.now();
    final snap = await contextRef
        .subCollection('health_appointments')
        .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final status = (data['status'] ?? 'scheduled').toString();
      if (status == 'canceled' || status == 'completed') continue;

      final when = _toDate(data['dateTime']);
      if (when == null) continue;

      final doctor = (data['doctor'] ?? '').toString().trim();
      final hospital = (data['hospital'] ?? '').toString().trim();
      final reason = (data['reason'] ?? '').toString().trim();
      final detail = _joinParts(<String>[reason, doctor, hospital]);

      final atId = NotificationService.stableIdForKey('appt:${doc.id}:at');
      await NotificationService.scheduleNotification(
        id: atId,
        title: 'Rendez-vous medical',
        body: detail.isNotEmpty ? detail : 'Vous avez un rendez-vous medical',
        scheduledAt: when,
        payload: 'health_appointment',
      );

      final reminder = when.subtract(const Duration(hours: 1));
      if (reminder.isAfter(now)) {
        final beforeId = NotificationService.stableIdForKey('appt:${doc.id}:before');
        await NotificationService.scheduleNotification(
          id: beforeId,
          title: 'Rappel rendez-vous',
          body: detail.isNotEmpty ? detail : 'Rendez-vous dans 1 heure',
          scheduledAt: reminder,
          payload: 'health_appointment',
        );
      }
    }
  }

  static Future<void> _syncPharmacyAlerts(
    HealthUserContext contextRef,
    Map<String, dynamic> health,
  ) async {
    final existingCache = _stringMap(health['pharmacyAlertSignatures']);
    final nextCache = <String, String>{};
    final snap = await FirebaseFirestore.instance
        .collection('health_pharmacies')
        .where('ownerId', isEqualTo: contextRef.userId)
        .get();

    for (final doc in snap.docs) {
      final alert = _buildPharmacyAlert(doc.data());
      if (!alert.hasAlert) continue;

      nextCache[doc.id] = alert.signature;
      if (existingCache[doc.id] == alert.signature) continue;

      await NotificationService.showNotification(
        alert.title,
        alert.body,
        payload: 'health_pharmacy_alert',
        id: NotificationService.stableIdForKey('health_pharmacy_alert:${doc.id}'),
      );
    }

    await _syncPharmacyAlertCache(
      contextRef,
      existing: existingCache,
      next: nextCache,
    );
  }

  static Future<void> _syncPharmacyAlertCache(
    HealthUserContext contextRef, {
    required Map<String, String> existing,
    required Map<String, String> next,
  }) async {
    if (_sameStringMap(existing, next)) return;
    await contextRef.userRef.set(
      {
        'health.pharmacyAlertSignatures': next,
      },
      SetOptions(merge: true),
    );
  }

  static DateTime? _toDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    final s = raw?.toString() ?? '';
    return DateTime.tryParse(s);
  }

  static List<_ClockTime> _parseTimes(String input) {
    final matches = RegExp(r'(\d{1,2})[:hH](\d{2})').allMatches(input);
    final out = <_ClockTime>[];
    for (final m in matches) {
      final h = int.tryParse(m.group(1) ?? '');
      final min = int.tryParse(m.group(2) ?? '');
      if (h == null || min == null) continue;
      if (h < 0 || h > 23 || min < 0 || min > 59) continue;
      out.add(_ClockTime(h, min));
    }
    return out;
  }

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day, 0, 0, 0);
  static DateTime _dayEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

  static String _joinParts(List<String> parts) {
    final out = parts.where((p) => p.trim().isNotEmpty).toList();
    return out.join(' / ');
  }

  static Map<String, String> _stringMap(dynamic raw) {
    if (raw is! Map) return <String, String>{};
    final out = <String, String>{};
    raw.forEach((key, value) {
      final normalizedKey = key.toString().trim();
      final normalizedValue = value?.toString().trim() ?? '';
      if (normalizedKey.isEmpty || normalizedValue.isEmpty) return;
      out[normalizedKey] = normalizedValue;
    });
    return out;
  }

  static bool _sameStringMap(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static _PharmacyInventoryAlert _buildPharmacyAlert(Map<String, dynamic> pharmacy) {
    final pharmacyName = _safeStr(pharmacy['name']).isNotEmpty ? _safeStr(pharmacy['name']) : 'Pharmacie';
    final catalog = _pharmacyCatalogFromRaw(
      pharmacy['medicineCatalog'] ??
          pharmacy['catalog'] ??
          pharmacy['inventory'] ??
          pharmacy['stock'] ??
          pharmacy['products'] ??
          pharmacy['medicines'] ??
          pharmacy['medications'] ??
          pharmacy['medicaments'],
    );
    final expiredNames = <String>{};
    final outOfStockNames = <String>{};
    final now = DateTime.now();

    for (final medicine in catalog) {
      final name = _safeStr(medicine['name'] ?? medicine['medicament'] ?? medicine['label']);
      if (name.isEmpty) continue;

      final stock = _toInt(medicine['stock']) ?? 0;
      if (stock <= 0) {
        outOfStockNames.add(name);
      }

      final expiry = _parseExpiryDate(
        medicine['expiryDate'] ?? medicine['expiry'] ?? medicine['expiration'] ?? medicine['peremption'],
      );
      if (expiry != null && expiry.isBefore(now)) {
        expiredNames.add(name);
      }
    }

    final expired = expiredNames.toList()..sort();
    final outOfStock = outOfStockNames.toList()..sort();
    final signature = _alertSignature(expired: expired, outOfStock: outOfStock);
    if (signature.isEmpty) {
      return const _PharmacyInventoryAlert.empty();
    }

    final parts = <String>[];
    if (expired.isNotEmpty) {
      parts.add('${expired.length} perime(s): ${_summarizeNames(expired)}');
    }
    if (outOfStock.isNotEmpty) {
      parts.add('${outOfStock.length} en rupture: ${_summarizeNames(outOfStock)}');
    }

    final title = expired.isNotEmpty && outOfStock.isNotEmpty
        ? 'Alerte pharmacie'
        : expired.isNotEmpty
            ? 'Produit perime'
            : 'Rupture de stock';

    return _PharmacyInventoryAlert(
      title: title,
      body: '$pharmacyName: ${parts.join(' / ')}',
      signature: signature,
    );
  }

  static String _alertSignature({
    required List<String> expired,
    required List<String> outOfStock,
  }) {
    final expiredKey = expired.join('|');
    final outOfStockKey = outOfStock.join('|');
    if (expiredKey.isEmpty && outOfStockKey.isEmpty) return '';
    return 'exp:$expiredKey||out:$outOfStockKey';
  }

  static String _summarizeNames(List<String> names, {int max = 3}) {
    if (names.length <= max) return names.join(', ');
    final visible = names.take(max).join(', ');
    return '$visible (+${names.length - max})';
  }

  static List<Map<String, dynamic>> _pharmacyCatalogFromRaw(dynamic raw) {
    if (raw == null) return const <Map<String, dynamic>>[];
    if (raw is List) {
      final out = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map) {
          out.add(item.map((key, value) => MapEntry(key.toString(), value)));
        } else {
          final name = _safeStr(item);
          if (name.isEmpty) continue;
          out.add(<String, dynamic>{'name': name, 'stock': 0, 'expiryDate': ''});
        }
      }
      return out;
    }
    if (raw is Map) {
      return _pharmacyCatalogFromRaw(<dynamic>[raw]);
    }
    final text = _safeStr(raw);
    if (text.isEmpty) return const <Map<String, dynamic>>[];
    return text
        .split(',')
        .map((item) => _safeStr(item))
        .where((item) => item.isNotEmpty)
        .map((item) => <String, dynamic>{'name': item, 'stock': 0, 'expiryDate': ''})
        .toList(growable: false);
  }

  static int? _toInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString().trim());
  }

  static String _safeStr(dynamic value) => (value ?? '').toString().trim();

  static DateTime? _parseExpiryDate(dynamic raw) {
    final value = _safeStr(raw);
    if (value.isEmpty) return null;

    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;

    for (final pattern in const <String>[
      'dd/MM/yyyy',
      'd/M/yyyy',
      'dd-MM-yyyy',
      'd-M-yyyy',
      'dd.MM.yyyy',
      'd.MM.yyyy',
    ]) {
      try {
        return DateFormat(pattern).parseStrict(value);
      } catch (_) {}
    }
    return null;
  }
}

class _ClockTime {
  final int hour;
  final int minute;
  const _ClockTime(this.hour, this.minute);
}

class _PharmacyInventoryAlert {
  final String title;
  final String body;
  final String signature;

  const _PharmacyInventoryAlert({
    required this.title,
    required this.body,
    required this.signature,
  });

  const _PharmacyInventoryAlert.empty()
      : title = '',
        body = '',
        signature = '';

  bool get hasAlert => signature.isNotEmpty;
}
