import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/map_tiles_provider.dart';
import '../theme/app_theme.dart';

/// Crédit visible du fournisseur, placé hors des panneaux de la carte.
class MapAttribution extends ConsumerWidget {
  final bool satellite;
  final Alignment alignment;
  final EdgeInsets padding;

  const MapAttribution({
    super.key,
    this.satellite = false,
    this.alignment = Alignment.bottomRight,
    this.padding = const EdgeInsets.all(4),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = ref.watch(cartoFallbackProvider);
    return Align(
      alignment: alignment,
      child: Padding(
        padding: padding,
        child: Material(
          color: const Color(0xEEFFFFFF),
          child: InkWell(
            onTap: () => launchUrl(Uri.parse(satellite
                ? 'https://www.esri.com/en-us/legal/terms/data-attributions'
                : 'https://www.openstreetmap.org/copyright')),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                satellite
                    ? AppMapTiles.satelliteAttribution
                    : fallback
                        ? '© OpenStreetMap contributors'
                        : AppMapTiles.attribution,
                style: const TextStyle(fontSize: 10, color: Colors.black87),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
