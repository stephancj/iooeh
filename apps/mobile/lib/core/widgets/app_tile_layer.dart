import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/map_tiles_provider.dart';
import '../theme/app_theme.dart';

/// Couche commune : au premier échec CARTO, recharge le fond complet en OSM.
class AppTileLayer extends ConsumerStatefulWidget {
  final String urlTemplate;

  @visibleForTesting
  final TileProvider Function()? tileProviderFactory;

  const AppTileLayer({
    super.key,
    required this.urlTemplate,
    this.tileProviderFactory,
  });

  @override
  ConsumerState<AppTileLayer> createState() => _AppTileLayerState();
}

class _AppTileLayerState extends ConsumerState<AppTileLayer> {
  bool _fallbackScheduled = false;
  String? _providerUrl;
  TileProvider? _tileProvider;

  void _useFallback() {
    if (_fallbackScheduled) return;
    _fallbackScheduled = true;
    // Les erreurs peuvent arriver pendant le chargement d'une couche.
    scheduleMicrotask(() {
      if (mounted) ref.read(cartoFallbackProvider.notifier).state = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fallback = ref.watch(cartoFallbackProvider);
    final requestedCarto = AppMapTiles.isCarto(widget.urlTemplate);
    final url = requestedCarto && fallback
        ? AppMapTiles.openStreetMap
        : widget.urlTemplate;
    final usesCarto = AppMapTiles.isCarto(url);

    if (_providerUrl != url) {
      _providerUrl = url;
      // Chaque couche possède son client, fermé par TileLayer à sa destruction.
      _tileProvider =
          widget.tileProviderFactory?.call() ?? NetworkTileProvider();
    }

    return TileLayer(
      // Recréer la couche supprime les anciennes tuiles et réinitialise retina.
      key: ValueKey(url),
      urlTemplate: url,
      subdomains: usesCarto ? const ['a', 'b', 'c', 'd'] : const [],
      retinaMode: usesCarto,
      tileProvider: _tileProvider,
      userAgentPackageName: 'mg.trackeo.app',
      errorTileCallback: usesCarto ? (_, __, ___) => _useFallback() : null,
    );
  }
}
