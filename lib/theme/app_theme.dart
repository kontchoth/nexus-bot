import 'package:flutter/material.dart';
import 'package:nexusbot/theme/google_fonts_stub.dart';

class AppTheme {
  // Colors
  static const bg = Color(0xFF050A0F);
  static const bg2 = Color(0xFF080F17);
  static const bg3 = Color(0xFF0D1825);
  static const bg4 = Color(0xFF111F2E);
  static const border = Color(0xFF1A2E42);
  static const border2 = Color(0xFF1E3A52);

  static const textPrimary = Color(0xFFC8DDF0);
  static const textMuted = Color(0xFF4A6A85);
  static const textDim = Color(0xFF2A4A65);

  static const green = Color(0xFF00FF87);
  static const red = Color(0xFFFF3366);
  static const blue = Color(0xFF4499FF);
  static const gold = Color(0xFFFFD700);

  static const greenBg = Color(0xFF001F10);
  static const redBg = Color(0xFF1A000A);

  // Text styles
  static TextStyle get mono => GoogleFonts.spaceGrotesk(
        color: textPrimary,
        fontSize: 12,
      );

  static TextStyle get display => GoogleFonts.syne(
        color: textPrimary,
        fontWeight: FontWeight.w800,
      );

  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: blue,
          secondary: green,
          surface: bg2,
          error: red,
        ),
        textTheme: GoogleFonts.spaceGroteskTextTheme(
          const TextTheme(
            bodyLarge: TextStyle(color: textPrimary),
            bodyMedium: TextStyle(color: textMuted),
          ),
        ),
        dividerColor: border,
        cardColor: bg2,
        appBarTheme: AppBarTheme(
          backgroundColor: bg2,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.syne(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: bg2,
          selectedItemColor: blue,
          unselectedItemColor: textMuted,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: textMuted,
          indicatorColor: blue,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bg3,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: border2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: blue),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: bg3,
            foregroundColor: textPrimary,
            side: const BorderSide(color: border2),
            textStyle: GoogleFonts.spaceGrotesk(fontSize: 11),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
      );
}

// Reusable style helpers
class NexusText {
  static TextStyle label({Color? color}) => GoogleFonts.spaceGrotesk(
        fontSize: 9,
        color: color ?? AppTheme.textMuted,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w600,
      );

  static TextStyle value({Color? color, double size = 15}) => GoogleFonts.syne(
        fontSize: size,
        color: color ?? AppTheme.textPrimary,
        fontWeight: FontWeight.w700,
      );

  static TextStyle mono({Color? color, double size = 11}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        color: color ?? AppTheme.textPrimary,
      );
}
