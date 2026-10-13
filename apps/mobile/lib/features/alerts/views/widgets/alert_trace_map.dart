import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/map_attribution.dart';
import '../../../../core/widgets/app_tile_layer.dart';
import '../../../../core/theme/speed_palette.dart';
import '../../models/alert_model.dart';
import '../../providers/alert_track_provider.dart';
import '../../../vehicles/models/vehicle_model.dart';
import '../../../vehicles/utils/speed_gradient.dart';

/// Seuil d'excès (doit refléter SPEED_LIMIT_KMH côté backend).
const double kSpeedLimitKmh = 120;

/// Carte traçant le segment GPS autour d'une alerte (fenêtre ±5 min), coloré
/// par vitesse — le rouge matérialise l'excès. Repli sur un simple marqueur si
/// l'alerte n'a pas de trace (autre type) ou si l'historique est vide.
class AlertTraceMap extends ConsumerStatefulWidget {
  final AlertModel alert;
  final Color color;
  final IconData icon;
  final bool interactive;

  const AlertTraceMap({
    super.key,
    required this.alert,
    required this.color,
    required this.icon,
    this.interactive = true,
  });

  @override
  ConsumerState<AlertTraceMap> createState() => _AlertTraceMapState();
}

class _AlertTraceMapState extends ConsumerState<AlertTraceMap> {
  final _map = MapController();
  static const _window = Duration(minutes: 5);

  // Évite de refit la caméra à chaque rebuild (un fit par jeu de données).
  int _fittedFor = -1;

  AlertTrackKey? get _trackKey {
    final a = widget.alert;
    if (a.type != 'speed_limit') return null; // trace réservée aux excès
    final from = a.createdAt.subtract(_window).millisecondsSinceEpoch;
    final to = a.createdAt.add(_window).millisecondsSinceEpoch;
    return (a.deviceId, from, to);
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = _trackKey;
    final focal = widget.alert.hasLocation
        ? LatLng(widget.alert.lat!, widget.alert.lon!)
        : null;

    if (key == null) {
      return _buildMap(const [], focal);
    }
    final trackAsync = ref.watch(alertTrackProvider(key));
    return trackAsync.when(
      data: (positions) => _buildMap(positions, focal),
      loading: () => const ColoredBox(
        color: Color(0xFFEDEEF0),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
        ),
      ),
      error: (_, __) => _buildMap(const [], focal),
    );
  }

  Widget _buildMap(List<VehiclePosition> positions, LatLng? focal) {
    final pts = positions.map((p) => LatLng(p.lat, p.lon)).toList();
    final speeding = [
      for (final p in positions)
        if (p.speedKmh > kSpeedLimitKmh) LatLng(p.lat, p.lon),
    ];

    // Cible de cadrage : priorité au segment en excès, sinon toute la trace,
    // sinon le point focal.
    final List<LatLng> fitTarget = speeding.length >= 2
        ? speeding
        : (pts.length >= 2 ? pts : [if (focal != null) focal]);

    if (fitTarget.isNotEmpty) {
      final sig =
          Object.hash(fitTarget.length, fitTarget.first, fitTarget.last);
      if (sig != _fittedFor) {
        _fittedFor = sig;
        WidgetsBinding.instance.addPostFrameCallback((_) => _fit(fitTarget));
      }
    }

    final center = focal ?? (pts.isNotEmpty ? pts.first : _fallbackCenter);

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 15,
        interactionOptions: InteractionOptions(
          flags:
              widget.interactive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
      ),
      children: [
        AppTileLayer(urlTemplate: AppMapTiles.positron),
        const MapAttribution(alignment: Alignment.topRight),
        if (pts.length >= 2)
          PolylineLayer(
            polylines: [
              for (final segment in buildSpeedTraceSegments(positions))
                Polyline(
                  points:
                      segment.points.map((p) => LatLng(p.lat, p.lon)).toList(),
                  strokeWidth: 5,
                  color: segment.band.color,
                  borderStrokeWidth: 1,
                  borderColor: const Color(0x66333549),
                  strokeCap: StrokeCap.round,
                  strokeJoin: StrokeJoin.round,
                ),
            ],
          ),
        MarkerLayer(markers: _markers(pts, focal)),
      ],
    );
  }

  List<Marker> _markers(List<LatLng> pts, LatLng? focal) {
    final markers = <Marker>[];
    if (pts.length >= 2) {
      markers.add(_dot(pts.first, AppColors.primary)); // départ du segment
      markers.add(_dot(pts.last, const Color(0xFF6B7280))); // fin du segment
    }
    // Épingle de l'alerte (lieu où l'excès a été détecté).
    if (focal != null) {
      markers.add(
        Marker(
          point: focal,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Icon(widget.icon, color: Colors.white, size: 20),
          ),
        ),
      );
    }
    return markers;
  }

  Marker _dot(LatLng point, Color color) {
    return Marker(
      point: point,
      width: 16,
      height: 16,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
      ),
    );
  }

  void _fit(List<LatLng> points) {
    if (!mounted || points.isEmpty) return;
    if (points.length == 1) {
      _map.move(points.first, 16);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  static const _fallbackCenter = LatLng(-18.9137, 47.5361);
}

/// Légende compacte de la palette de vitesse (pour le plein écran). Bloc qui
/// s'adapte en hauteur (Wrap) pour ne pas déborder dans le coin haut-droit.
class SpeedTraceLegend extends StatelessWidget {
  const SpeedTraceLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 172),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 5,
        children: [
          for (final b in kSpeedBands)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 5,
                  decoration: BoxDecoration(
                    color: b.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  b.range,
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.textHint),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
