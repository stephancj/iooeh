import 'package:flutter/material.dart';

/// Palette de couleurs iooeh — extraite du logo officiel.
class AppColors {
  AppColors._();

  // ── Brand ──────────────────────────────────────────────────────────────────
  /// Vert menthe officiel du logo iooeh.
  static const Color primary = Color(0xFF4ECB8D);
  static const Color brandMint = Color(0xFF4ECB8D);

  /// Charcoal du logo. Utilisé sur le vert pour un contraste WCAG AA.
  static const Color primaryDark = Color(0xFF333549);

  // ── Layout ────────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF4F5F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE5E7EB);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF596273);
  static const Color textHint = Color(0xFF656D7A);

  // ── Statuts véhicules ─────────────────────────────────────────────────────
  static const Color statusOnline = Color(0xFF4ECB8D); // En mouvement → vert
  static const Color statusIdle = Color(0xFF5B8DEF); // Arrêté connecté → bleu
  static const Color statusOffline = Color(0xFF9CA3AF); // Hors ligne → gris
  static const Color statusAlert = Color(0xFFEF4444); // Alerte → rouge

  // ── Batterie ──────────────────────────────────────────────────────────────
  static const Color batteryGood = Color(0xFF4ECB8D); // > 50 %
  static const Color batteryMedium = Color(0xFFF59E0B); // 20–50 %
  static const Color batteryLow = Color(0xFFEF4444); // < 20 %

  // ── Pastels (fonds d'icônes) ──────────────────────────────────────────────
  static const Color pastelGreen = Color(0xFFE8F8F2); // primary à 12 %
  static const Color pastelBlue = Color(0xFFEBF2FD); // statusIdle à 15 %
  static const Color pastelPurple = Color(0xFFF3EEFF); // #8B5CF6 à 12 %
  static const Color pastelRed = Color(0xFFFEECEC); // statusAlert à 10 %
  static const Color pastelOrange = Color(0xFFFFF3E8); // #F97316 à 12 %
}

/// Échelle typographique — utiliser ces styles plutôt que des TextStyle inline.
class AppTextStyles {
  AppTextStyles._();

  // Titres de pages
  static const TextStyle pageTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppColors.primaryDark,
  );
  static const TextStyle pageTitleLarge = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.primaryDark,
  );

  // Titres de sections / cards
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    color: AppColors.primaryDark,
  );
  static const TextStyle cardTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  // Corps de texte
  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.textPrimary,
  );
  static const TextStyle bodySecondary = TextStyle(
    fontSize: 13,
    color: AppColors.textSecondary,
  );

  // Labels / métadonnées
  static const TextStyle label = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );
  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    color: AppColors.textHint,
  );

  // Caps (section labels)
  static const TextStyle caps = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: AppColors.textHint,
    letterSpacing: 1.1,
  );
}

/// Constantes d'espacement — utiliser ces valeurs plutôt que des literaux inline.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0; // padding standard
  static const double xl = 24.0;
  static const double xxl = 32.0;
}

/// Constantes de border radius.
class AppRadius {
  AppRadius._();

  static const double sm = 8.0;
  static const double md = 12.0; // cards standard
  static const double lg = 16.0; // sections, modals
  static const double pill = 24.0; // chips, pills
}

/// Tokens de mouvement — une seule signature de courbe pour toute l'app,
/// alignée sur la landing web (`--ease: cubic-bezier(0.22, 1, 0.36, 1)`).
/// Objectif : une voix de motion cohérente, premium, jamais "rebond élastique".
class AppMotion {
  AppMotion._();

  // ── Courbes ────────────────────────────────────────────────────────────────
  /// Décélération douce — la courbe signature (ease-out-quint). Défaut partout.
  static const Cubic quint = Cubic(0.22, 1, 0.36, 1);

  /// Décélération franche — déplacements amples (ease-out-expo).
  static const Cubic expo = Cubic(0.16, 1, 0.3, 1);

  // ── Durées ─────────────────────────────────────────────────────────────────
  static const Duration instant =
      Duration(milliseconds: 120); // feedback tactile
  static const Duration fast = Duration(milliseconds: 180); // hover, chips
  static const Duration base =
      Duration(milliseconds: 240); // changements d'état
  static const Duration enter =
      Duration(milliseconds: 420); // entrées de contenu
  static const Duration pulse = Duration(milliseconds: 2200); // beacon "live"

  /// Respecte la préférence système « réduire les animations » (WCAG / PRODUCT.md).
  /// Les boucles décoratives doivent se désactiver quand ceci renvoie `true`.
  static bool reduce(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

/// Fonds de carte : OpenStreetMap par défaut, CARTO si une clé est configurée.
class AppMapTiles {
  AppMapTiles._();

  /// Configurer avec --dart-define=CARTO_BASEMAP_API_KEY=... au build Flutter.
  static const String cartoApiKey =
      String.fromEnvironment('CARTO_BASEMAP_API_KEY');
  static const bool hasCartoApiKey = cartoApiKey != '';

  static const String openStreetMap =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static const String darkMatter = hasCartoApiKey
      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png?key=$cartoApiKey'
      : openStreetMap;

  static const String voyager = hasCartoApiKey
      ? 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png?key=$cartoApiKey'
      : openStreetMap;

  static const String positron = hasCartoApiKey
      ? 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png?key=$cartoApiKey'
      : openStreetMap;

  /// Esri World Imagery — ordre des tuiles {z}/{y}/{x}, sans retina.
  static const String satellite =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  static const List<String> subdomains =
      hasCartoApiKey ? ['a', 'b', 'c', 'd'] : [];

  static bool isCarto(String url) => url.contains('basemaps.cartocdn.com/');

  static const String attribution = hasCartoApiKey
      ? '© OpenStreetMap contributors, © CARTO'
      : '© OpenStreetMap contributors';
  static const String satelliteAttribution =
      '© Esri, Maxar, Earthstar Geographics';
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: AppColors.primaryDark,
          secondary: AppColors.primaryDark,
          onSecondary: Colors.white,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          error: AppColors.statusAlert,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 1,
          titleTextStyle: TextStyle(
            color: AppColors.primaryDark,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: IconThemeData(color: AppColors.primaryDark),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.divider),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.primaryDark,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
            minimumSize: const Size(double.infinity, 52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md)),
            textStyle: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textHint,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          selectedLabelStyle:
              TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 10),
        ),
      );
}
