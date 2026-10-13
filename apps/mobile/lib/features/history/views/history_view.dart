import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/map_attribution.dart';
import '../../../core/widgets/app_tile_layer.dart';
import '../../../core/theme/speed_palette.dart';
import '../../../core/providers/geocoding_provider.dart';
import '../../../core/utils/app_time.dart';
import '../../vehicles/models/vehicle_model.dart';
import '../../vehicles/utils/speed_gradient.dart';
import '../models/trip_model.dart';
import '../models/day_activity_model.dart';
import '../../entitlements/views/feature_gate.dart';
import '../providers/history_provider.dart';
import 'widgets/activity_calendar_sheet.dart';

class HistoryView extends ConsumerStatefulWidget {
  final int vehicleId;
  final String vehicleName;

  const HistoryView({
    super.key,
    required this.vehicleId,
    required this.vehicleName,
  });

  @override
  ConsumerState<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends ConsumerState<HistoryView> {
  final _mapController = MapController();
  static const _defaultCenter = LatLng(-18.9137, 47.5361);

  // Hauteur du panneau inférieur (~52 % de l'écran)
  static const double _panelRatio = 0.52;

  // Styles de carte cyclés par le bouton calques.
  static const _tiles = AppMapTiles.hasCartoApiKey
      ? [AppMapTiles.positron, AppMapTiles.voyager, AppMapTiles.darkMatter]
      : [AppMapTiles.openStreetMap, AppMapTiles.satellite];
  static const _tileNames = AppMapTiles.hasCartoApiKey
      ? ['Clair', 'Voyager', 'Sombre']
      : ['Plan', 'Satellite'];
  int _tileIndex = 0;

  // Trajet sélectionné (1-based) — met en évidence sa polyligne et zoome dessus.
  int? _selectedTrip;

  // Dernières données calculées, accessibles aux handlers (tap trajet, recentrer).
  DayTrips _day = DayTrips.fromPositions(const []);
  List<LatLng> _allPoints = const [];

  // ── Playback State ──────────────────────────────────────────────────
  bool _isPlaying = false;
  bool _playbackActive = false;
  double _playbackIndex = 0;
  double _playbackSpeed = 1.0;
  Timer? _playbackTimer;

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final positionsAsync = ref.watch(
      historyPositionsProvider(widget.vehicleId),
    );
    final date = ref.watch(historyDateProvider);
    final screenH = MediaQuery.of(context).size.height;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final effectivePanelH = _playbackActive ? 0.0 : (screenH * _panelRatio);

    final positions = positionsAsync.valueOrNull ?? [];
    _day = DayTrips.fromPositions(positions);
    _allPoints = positions.map((p) => LatLng(p.lat, p.lon)).toList();
    final polylines = _buildTripPolylines(_day, _selectedTrip);

    // Ajuster la carte + réinitialiser la sélection quand de nouvelles données arrivent.
    ref.listen(historyPositionsProvider(widget.vehicleId), (_, next) {
      next.whenData((pts) {
        if (mounted && _selectedTrip != null) {
          setState(() => _selectedTrip = null);
        }
        if (pts.length > 1) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _fitRoute(pts.map((p) => LatLng(p.lat, p.lon)).toList()),
          );
        }
      });
    });

    return FeatureGate(
        anyOf: const ['history'],
        title: 'Historique des Trajets',
        description:
            'L\'historique complet de vos déplacements est disponible avec un plan Basic ou Premium.',
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              // ── Carte plein écran ─────────────────────────────────────────
              FlutterMap(
                mapController: _mapController,
                options: const MapOptions(
                  initialCenter: _defaultCenter,
                  initialZoom: 12,
                ),
                children: [
                  AppTileLayer(urlTemplate: _tiles[_tileIndex]),
                  // Une polyligne (dégradé de vitesse) par trajet — pas de ligne
                  // factice à travers les arrêts.
                  if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
                  // Marqueurs départ / arrivée du jour + points d'arrêt + véhicule animé.
                  MarkerLayer(
                    markers: [
                      ..._dayMarkers(_day),
                      ..._playbackMarkers(positions),
                    ],
                  ),
                  MapAttribution(
                    satellite: _tiles[_tileIndex] == AppMapTiles.satellite,
                    alignment: Alignment.topRight,
                    padding: EdgeInsets.only(top: topPad + 62, right: 6),
                  ),
                ],
              ),

              // ── Indicateur de chargement (fin du top) ────────────────────
              if (positionsAsync.isLoading)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    color: AppColors.primary,
                    backgroundColor: Colors.transparent,
                    minHeight: 2,
                  ),
                ),

              // ── Header : retour + sélecteur de date ──────────────────────
              Positioned(
                top: topPad + 8,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    // Bouton retour
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          size: 16,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Sélecteur de date
                    Expanded(
                      child: _DateSelector(
                        date: date,
                        vehicleId: widget.vehicleId,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Boutons droite (calques + recenter) ──────────────────────
              Positioned(
                right: 16,
                bottom:
                    effectivePanelH + (_playbackActive ? 100 + bottomPad : 12),
                child: Column(
                  children: [
                    // Calques — cycle clair / voyager / sombre
                    GestureDetector(
                      onTap: _cycleTiles,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primaryDark,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.layers,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Recentrer
                    GestureDetector(
                      onTap: () {
                        final sel = _tripByIndex(_selectedTrip);
                        if (sel != null) {
                          _fitTrip(sel);
                        } else if (_allPoints.length > 1) {
                          _fitRoute(_allPoints);
                        } else if (_allPoints.isNotEmpty) {
                          _mapController.move(_allPoints.first, 14);
                        }
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.gps_fixed,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Bar de contrôle du Playback ──────────────────────────────
              _buildPlaybackBar(positions, bottomPad),

              // ── Panneau inférieur (résumé + trajets) ─────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.fastOutSlowIn,
                  height: effectivePanelH,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: positionsAsync.when(
                    loading: () => const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    ),
                    error: (e, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Impossible de charger le trajet.\n$e',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.statusAlert,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    data: (_) => positions.isEmpty
                        ? _EmptyState(
                            vehicleName: widget.vehicleName, date: date)
                        : _DayPanel(
                            day: _day,
                            selectedTrip: _selectedTrip,
                            onTripTap: _onTripTap,
                            onPlayPlayback: () =>
                                _startPlayback(positions: positions),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ));
  }

  // ── Playback Logic & Helpers ──────────────────────────────────────────

  void _startPlayback(
      {required List<VehiclePosition> positions, int? startIndex}) {
    if (positions.isEmpty) return;
    _playbackTimer?.cancel();
    final maxIdx = (positions.length - 1).toDouble();
    setState(() {
      _playbackActive = true;
      _isPlaying = true;
      _playbackIndex = (startIndex ?? 0).toDouble().clamp(0, maxIdx);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitRoute(_allPoints);
    });

    _playbackTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!_isPlaying || !mounted) return;
      setState(() {
        _playbackIndex += (0.15 * _playbackSpeed);
        if (_playbackIndex >= maxIdx) {
          _playbackIndex = maxIdx;
          _isPlaying = false;
          _playbackTimer?.cancel();
        }
      });
      final pos = _interpolatedPoint(positions, _playbackIndex);
      final currentZoom = math.max(_mapController.camera.zoom, 14.0);
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: [pos],
          padding: const EdgeInsets.only(bottom: 220),
          maxZoom: currentZoom,
        ),
      );
    });
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  void _changeSpeed() {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 2.0;
      } else if (_playbackSpeed == 2.0) {
        _playbackSpeed = 4.0;
      } else if (_playbackSpeed == 4.0) {
        _playbackSpeed = 8.0;
      } else {
        _playbackSpeed = 1.0;
      }
    });
  }

  void _seekPlayback(List<VehiclePosition> positions, double value) {
    if (positions.isEmpty) return;
    final maxIdx = (positions.length - 1).toDouble();
    setState(() {
      _playbackIndex = value.clamp(0, maxIdx);
    });
    final pos = _interpolatedPoint(positions, _playbackIndex);
    final currentZoom = _mapController.camera.zoom;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: [pos],
        padding: const EdgeInsets.only(bottom: 220),
        maxZoom: currentZoom,
      ),
    );
  }

  void _stopPlayback() {
    _playbackTimer?.cancel();
    setState(() {
      _playbackActive = false;
      _isPlaying = false;
      _playbackIndex = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitRoute(_allPoints);
    });
  }

  LatLng _interpolatedPoint(List<VehiclePosition> positions, double index) {
    if (positions.isEmpty) return _defaultCenter;
    final i1 = index.floor().clamp(0, positions.length - 1);
    final i2 = math.min(i1 + 1, positions.length - 1);
    if (i1 == i2) return LatLng(positions[i1].lat, positions[i1].lon);
    final t = index - i1;
    final p1 = positions[i1];
    final p2 = positions[i2];
    final lat = p1.lat + (p2.lat - p1.lat) * t;
    final lon = p1.lon + (p2.lon - p1.lon) * t;
    return LatLng(lat, lon);
  }

  double _interpolatedBearing(List<VehiclePosition> positions, double index) {
    if (positions.length < 2) return 0;
    final i1 = index.floor().clamp(0, positions.length - 1);
    final i2 = math.min(i1 + 1, positions.length - 1);
    if (i1 == i2) return 0;
    final p1 = LatLng(positions[i1].lat, positions[i1].lon);
    final p2 = LatLng(positions[i2].lat, positions[i2].lon);
    return _calculateBearing(p1, p2);
  }

  double _calculateBearing(LatLng start, LatLng end) {
    final startLat = start.latitude * math.pi / 180;
    final startLng = start.longitude * math.pi / 180;
    final endLat = end.latitude * math.pi / 180;
    final endLng = end.longitude * math.pi / 180;
    final dLng = endLng - startLng;

    final y = math.sin(dLng) * math.cos(endLat);
    final x = math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(dLng);

    final bearing = math.atan2(y, x);
    return (bearing * 180 / math.pi + 360) % 360;
  }

  List<Marker> _playbackMarkers(List<VehiclePosition> positions) {
    if (!_playbackActive || positions.isEmpty) return const [];
    final currentPos = _interpolatedPoint(positions, _playbackIndex);
    final bearing = _interpolatedBearing(positions, _playbackIndex);
    final idx = _playbackIndex.floor().clamp(0, positions.length - 1);
    final speed = smoothedSpeedKmh(positions, idx);

    return [
      Marker(
        point: currentPos,
        width: 70,
        height: 70,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                '${speed.round()} km/h',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Transform.rotate(
              angle: bearing * math.pi / 180,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.navigation_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildPlaybackBar(List<VehiclePosition> positions, double bottomPad) {
    if (!_playbackActive || positions.isEmpty) return const SizedBox.shrink();
    final maxIdx = (positions.length - 1).toDouble();
    final idx = _playbackIndex.floor().clamp(0, positions.length - 1);
    final currentPos = positions[idx];
    final date = currentPos.deviceTime.toLocal();
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16 + bottomPad,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primaryDark.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: _togglePlayPause,
              icon: Icon(
                _isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 34,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        timeStr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        '${currentPos.speedKmh.round()} km/h',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: const SliderThemeData(
                      trackHeight: 3,
                      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: _playbackIndex.clamp(0, maxIdx),
                      min: 0,
                      max: maxIdx > 0 ? maxIdx : 1,
                      onChanged: (val) => _seekPlayback(positions, val),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _changeSpeed,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: Colors.white12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                '${_playbackSpeed.toInt()}x',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: _stopPlayback,
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white70,
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Handlers ───────────────────────────────────────────────────────────

  void _cycleTiles() {
    setState(() => _tileIndex = (_tileIndex + 1) % _tiles.length);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Carte : ${_tileNames[_tileIndex]}'),
          duration: const Duration(milliseconds: 900),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primaryDark,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  void _onTripTap(int index) {
    final deselect = _selectedTrip == index;
    setState(() => _selectedTrip = deselect ? null : index);
    final target = _tripByIndex(deselect ? null : index);
    if (target != null) {
      _fitTrip(target);
    } else if (_allPoints.length > 1) {
      _fitRoute(_allPoints);
    }
  }

  Trip? _tripByIndex(int? index) {
    if (index == null) return null;
    for (final t in _day.trips) {
      if (t.index == index) return t;
    }
    return null;
  }

  // ── Map helpers ────────────────────────────────────────────────────────

  /// Une polyligne par trajet. Si un trajet est sélectionné, les autres sont
  /// estompés en gris translucide pour le mettre en avant.
  static List<Polyline> _buildTripPolylines(DayTrips day, int? selected) {
    final polys = <Polyline>[];
    for (final t in day.trips) {
      if (t.points.length < 2) continue;
      final dimmed = selected != null && selected != t.index;
      if (dimmed) {
        polys.add(
          Polyline(
            points: t.points.map((p) => LatLng(p.lat, p.lon)).toList(),
            strokeWidth: 5,
            color: const Color(0x5598A2B3),
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
        continue;
      }

      for (final segment in buildSpeedTraceSegments(t.points)) {
        polys.add(
          Polyline(
            points: segment.points.map((p) => LatLng(p.lat, p.lon)).toList(),
            strokeWidth: selected == t.index ? 6 : 5,
            color: segment.band.color,
            borderStrokeWidth: 1,
            borderColor: const Color(0x66333549),
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
      }
    }
    return polys;
  }

  List<Marker> _dayMarkers(DayTrips day) {
    final markers = <Marker>[];
    final start = day.dayStart;
    final end = day.dayEnd;
    if (start != null) {
      markers.add(_endpointMarker(LatLng(start.lat, start.lon), isStart: true));
    }
    if (end != null && day.trips.isNotEmpty) {
      markers.add(_endpointMarker(LatLng(end.lat, end.lon), isStart: false));
    }
    // Points d'arrêt entre trajets.
    for (final s in day.stops) {
      markers.add(
        Marker(
          point: LatLng(s.at.lat, s.at.lon),
          width: 14,
          height: 14,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.textSecondary, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return markers;
  }

  Marker _endpointMarker(LatLng point, {required bool isStart}) {
    return Marker(
      point: point,
      width: 22,
      height: 22,
      child: Container(
        decoration: BoxDecoration(
          color: isStart ? AppColors.primary : const Color(0xFFEF6C6C),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  void _fitRoute(List<LatLng> points) {
    if (points.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(points);
    final screenH = MediaQuery.of(context).size.height;
    final bottomPad = _playbackActive ? 100.0 : (screenH * _panelRatio + 30.0);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: EdgeInsets.fromLTRB(40, 100, 40, bottomPad),
      ),
    );
  }

  void _fitTrip(Trip trip) {
    _fitRoute(trip.points.map((p) => LatLng(p.lat, p.lon)).toList());
  }
}

// ── Date Selector ─────────────────────────────────────────────────────────────

class _DateSelector extends ConsumerWidget {
  final DateTime date;
  final int vehicleId;
  const _DateSelector({required this.date, required this.vehicleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isToday = _isToday(date);
    // Jours actifs du mois courant — alimente les flèches "jour actif suivant".
    final monthDays = ref
            .watch(activeDaysProvider((vehicleId, date.year, date.month)))
            .valueOrNull ??
        const <DayActivity>[];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Jour actif précédent
          GestureDetector(
            onTap: () => _stepToActive(ref, monthDays, -1),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_left,
                color: AppColors.textSecondary,
                size: 26,
              ),
            ),
          ),
          // Date centrale — tap pour ouvrir le calendrier d'activité
          Expanded(
            child: GestureDetector(
              onTap: () => _openCalendar(context, ref),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatDate(date),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isToday ? 'Aujourd\'hui' : _dayName(date),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Jour actif suivant (désactivé si aujourd'hui)
          GestureDetector(
            onTap: isToday ? null : () => _stepToActive(ref, monthDays, 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_right,
                color: isToday ? AppColors.textHint : AppColors.textSecondary,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCalendar(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ActivityCalendarSheet(
        vehicleId: vehicleId,
        selectedDate: date,
      ),
    );
    if (picked != null) {
      ref.read(historyDateProvider.notifier).state =
          DateTime(picked.year, picked.month, picked.day);
    }
  }

  /// Saute au jour actif le plus proche dans la direction [dir] (-1 / +1).
  /// Repli sur ±1 jour calendaire si aucun jour actif dans ce mois.
  void _stepToActive(WidgetRef ref, List<DayActivity> monthDays, int dir) {
    final cur = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    final todayD = DateTime(now.year, now.month, now.day);

    final active = monthDays
        .where((d) => d.hasMovement)
        .map((d) => DateTime(d.date.year, d.date.month, d.date.day))
        .toList()
      ..sort();

    DateTime? target;
    if (dir < 0) {
      for (final d in active.reversed) {
        if (d.isBefore(cur)) {
          target = d;
          break;
        }
      }
    } else {
      for (final d in active) {
        if (d.isAfter(cur)) {
          target = d;
          break;
        }
      }
    }

    target ??= cur.add(Duration(days: dir));
    if (target.isAfter(todayD)) return;
    ref.read(historyDateProvider.notifier).state = target;
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String _formatDate(DateTime d) {
    const m = [
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.',
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  String _dayName(DateTime d) {
    const w = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    return w[d.weekday - 1];
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String vehicleName;
  final DateTime date;
  const _EmptyState({required this.vehicleName, required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.route, size: 32, color: AppColors.textHint),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucun trajet enregistré',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Aucune donnée pour $vehicleName à cette date.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Day Summary Panel ─────────────────────────────────────────────────────────

class _DayPanel extends StatelessWidget {
  final DayTrips day;
  final int? selectedTrip;
  final void Function(int index) onTripTap;
  final VoidCallback onPlayPlayback;

  const _DayPanel({
    required this.day,
    required this.selectedTrip,
    required this.onTripTap,
    required this.onPlayPlayback,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Header ────────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Résumé de la journée',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              if (!day.isEmpty) ...[
                ElevatedButton.icon(
                  onPressed: onPlayPlayback,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Rejouer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.pastelGreen,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  day.tripCount == 0
                      ? 'AUCUN TRAJET'
                      : '${day.tripCount} TRAJET${day.tripCount > 1 ? 'S' : ''}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Stats hero (distance / conduite / vitesse max) ────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  _StatTile(
                    icon: Icons.directions_car_outlined,
                    iconColor: const Color(0xFF5B8DEF),
                    iconBg: const Color(0xFFEEF2FF),
                    label: 'DISTANCE',
                    value: day.formattedDistance,
                  ),
                  Container(width: 1, color: AppColors.divider),
                  _StatTile(
                    icon: Icons.timer_outlined,
                    iconColor: const Color(0xFFF97316),
                    iconBg: const Color(0xFFFFF3E8),
                    label: 'CONDUITE',
                    value: day.formattedDrivingTime,
                  ),
                  Container(width: 1, color: AppColors.divider),
                  _StatTile(
                    icon: Icons.speed_outlined,
                    iconColor: const Color(0xFF9333EA),
                    iconBg: const Color(0xFFF5EEFF),
                    label: 'VITESSE MAX',
                    value: day.formattedTopSpeed,
                  ),
                ],
              ),
            ),
          ),

          // ── Stats secondaires (moyenne / arrêts / stationné) ──────────
          if (!day.isEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    icon: Icons.trending_up_rounded,
                    label: 'Moyenne',
                    value: day.formattedAvgSpeed,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniStat(
                    icon: Icons.local_parking_rounded,
                    label: 'Arrêts',
                    value: '${day.stopCount}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniStat(
                    icon: Icons.pause_circle_outline_rounded,
                    label: 'Stationné',
                    value: day.formattedParkedTime,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // ── Légende vitesse ───────────────────────────────────────────
          const _SpeedLegend(),

          const SizedBox(height: 24),

          // ── Trajets ───────────────────────────────────────────────────
          if (day.isEmpty)
            _StationaryNote()
          else ...[
            const Text(
              'TRAJETS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textHint,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < day.trips.length; i++) ...[
              _TripCard(
                trip: day.trips[i],
                selected: selectedTrip == day.trips[i].index,
                onTap: () => onTripTap(day.trips[i].index),
              ),
              if (i < day.stops.length) _StopSeparator(stop: day.stops[i]),
            ],
          ],
        ],
      ),
    );
  }
}

// ── Stat Tile (hero) ──────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;

  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    // Sépare la valeur numérique de l'unité (ex: "12.4" + "km")
    final parts = value.split(' ');
    final numeric = parts.first;
    final unit = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textHint,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: numeric,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Mini Stat (secondaire) ────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stationary note (positions mais aucun trajet significatif) ────────────────

class _StationaryNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.local_parking_rounded,
              size: 22, color: AppColors.textSecondary),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Véhicule stationné — aucun déplacement significatif ce jour.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Trip Card ─────────────────────────────────────────────────────────────────

class _TripCard extends ConsumerWidget {
  final Trip trip;
  final bool selected;
  final VoidCallback onTap;

  const _TripCard({
    required this.trip,
    required this.selected,
    required this.onTap,
  });

  String _hhmm(DateTime t) => fmtMgHm(t);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startAddr = ref
        .watch(reverseGeocodeProvider(LatLng(trip.start.lat, trip.start.lon)));
    final endAddr =
        ref.watch(reverseGeocodeProvider(LatLng(trip.end.lat, trip.end.lon)));

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.quint,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.pastelGreen : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Numéro du trajet
            Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${trip.index}',
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Heures + chevron
                  Row(
                    children: [
                      Text(
                        '${_hhmm(trip.start.deviceTime)} – ${_hhmm(trip.end.deviceTime)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        selected
                            ? Icons.my_location_rounded
                            : Icons.chevron_right_rounded,
                        size: 18,
                        color:
                            selected ? AppColors.primary : AppColors.textHint,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Adresse départ
                  _AddrLine(
                    dotColor: AppColors.primary,
                    filled: true,
                    text: _addrText(startAddr, 'Départ'),
                  ),
                  const SizedBox(height: 2),
                  // Adresse arrivée
                  _AddrLine(
                    dotColor: const Color(0xFFEF6C6C),
                    filled: false,
                    text: _addrText(endAddr, 'Arrivée'),
                  ),
                  const SizedBox(height: 8),
                  // Stats du trajet
                  Row(
                    children: [
                      _chip(Icons.straighten_rounded, trip.formattedDistance),
                      const SizedBox(width: 8),
                      _chip(Icons.schedule_rounded, trip.formattedDuration),
                      const SizedBox(width: 8),
                      _chip(Icons.speed_rounded, trip.formattedTopSpeed),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _addrText(AsyncValue<String?> addr, String fallback) {
    return addr.maybeWhen(
      data: (a) => a ?? fallback,
      orElse: () => 'Localisation…',
    );
  }

  Widget _chip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _AddrLine extends StatelessWidget {
  final Color dotColor;
  final bool filled;
  final String text;

  const _AddrLine({
    required this.dotColor,
    required this.filled,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? dotColor : Colors.transparent,
            border: Border.all(color: dotColor, width: 2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Stop separator (entre deux trajets) ───────────────────────────────────────

class _StopSeparator extends StatelessWidget {
  final TripStop stop;
  const _StopSeparator({required this.stop});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Aligné sous le cercle numéro (26px) → trait vertical pointillé.
          const SizedBox(
            width: 26,
            child: Center(
              child: _DottedLine(),
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.local_parking_rounded,
              size: 14, color: AppColors.textHint),
          const SizedBox(width: 6),
          Text(
            'Arrêt · ${stop.formattedDuration}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

class _DottedLine extends StatelessWidget {
  const _DottedLine();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (_) => Container(
          width: 2,
          height: 3,
          margin: const EdgeInsets.symmetric(vertical: 1.5),
          color: AppColors.divider,
        ),
      ),
    );
  }
}

// ── Speed Legend ──────────────────────────────────────────────────────────────

class _SpeedLegend extends StatelessWidget {
  const _SpeedLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 6,
        runSpacing: 10,
        children: kSpeedBands
            .map((b) => _LegendItem(b.color, b.label, b.range))
            .toList(),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String sub;
  const _LegendItem(this.color, this.label, this.sub);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 5,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          sub.contains('km/h') ? sub : '$sub km/h',
          style: const TextStyle(
            fontSize: 9,
            color: AppColors.textHint,
          ),
        ),
      ],
    );
  }
}
