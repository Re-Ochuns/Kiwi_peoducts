import 'package:flutter/material.dart';

abstract final class AppColors {
  static const green = Color(0xFF205C3B);
  static const ink = Color(0xFF1A1D1B);
  static const line = Color(0xFFCBD1CD);
  static const background = Color(0xFFF7F8F7);
  static const mutedText = Color(0xFF56605A);
  static const error = Color(0xFFB3261E);
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class AppRadius {
  static const double control = 6;
  static const double modal = 8;
}

ThemeData buildAppTheme({String? fontFamily}) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.green,
        surface: AppColors.background,
      ).copyWith(
        primary: AppColors.green,
        onPrimary: Colors.white,
        onSurface: AppColors.ink,
        outline: AppColors.line,
        error: AppColors.error,
      );

  return ThemeData.from(colorScheme: scheme).copyWith(
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.line,
    textTheme: ThemeData.light().textTheme.apply(
      fontFamily: fontFamily,
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: Colors.white,
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: const BorderSide(color: Color(0xFF8D9690)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    dialogTheme: const DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.modal)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
      ),
    ),
  );
}
