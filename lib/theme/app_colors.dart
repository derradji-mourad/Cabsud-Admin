import 'package:flutter/material.dart';

/// Premium Deep Sapphire & Gold color palette for Cabsud Admin Dashboard
class AppColors {
  AppColors._();

  // === PRIMARY COLORS ===
  /// Deep Sapphire - Main background color
  static const Color primary = Color(0xFF0A1628);

  /// Rich Navy - Cards and panels
  static const Color secondary = Color(0xFF1A2B4A);

  /// Slate Blue - Elevated surfaces
  static const Color surface = Color(0xFF243B55);

  /// Darker surface for contrast
  static const Color surfaceDark = Color(0xFF0D1B2A);

  // === ACCENT COLORS ===
  /// Luxury Gold - Primary accent color
  static const Color gold = Color(0xFFD4AF37);

  /// Light Gold - Hover states and highlights
  static const Color goldLight = Color(0xFFF4E5B2);

  /// Dark Gold - Pressed states
  static const Color goldDark = Color(0xFFB8960C);

  // === STATUS COLORS ===
  /// Success Green
  static const Color success = Color(0xFF22C55E);

  /// Warning Amber
  static const Color warning = Color(0xFFF59E0B);

  /// Error Red
  static const Color error = Color(0xFFEF4444);

  /// Info Blue
  static const Color info = Color(0xFF3B82F6);

  // === TEXT COLORS ===
  /// Primary text - White
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Secondary text - Light grey
  static const Color textSecondary = Color(0xFF94A3B8);

  /// Muted text - Darker grey
  static const Color textMuted = Color(0xFF64748B);

  // === BORDER COLORS ===
  /// Subtle border
  static const Color border = Color(0xFF334155);

  /// Gold border for focus states
  static const Color borderFocus = gold;

  // === GRADIENTS ===
  /// Primary gradient for backgrounds
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  /// Gold gradient for buttons
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gold, goldDark],
  );

  /// Sidebar gradient
  static const LinearGradient sidebarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0D1B2A), Color(0xFF1A2B4A)],
  );

  // === GLASSMORPHISM ===
  /// Glass background color
  static Color glassBackground = Colors.white.withValues(alpha: 0.08);

  /// Glass border color
  static Color glassBorder = Colors.white.withValues(alpha: 0.15);
}
