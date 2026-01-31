import 'package:flutter/material.dart';

class ThemeState {
  ThemeState._private();
  static final ThemeState instance = ThemeState._private();
  final ValueNotifier<bool> isDark = ValueNotifier<bool>(false);
}
