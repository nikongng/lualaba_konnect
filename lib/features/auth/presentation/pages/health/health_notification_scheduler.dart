import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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

    if (medsEnabled) {
      await _scheduleMedications(contextRef);
    }
    if (apptEnabled) {
      await _scheduleAppointments(contextRef);
    }
  }

  static Future<void> _scheduleMedications(HealthUserContext contextRef) async {
    final now = DateTime.now();
    final medsSnap = await contextRef
        .subCollection('health_medications')
        .where('active', isEqualTo: true)
        .get();

    for (final doc in medsSnap.docs) {
      final data = doc.data();
      final name = (data['name'] ?? '').toString().trim();
      final schedule = (data['schedule'] ?? '').toString();
      final start = _toDate(data['startDate']);
      final end = _toDate(data['endDate']);

      final times = _parseTimes(schedule);
      final List<_ClockTime> scheduleTimes = times.isEmpty ? [_ClockTime(8, 0)] : times;

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

          final idKey = 'med:${doc.id}:${target.year}${target.month.toString().padLeft(2, '0')}${target.day.toString().padLeft(2, '0')}:${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}';
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
      final detail = _joinParts([reason, doctor, hospital]);

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
    return out.join(' • ');
  }
}

class _ClockTime {
  final int hour;
  final int minute;
  const _ClockTime(this.hour, this.minute);
}
