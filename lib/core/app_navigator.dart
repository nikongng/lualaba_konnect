import 'package:flutter/material.dart';
import 'dart:async';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class AppNavigator {
  static Future<T?> pushWhenReady<T>(Route<T> route, {Duration timeout = const Duration(seconds: 8)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final nav = appNavigatorKey.currentState;
      if (nav != null) return nav.push<T>(route);
      await Future.delayed(const Duration(milliseconds: 60));
    }
    return null;
  }

  static Future<void> runWhenReady(FutureOr<void> Function() action, {Duration timeout = const Duration(seconds: 8)}) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final ctx = appNavigatorKey.currentContext;
      if (ctx != null) {
        await action();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }
}
