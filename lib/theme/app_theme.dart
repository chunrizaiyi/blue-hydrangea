import 'package:flutter/material.dart';

abstract final class AppColors {
  static const mistBlue = Color(0xFFEAF1FF);
  static const softBlue = Color(0xFFB8CAF0);
  static const hydrangea = Color(0xFF708DC7);
  static const deepBlue = Color(0xFF4E689D);
  static const lavender = Color(0xFFDCD9F3);
  static const cream = Color(0xFFFCFAF6);
  static const ink = Color(0xFF3F4A60);
  static const muted = Color(0xFF7D8799);
  static const leaf = Color(0xFF9BB6A7);
  static const blush = Color(0xFFF0DDE3);
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.hydrangea,
      brightness: Brightness.light,
      surface: AppColors.cream,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: AppColors.deepBlue,
        secondary: AppColors.lavender,
        surface: AppColors.cream,
      ),
      scaffoldBackgroundColor: AppColors.cream,
      fontFamilyFallback: const [
        'PingFang SC',
        'Microsoft YaHei',
        'sans-serif',
      ],
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: AppColors.ink,
          fontSize: 29,
          height: 1.35,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
        headlineSmall: TextStyle(
          color: AppColors.ink,
          fontSize: 22,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: AppColors.ink,
          fontSize: 17,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: AppColors.ink, fontSize: 16, height: 1.75),
        bodyMedium: TextStyle(color: AppColors.ink, fontSize: 14, height: 1.65),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 21,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: .82),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .78),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: AppColors.softBlue.withValues(alpha: .25),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: AppColors.hydrangea, width: 1.3),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 15,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.deepBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: GardenPageTransitionsBuilder()},
      ),
    );
  }
}

class GardenPageTransitionsBuilder extends PageTransitionsBuilder {
  const GardenPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final entrance = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInCubic,
    );
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeInOutCubic,
    );

    return AnimatedBuilder(
      animation: exit,
      child: FadeTransition(
        opacity: entrance,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(.045, .012),
            end: Offset.zero,
          ).animate(entrance),
          child: ScaleTransition(
            scale: Tween(begin: .985, end: 1.0).animate(entrance),
            child: child,
          ),
        ),
      ),
      builder: (context, child) => Transform.translate(
        offset: Offset(-12 * exit.value, 0),
        child: Transform.scale(scale: 1 - .01 * exit.value, child: child),
      ),
    );
  }
}
