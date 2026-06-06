import 'package:flutter/material.dart';

const Color authBackground = Color(0xFFF7F5F2);
const Color authSurface = Color(0xFFFFFFFF);
const Color authOutline = Color(0xFFDDD7D1);
const Color authText = Color(0xFF181818);
const Color authHint = Color(0xFF6E6A66);
const Color authAccent = Color(0xFF2F6B5F);
const Color authAccentHover = Color(0xFF25564C);
const Color authError = Color(0xFFC84B4B);
const Color authSuccess = Color(0xFF2F6B5F);
const Color authButtonDisabled = Color(0x52306B5F);
const Color authButtonDisabledText = Color(0xFFF8FCFA);
const Color authFocusFill = Color(0xFFFDFCFB);
const Color authSoftPanel = Color(0xFFF3F0EB);
const Color authSoftAccent = Color(0xFFE8F0ED);

const double authCardRadius = 20;
const double authControlRadius = 14;
const double authControlHeight = 52;
const double authCompactBreakpoint = 760;
const double authPageCompactPadding = 16;
const double authPagePadding = 24;
const double authPageDesktopMinHeight = 700;
const double authHeaderGap = 8;
const double authFieldNoteGap = 8;
const double authFieldNoteMinHeight = 36;
const double authSectionContentGap = 16;
const double authBrandIconSize = 30;
const double authBrandGap = 10;
const double authHeroBrandGap = 52;
const double authHeroTitleWidth = 320;
const double authHeroSubtitleWidth = 360;
const double authHeroTextGap = 14;
const double authHeroItemsGap = 38;
const double authHeroItemGap = 18;
const double authHeroItemIconWrap = 36;
const double authHeroItemIconSize = 19;
const double authHeroItemRowGap = 14;
const double authStepperHeaderGap = 26;
const double authStepperItemsGap = 22;
const double authStepperItemGap = 12;
const double authStepperIndicatorColumnWidth = 34;
const double authStepperBadgeSize = 32;
const double authStepperConnectorWidth = 2;
const double authStepperConnectorHeight = 24;
const double authStepperTextGap = 12;
const double authStepperTextTopPadding = 5;
const double authTabletStepDotSize = 26;
const EdgeInsets authDefaultFormCardPadding = EdgeInsets.symmetric(
  horizontal: 28,
  vertical: 30,
);
const EdgeInsets authHeroPadding = EdgeInsets.fromLTRB(42, 34, 38, 38);
const EdgeInsets authStepperSidebarPadding = EdgeInsets.fromLTRB(22, 24, 22, 24);
const EdgeInsets authStepperItemPadding = EdgeInsets.fromLTRB(10, 8, 10, 8);
const EdgeInsets authTabletStepPadding = EdgeInsets.fromLTRB(18, 14, 18, 12);
const EdgeInsets authMobileProgressPadding = EdgeInsets.fromLTRB(16, 14, 16, 14);
const EdgeInsets authSectionCardPadding = EdgeInsets.fromLTRB(18, 18, 18, 16);

ThemeData buildInkConnectTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: authAccent,
    brightness: Brightness.light,
    primary: authAccent,
    error: authError,
    surface: authSurface,
  );

  OutlineInputBorder border(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(authControlRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: authBackground,
    fontFamily: 'Segoe UI',
    splashColor: authAccent.withValues(alpha: 0.08),
    highlightColor: authAccent.withValues(alpha: 0.06),
    hoverColor: authAccent.withValues(alpha: 0.05),
    focusColor: authAccent.withValues(alpha: 0.08),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 44,
        height: 1.08,
        fontWeight: FontWeight.w700,
        color: authText,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: authText,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: authText,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        height: 1.45,
        color: authText,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        color: authHint,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: authSurface,
      labelStyle: const TextStyle(color: authHint, fontSize: 14),
      hintStyle: const TextStyle(color: Color(0xFFA19A93), fontSize: 14),
      errorStyle: const TextStyle(fontSize: 0, height: 0),
      constraints: const BoxConstraints(
        minHeight: authControlHeight,
        maxHeight: authControlHeight,
      ),
      prefixIconColor: authHint,
      suffixIconColor: authHint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(authOutline),
      enabledBorder: border(authOutline),
      focusedBorder: border(authAccent, width: 1.4),
      errorBorder: border(authError, width: 1.2),
      focusedErrorBorder: border(authError, width: 1.4),
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: authOutline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
  );
}

const BoxDecoration authBackgroundDecoration = BoxDecoration(
  color: authBackground,
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF7F5F2), Color(0xFFF2EFEA)],
  ),
);

ButtonStyle authPrimaryButtonStyle() {
  return FilledButton.styleFrom(
    minimumSize: const Size.fromHeight(authControlHeight),
    backgroundColor: authAccent,
    foregroundColor: Colors.white,
    disabledBackgroundColor: authButtonDisabled,
    disabledForegroundColor: authButtonDisabledText,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(authControlRadius),
    ),
    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    elevation: 0,
  ).copyWith(
    shadowColor: const WidgetStatePropertyAll(Color(0x26000000)),
    elevation: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return 0;
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed)) {
        return 2;
      }
      return 1;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed)) {
        return authAccentHover.withValues(alpha: 0.1);
      }
      return null;
    }),
  );
}
