import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Une erreur CARTO bascule toutes les cartes vers OSM pour cette session.
/// Un nouveau lancement de l'application permettra de réessayer CARTO.
final cartoFallbackProvider = StateProvider<bool>((ref) => false);
