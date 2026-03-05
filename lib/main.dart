import 'package:flutter/material.dart';

import 'screens/devices_screen.dart';

void main() {
  runApp(const MyApp());
}

/// Modern dark theme color palette
class TerminalColors {
  static const Color background = Color(0xFF121218);
  static const Color surface = Color(0xFF1E1E26);
  static const Color surfaceLight = Color(0xFF2A2A35);
  static const Color primary = Color(0xFF5DADE2); // Soft teal/cyan
  static const Color primaryDim = Color(0xFF3498DB); // Deeper blue
  static const Color accent = Color(0xFF58D68D); // Soft green for success
  static const Color red = Color(0xFFE74C3C); // Softer red
  static const Color yellow = Color(0xFFF4D03F); // Warmer yellow
  static const Color cyan = Color(0xFF5DADE2); // Teal accent
  static const Color text = Color(0xFFE8E8E8); // Light text
  static const Color textDim = Color(0xFFB0B0B0); // Dimmed text
  static const Color grey = Color(0xFF6C6C7A); // Muted grey

  // Semantic aliases
  static const Color green = accent;
  static const Color greenDim = Color(0xFF45B39D);
  static const Color greenBright = accent;
  static const Color white = text;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhalePi',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: TerminalColors.background,
        colorScheme: ColorScheme.dark(
          primary: TerminalColors.primary,
          secondary: TerminalColors.primaryDim,
          surface: TerminalColors.surface,
          onPrimary: TerminalColors.background,
          onSecondary: TerminalColors.background,
          onSurface: TerminalColors.text,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: TerminalColors.surface,
          foregroundColor: TerminalColors.text,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: TerminalColors.text,
          ),
          iconTheme: IconThemeData(color: TerminalColors.primary),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.text,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.text,
          ),
          bodySmall: TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.textDim,
          ),
          titleLarge: TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.text,
          ),
          titleMedium: TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.text,
          ),
          labelLarge: TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.text,
          ),
        ),
        iconTheme: const IconThemeData(color: TerminalColors.primary),
        listTileTheme: const ListTileThemeData(
          textColor: TerminalColors.text,
          iconColor: TerminalColors.primary,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: TerminalColors.surfaceLight,
            foregroundColor: TerminalColors.primary,
            side: const BorderSide(color: TerminalColors.primary),
            textStyle: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: TerminalColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: TerminalColors.grey),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: TerminalColors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
              color: TerminalColors.primary,
              width: 2,
            ),
          ),
          hintStyle: const TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.grey,
          ),
          labelStyle: const TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.textDim,
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: TerminalColors.surfaceLight,
          contentTextStyle: TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.text,
          ),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: TerminalColors.surface,
          titleTextStyle: TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.text,
            fontSize: 18,
          ),
          contentTextStyle: TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.text,
          ),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: TerminalColors.surface,
          textStyle: TextStyle(
            fontFamily: 'monospace',
            color: TerminalColors.text,
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: TerminalColors.primary,
        ),
        useMaterial3: true,
      ),
      home: const DevicesScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
