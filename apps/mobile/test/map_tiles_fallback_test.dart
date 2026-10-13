import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile/core/providers/map_tiles_provider.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/core/widgets/app_tile_layer.dart';
import 'package:mobile/core/widgets/map_attribution.dart';

const _carto =
    'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png?key=test';
const _point = LatLng(-18.8792, 47.5079);
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=');

class _RejectedImage extends ImageProvider<_RejectedImage> {
  final int status;
  _RejectedImage(this.status);

  @override
  Future<_RejectedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _RejectedImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: Future<ui.Codec>.error(NetworkImageLoadException(
          statusCode: status,
          uri: Uri.parse('https://basemaps.cartocdn.com/test.png'),
        )),
        scale: 1,
      );
}

class _TestTiles extends TileProvider {
  final List<String> requests;
  final int? status;
  final bool rejectSatellite;

  _TestTiles(this.requests, {this.status, this.rejectSatellite = false});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    requests.add(url);
    if (status != null && (AppMapTiles.isCarto(url) || rejectSatellite)) {
      return _RejectedImage(status!);
    }
    return MemoryImage(_png);
  }
}

Widget _map(String url, TileProvider Function() factory) => SizedBox(
      height: 180,
      child: FlutterMap(
        options: const MapOptions(initialCenter: _point, initialZoom: 12),
        children: [
          AppTileLayer(urlTemplate: url, tileProviderFactory: factory),
          MarkerLayer(markers: [
            Marker(point: _point, child: const Text('Véhicule')),
          ]),
          MapAttribution(satellite: url == AppMapTiles.satellite),
        ],
      ),
    );

Widget _app(ProviderContainer container, List<Widget> maps) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: Column(children: maps))),
    );

void main() {
  for (final status in [401, 403, 429, 503]) {
    testWidgets(
        'un refus CARTO $status bascule toutes les cartes de la session',
        (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final requests = <String>[];

      await tester.pumpWidget(_app(container, [
        _map(_carto, () => _TestTiles(requests, status: status)),
        _map(_carto, () => _TestTiles(requests)),
      ]));
      await tester.pumpAndSettle();

      expect(container.read(cartoFallbackProvider), isTrue);
      expect(requests.any(AppMapTiles.isCarto), isTrue);
      expect(
          requests
              .any((url) => url.startsWith('https://tile.openstreetmap.org/')),
          isTrue);
      for (final layer
          in tester.widgetList<TileLayer>(find.byType(TileLayer))) {
        expect(layer.urlTemplate, AppMapTiles.openStreetMap);
        expect(layer.resolvedRetinaMode, RetinaMode.disabled);
        expect(layer.errorTileCallback, isNull);
      }
      expect(find.text('Véhicule'), findsNWidgets(2));
      expect(find.text('© OpenStreetMap contributors'), findsNWidgets(2));

      // Ouvrir une autre carte ne doit pas réessayer une clé déjà refusée.
      requests.clear();
      await tester.pumpWidget(_app(container, [
        _map(_carto.replaceFirst('light_all', 'dark_all'),
            () => _TestTiles(requests, status: status)),
        _map(AppMapTiles.satellite, () => _TestTiles(requests)),
      ]));
      await tester.pumpAndSettle();
      expect(requests.any(AppMapTiles.isCarto), isFalse);
      expect(
          tester.widgetList<TileLayer>(find.byType(TileLayer)).last.urlTemplate,
          AppMapTiles.satellite);
      expect(find.text(AppMapTiles.satelliteAttribution), findsOneWidget);
    });
  }

  testWidgets('une erreur satellite ne désactive pas CARTO', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container, [
      _map(AppMapTiles.satellite,
          () => _TestTiles([], status: 503, rejectSatellite: true)),
    ]));
    await tester.pumpAndSettle();
    expect(container.read(cartoFallbackProvider), isFalse);
  });

  testWidgets('sans erreur CARTO reste actif', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_app(container, [
      _map(_carto, () => _TestTiles([])),
    ]));
    await tester.pumpAndSettle();
    expect(container.read(cartoFallbackProvider), isFalse);
    expect(
        tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate, _carto);
  });
}
