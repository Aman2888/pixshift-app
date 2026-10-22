import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Same palette as the website (app/globals.css): pith, pine, zest, pulp.
class C {
  static const pith = Color(0xFFF5F7EC);
  static const pine = Color(0xFF0D2B24);
  static const zest = Color(0xFFC8F23A);
  static const pulp = Color(0xFFFF6A8B);
  static const brand50 = Color(0xFFF1F9D8);
  static const brand100 = Color(0xFFE3F4AE);
  static const brand500 = Color(0xFF3F7D5C);
  static const brand600 = Color(0xFF1F5A46);
  static const checker = Color(0xFFDFE5CF);
  static const line = Color(0xFFCBD5E1);
  static const lineSoft = Color(0xFFE2E8F0);
  static const muted = Color(0xFF64748B);
  static const ink2 = Color(0xFF334155);
  static const err = Color(0xFFBE123C);
  static const errBg = Color(0xFFFFF1F2);
}

TextStyle display(double size, {Color color = C.pine, FontWeight w = FontWeight.w800}) =>
    GoogleFonts.anybody(fontSize: size, fontWeight: w, color: color, letterSpacing: -0.2, height: 1.08);

TextStyle body(double size, {Color color = C.pine, FontWeight w = FontWeight.w500, double? h}) =>
    GoogleFonts.schibstedGrotesk(fontSize: size, fontWeight: w, color: color, height: h);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.brand600,
      primary: C.pine,
      onPrimary: Colors.white,
      secondary: C.zest,
      onSecondary: C.pine,
      surface: C.pith,
      onSurface: C.pine,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: C.pith,
  );
  return base.copyWith(
    textTheme: GoogleFonts.schibstedGroteskTextTheme(base.textTheme).apply(bodyColor: C.pine, displayColor: C.pine),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white.withValues(alpha: 0.92),
      foregroundColor: C.pine,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: display(20),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: C.brand600,
      inactiveTrackColor: C.lineSoft,
      thumbColor: C.brand600,
      overlayColor: Color(0x331F5A46),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.brand500, width: 2)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: C.zest,
      labelTextStyle: WidgetStatePropertyAll(body(12, w: FontWeight.w700)),
      iconTheme: const WidgetStatePropertyAll(IconThemeData(color: C.pine)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.pine,
      contentTextStyle: body(14, color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
