import 'package:flutter/material.dart';

class AuthenticatedDashboardTheme {
  const AuthenticatedDashboardTheme._();

  static const background = Colors.white;
  static const card = Colors.white;
  static const accent = Color(0xFF2F5D50);
  static const text = Color(0xFF101828);
  static const muted = Color(0xFF4A5565);
  static const line = Color(0xFFE5E7EB);
  static const soft = Color(0xFFF3F4F6);
  static const warningBg = Color(0xFFFFF4D8);
  static const warning = Color(0xFF9A6700);

  static const appointmentImage =
      'assets/user_dashboard/appointment_anna.png';
  static const mariaImage = 'assets/user_dashboard/master_maria.png';
  static const dmitryImage = 'assets/user_dashboard/master_dmitry.png';
  static const victoriaImage = 'assets/user_dashboard/master_victoria.png';

  static List<BoxShadow> cardShadow() {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.08),
        blurRadius: 12,
        offset: const Offset(0, 3),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 2,
        offset: const Offset(0, 1),
      ),
    ];
  }
}
