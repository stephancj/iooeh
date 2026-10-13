import 'dart:math' show cos, pow;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/map_attribution.dart';
import '../../../core/widgets/app_tile_layer.dart';
import '../../history/views/history_view.dart';
import '../../../core/navigation/app_shell.dart';
import '../../../core/navigation/trackeo_route.dart';
import '../../vehicles/models/vehicle_model.dart';
import '../../vehicles/views/vehicle_details_view.dart';
import '../../vehicles/views/widgets/status_badge.dart';
import '../../vehicles/providers/vehicles_provider.dart';
import '../../../core/providers/geocoding_provider.dart';

class MapView extends ConsumerStatefulWidget {
  const MapView({super.key});

  @override
  ConsumerState<MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<MapView>
    with TickerProviderStateMixin {
  final _mapController = MapController();

  // Centre par défaut : Antananarivo
  static const _defaultCenter = LatLng(-18.9137, 47.5361);

  // Approximate logical-pixel height of the bottom vehicle card.
  // Used to offset the camera so the marker appears in the visible centre
  // above the card rather than behind it.
  static const _cardHeight = 290.0;

  // ── Fix gesture conflict ───────────────────────────────────────────────
  bool _markerJustTapped = false;

  // ── Smooth animation state ────────────────────────────────────────────
  // One AnimationController per vehicle — interpolates from last animated
  // position to the new GPS position over the polling interval (10 s).
  final Map<int, AnimationController> _animControllers = {};
  final Map<int, LatLng> _animatedPositions = {};
  final Map<int, double> _animatedCourses = {};

  // ── Tracking mode ("always-center" on selected vehicle) ───────────────
  bool _trackingMode = false;

  // Voyager → Satellite → Plan clair.
  int _tileStyleIndex = 0;

  // One-shot : recadre une seule fois sur l'unique véhicule au 1er chargement.
  bool _didInitialFit = false;

  // ── Beacon "live" — un seul controller partagé, anime le halo du véhicule
  // sélectionné (motif signature de la landing). Coupé si motion réduit.
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: AppMotion.pulse,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduce(context)) {
      _pulseController.stop();
      _pulseController.value = 0;
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    for (final ctrl in _animControllers.values) {
      ctrl.dispose();
    }
    _mapController.dispose();
    super.dispose();
  }

  // ── Angle interpolation (shortest path) ──────────────────────────────
  // ── Camera helpers ────────────────────────────────────────────────────

  /// Moves the camera to [target] at [zoom].
  ///
  /// When [cardShowing] is true the camera is shifted south by half the
  /// vehicle-card height so the marker appears centred in the visible area
  /// above the card rather than at the mathematical centre of the full screen.
  ///
  /// Uses Mercator math: degreesLatPerPixel = 360·cos(φ) / (256·2^zoom)
  void _moveToTarget(LatLng target, double zoom, {bool cardShowing = false}) {
    if (!cardShowing) {
      _mapController.move(target, zoom);
      return;
    }
    final latRad = target.latitude * pi / 180;
    final degreesPerPixel = 360.0 * cos(latRad) / (256.0 * pow(2.0, zoom));
    // Shift south (smaller lat) so target rises into the visible centre.
    final adjustedLat = target.latitude - (_cardHeight / 2.0) * degreesPerPixel;
    _mapController.move(LatLng(adjustedLat, target.longitude), zoom);
  }

  double _lerpAngle(double from, double to, double t) {
    double diff = (to - from) % 360;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return from + diff * t;
  }

  // ── Called on every poll result ───────────────────────────────────────
  void _onVehiclesUpdated(List<Vehicle> vehicles) {
    for (final v in vehicles) {
      if (v.position == null) continue;
      final newPos = LatLng(v.position!.lat, v.position!.lon);
      final newCourse = v.position!.course.toDouble();

      final oldPos = _animatedPositions[v.id];
      final selectedId = ref.read(selectedVehicleIdProvider);
      if (oldPos != null && selectedId != v.id) {
        _animControllers.remove(v.id)?.dispose();
        _animatedPositions[v.id] = newPos;
        _animatedCourses[v.id] = newCourse;
        continue;
      }
      if (oldPos == null) {
        // First position — place directly with no animation.
        _animatedPositions[v.id] = newPos;
        _animatedCourses[v.id] = newCourse;
        continue;
      }

      // Skip if position hasn't meaningfully changed (~1 cm threshold).
      final dlat = (newPos.latitude - oldPos.latitude).abs();
      final dlon = (newPos.longitude - oldPos.longitude).abs();
      if (dlat < 1e-7 && dlon < 1e-7) continue;

      // Cancel any in-progress animation and start a fresh one
      // from the CURRENT animated position → new GPS position.
      _animControllers[v.id]?.stop();
      _animControllers[v.id]?.dispose();

      final fromPos = oldPos;
      final fromCourse = _animatedCourses[v.id] ?? newCourse;

      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 10),
      );
      _animControllers[v.id] = ctrl;

      ctrl.addListener(() {
        final t = Curves.easeInOut.transform(ctrl.value);
        final animPos = LatLng(
          fromPos.latitude + (newPos.latitude - fromPos.latitude) * t,
          fromPos.longitude + (newPos.longitude - fromPos.longitude) * t,
        );
        final animCourse = _lerpAngle(fromCourse, newCourse, t);

        setState(() {
          _animatedPositions[v.id] = animPos;
          _animatedCourses[v.id] = animCourse;
        });

        // Follow selected vehicle if tracking mode is on.
        // Use cardShowing:true because the vehicle card is always visible
        // when a vehicle is being tracked.
        final selectedId = ref.read(selectedVehicleIdProvider);
        if (_trackingMode && selectedId == v.id) {
          _moveToTarget(
            animPos,
            _mapController.camera.zoom,
            cardShowing: true,
          );
        }
      });

      ctrl.forward();
    }

    // Clean up state for vehicles no longer present in the list.
    final currentIds = vehicles.map((v) => v.id).toSet();
    final removed =
        _animControllers.keys.where((id) => !currentIds.contains(id)).toList();
    for (final id in removed) {
      _animControllers[id]?.dispose();
      _animControllers.remove(id);
      _animatedPositions.remove(id);
      _animatedCourses.remove(id);
    }

    // Expérience mono-véhicule : recadrage initial sur l'unique véhicule.
    if (!_didInitialFit) {
      final withPos = vehicles.where((v) => v.position != null).toList();
      if (withPos.length == 1) {
        _didInitialFit = true;
        final v = withPos.first;
        final p = _animatedPositions[v.id] ??
            LatLng(v.position!.lat, v.position!.lon);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            _moveToTarget(p, 14);
          } catch (_) {
            // Carte pas encore prête : l'utilisateur peut recadrer manuellement.
          }
        });
      }
    }
  }

  String get _tileUrl => switch (_tileStyleIndex) {
        1 => AppMapTiles.satellite,
        2 => AppMapTiles.positron,
        _ => AppMapTiles.voyager,
      };

  String get _tileStyleLabel => switch (_tileStyleIndex) {
        1 => 'Satellite',
        2 => 'Plan clair',
        _ => 'Plan standard',
      };

  void _cycleTiles() {
    setState(() => _tileStyleIndex =
        (_tileStyleIndex + 1) % (AppMapTiles.hasCartoApiKey ? 3 : 2));
  }

  /// Sélectionne et recadre l'unique véhicule (tap sur la pastille du haut).
  void _focusSingleVehicle(Vehicle v) {
    if (v.position == null) return;
    final p =
        _animatedPositions[v.id] ?? LatLng(v.position!.lat, v.position!.lon);
    ref.read(selectedVehicleIdProvider.notifier).state = v.id;
    setState(() => _trackingMode = true);
    _moveToTarget(p, 15, cardShowing: true);
  }

  @override
  Widget build(BuildContext context) {
    // H4 — Écoute les données ET les erreurs (erreurs gérées dans VehiclesNotifier).
    ref.listen(vehiclesProvider, (_, next) {
      next.when(
        data: _onVehiclesUpdated,
        error: (_, __) {
          // VehiclesNotifier conserve les données précédentes en cas d'erreur réseau.
          // Aucune action supplémentaire requise.
        },
        loading: () {},
      );
    });

    final vehiclesAsync = ref.watch(vehiclesProvider);
    final mapFilter = ref.watch(mapFilterProvider);
    final mapSearch = ref.watch(mapSearchProvider).trim().toLowerCase();
    final allVehicles = vehiclesAsync.valueOrNull ?? [];
    final isSingle = allVehicles.length == 1;
    final statusFiltered = switch (mapFilter) {
      VehicleFilter.moving =>
        allVehicles.where((v) => v.status == VehicleStatus.online).toList(),
      VehicleFilter.idle =>
        allVehicles.where((v) => v.status == VehicleStatus.idle).toList(),
      VehicleFilter.offline =>
        allVehicles.where((v) => v.status == VehicleStatus.offline).toList(),
      VehicleFilter.all => allVehicles,
    };
    final vehicles = mapSearch.isEmpty
        ? statusFiltered
        : statusFiltered
            .where(
              (vehicle) =>
                  vehicle.name.toLowerCase().contains(mapSearch) ||
                  (vehicle.plate?.toLowerCase().contains(mapSearch) ?? false) ||
                  vehicle.serialNumber.toLowerCase().contains(mapSearch),
            )
            .toList();
    final selected = ref.watch(selectedVehicleProvider);
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          // ── Carte ──────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 12,
              onTap: (tapPos, latLng) {
                if (_markerJustTapped) {
                  _markerJustTapped = false;
                  return;
                }
                ref.read(selectedVehicleIdProvider.notifier).state = null;
                if (_trackingMode) setState(() => _trackingMode = false);
              },
              // Disable tracking when the user manually pans / zooms the map.
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _trackingMode) {
                  setState(() => _trackingMode = false);
                }
              },
            ),
            children: [
              AppTileLayer(urlTemplate: _tileUrl),
              MarkerLayer(
                markers: (isSingle ? allVehicles : vehicles)
                    .where((v) => v.position != null)
                    .map((v) => _buildMarker(v, selected))
                    .toList(),
              ),
              MapAttribution(
                satellite: _tileStyleIndex == 1,
                alignment: Alignment.bottomLeft,
                padding: EdgeInsets.only(
                  left: 6,
                  bottom: selected != null ? _cardHeight + 8 : 6,
                ),
              ),
            ],
          ),

          // ── Gradient de lisibilité — sombre en haut, fondu vers transparent ─
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPad + 180,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.72),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Indicateur de chargement ───────────────────────────────────
          if (vehiclesAsync.isLoading)
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

          // ── Header : signature iooeh + cloche ──────────────────────────
          Positioned(
            top: topPad + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Logo
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text(
                      'i',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Ouvrir les alertes',
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      tooltip: 'Alertes',
                      onPressed: () =>
                          ref.read(activeTabProvider.notifier).state = 2,
                      icon: const Icon(
                        Icons.notifications_outlined,
                        color: AppColors.primaryDark,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Barre de recherche / pastille véhicule unique ──────────────
          Positioned(
            top: topPad + 62,
            left: 16,
            right: 16,
            child: isSingle
                ? _MapSingleVehicleBar(
                    vehicle: allVehicles.first,
                    onTap: () => _focusSingleVehicle(allVehicles.first),
                  )
                : _MapSearchBar(),
          ),

          // ── Chips de filtre (masqués si un seul véhicule) ──────────────
          if (!isSingle)
            Positioned(
              top: topPad + 122,
              left: 16,
              right: 16,
              child: vehiclesAsync.when(
                data: (v) =>
                    _MapFilterRow(vehicles: v, allVehicles: allVehicles),
                loading: () => const SizedBox.shrink(),
                error: (e, st) => const SizedBox.shrink(),
              ),
            ),

          // ── Boutons droite : Layers + Recenter ─────────────────────────
          Positioned(
            bottom: selected != null ? 295 : 90,
            right: 16,
            child: Column(
              children: [
                Semantics(
                  button: true,
                  label: 'Changer le fond de carte, $_tileStyleLabel',
                  child: Tooltip(
                    message: 'Fond : $_tileStyleLabel',
                    child: GestureDetector(
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
                        child: Icon(
                          _tileStyleIndex == 1
                              ? Icons.satellite_alt_outlined
                              : Icons.layers,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Recenter — glows primary when tracking is active
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _trackingMode && selected != null
                        ? AppColors.primary
                        : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    tooltip: selected != null
                        ? 'Suivre ${selected.name}'
                        : 'Centrer la flotte',
                    onPressed: () => _recenter(selected),
                    icon: Icon(
                      Icons.gps_fixed,
                      color: _trackingMode && selected != null
                          ? Colors.white
                          : AppColors.primary,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Card véhicule sélectionné ──────────────────────────────────
          if (selected != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _VehicleCard(
                vehicle: selected,
                onClose: () {
                  ref.read(selectedVehicleIdProvider.notifier).state = null;
                  setState(() => _trackingMode = false);
                },
                onHistoryTap: () => Navigator.push(
                  context,
                  TrackeoRoute(
                    builder: (_) => HistoryView(
                      vehicleId: selected.id,
                      vehicleName: selected.name,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _recenter(Vehicle? selected) {
    if (selected != null) {
      // Use the current animated position if available.
      final pos = _animatedPositions[selected.id] ??
          (selected.position != null
              ? LatLng(selected.position!.lat, selected.position!.lon)
              : null);
      if (pos != null) {
        // Card is open → offset camera so the marker sits in visible centre.
        _moveToTarget(pos, 15, cardShowing: true);
        setState(() => _trackingMode = true);
        return;
      }
    }
    // No selection — center on the whole fleet (full-screen, no card).
    setState(() => _trackingMode = false);
    final vehiclesAsync = ref.read(vehiclesProvider);
    vehiclesAsync.whenData((vehicles) {
      final withPos = vehicles.where((v) => v.position != null).toList();
      if (withPos.isEmpty) return;
      if (withPos.length == 1) {
        final p = _animatedPositions[withPos.first.id] ??
            LatLng(withPos.first.position!.lat, withPos.first.position!.lon);
        _mapController.move(p, 14);
      } else {
        final avgLat =
            withPos.map((v) => v.position!.lat).reduce((a, b) => a + b) /
                withPos.length;
        final avgLon =
            withPos.map((v) => v.position!.lon).reduce((a, b) => a + b) /
                withPos.length;
        _mapController.move(LatLng(avgLat, avgLon), 12);
      }
    });
  }

  Marker _buildMarker(Vehicle vehicle, Vehicle? selected) {
    final pos = vehicle.position!;
    // Use the smoothly animated position; fall back to raw GPS on first render.
    final markerPos =
        _animatedPositions[vehicle.id] ?? LatLng(pos.lat, pos.lon);
    final course = _animatedCourses[vehicle.id] ?? pos.course.toDouble();
    final isSelected = selected?.id == vehicle.id;
    // Boîte élargie quand sélectionné pour contenir le halo "live".
    final boxSize = isSelected ? 88.0 : 42.0;
    final statusColor = switch (vehicle.status) {
      VehicleStatus.online => AppColors.primary,
      VehicleStatus.idle => AppColors.statusIdle,
      VehicleStatus.offline => AppColors.statusOffline,
    };

    // Le pin tourne selon le cap ; le halo, lui, ne tourne pas.
    final pin = Transform.rotate(
      angle: course * (pi / 180),
      child: Container(
        decoration: BoxDecoration(
          color: statusColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: isSelected ? 3 : 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.navigation,
          color: Colors.white,
          size: isSelected ? 28 : 22,
        ),
      ),
    );

    return Marker(
      point: markerPos,
      width: boxSize,
      height: boxSize,
      child: GestureDetector(
        onTap: () {
          _markerJustTapped = true;
          ref.read(selectedVehicleIdProvider.notifier).state = vehicle.id;
          // Auto-enable tracking; card will appear → apply south offset.
          setState(() => _trackingMode = true);
          _moveToTarget(markerPos, 14, cardShowing: true);
        },
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Beacon "live" : seulement le véhicule suivi, pour garder la carte calme.
            if (isSelected)
              _MarkerBeacon(controller: _pulseController, color: statusColor),
            pin,
          ],
        ),
      ),
    );
  }
}

/// Halo pulsé derrière le pin du véhicule sélectionné — disque qui s'étend
/// et se fond (motif "pulse-ring" repris de la landing). Drivé par le
/// controller partagé du MapView ; statique si le motion est réduit.
class _MarkerBeacon extends StatelessWidget {
  final Animation<double> controller; // 0..1, en boucle
  final Color color;

  const _MarkerBeacon({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        final scale = 1.0 + t * 1.1; // 1.0 → 2.1
        final opacity = (1.0 - t) * 0.42; // 0.42 → 0
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: opacity),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

// ── Widgets internes ─────────────────────────────────────────────────────────

/// Barre de recherche des véhicules affichés sur la carte.
class _MapSearchBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Icon(Icons.search, color: AppColors.textHint, size: 20),
          ),
          Expanded(
            child: TextField(
              onChanged: (v) => ref.read(mapSearchProvider.notifier).state = v,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: 'Rechercher un véhicule...',
                hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

/// Pastille véhicule unique — remplace la barre de recherche quand il n'y a
/// qu'un seul véhicule : identité + statut live, tap pour recadrer.
class _MapSingleVehicleBar extends StatelessWidget {
  final Vehicle vehicle;
  final VoidCallback onTap;

  const _MapSingleVehicleBar({required this.vehicle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppColors.pastelGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.directions_car,
                  color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                vehicle.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            StatusBadge(status: vehicle.status),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// Chips de filtre : All Vehicles / Moving / Idle (filtre local carte uniquement)
class _MapFilterRow extends ConsumerWidget {
  final List<Vehicle> vehicles;
  final List<Vehicle> allVehicles;
  const _MapFilterRow({required this.vehicles, required this.allVehicles});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(mapFilterProvider);
    final moving =
        allVehicles.where((v) => v.status == VehicleStatus.online).length;
    final idle =
        allVehicles.where((v) => v.status == VehicleStatus.idle).length;
    final offline =
        allVehicles.where((v) => v.status == VehicleStatus.offline).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(
            label: 'Tous',
            selected: filter == VehicleFilter.all,
            onTap: () =>
                ref.read(mapFilterProvider.notifier).state = VehicleFilter.all,
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'En route ($moving)',
            selected: filter == VehicleFilter.moving,
            onTap: () => ref.read(mapFilterProvider.notifier).state =
                VehicleFilter.moving,
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Arrêté ($idle)',
            selected: filter == VehicleFilter.idle,
            onTap: () =>
                ref.read(mapFilterProvider.notifier).state = VehicleFilter.idle,
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Hors ligne ($offline)',
            selected: filter == VehicleFilter.offline,
            onTap: () => ref.read(mapFilterProvider.notifier).state =
                VehicleFilter.offline,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Vehicle Card ─────────────────────────────────────────────────────────────

/// Card bottom sheet quand un véhicule est sélectionné — design Figma exact avec mode replié / étendu.
class _VehicleCard extends ConsumerStatefulWidget {
  final Vehicle vehicle;
  final VoidCallback onClose;
  final VoidCallback onHistoryTap;

  const _VehicleCard({
    required this.vehicle,
    required this.onClose,
    required this.onHistoryTap,
  });

  @override
  ConsumerState<_VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends ConsumerState<_VehicleCard> {
  bool _isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final pos = vehicle.position;
    final updatedAgo = pos != null ? _timeAgo(pos.deviceTime) : null;

    AsyncValue<String?>? addressAsync;
    if (pos != null) {
      addressAsync = ref.watch(
        reverseGeocodeProvider(LatLng(pos.lat, pos.lon)),
      );
    }

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! > 150) {
            // Glissé vers le bas -> réduire
            setState(() => _isCollapsed = true);
          } else if (details.primaryVelocity! < -150) {
            // Glissé vers le haut -> agrandir
            setState(() => _isCollapsed = false);
          }
        }
      },
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, _isCollapsed ? 16 : 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle (cliquable pour basculer réduit / étendu) ────
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _isCollapsed = !_isCollapsed),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 10),
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),

              if (_isCollapsed) ...[
                // ── Vue réduite (Collapsed) ──────────────────────────────────
                InkWell(
                  onTap: () => setState(() => _isCollapsed = false),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        // Icône voiture avec pastille de statut
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.directions_car_outlined,
                                color: AppColors.textSecondary,
                                size: 22,
                              ),
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _statusColor(vehicle.status),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        // Nom + Vitesse / Batterie
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vehicle.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: AppColors.primaryDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    '${pos?.speedKmh.toInt() ?? 0} km/h',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                  if (pos?.battery != null) ...[
                                    const Text(' · ',
                                        style: TextStyle(
                                            color: AppColors.textHint)),
                                    Icon(
                                      Icons.battery_charging_full_rounded,
                                      color: _batteryColor(pos!.battery!),
                                      size: 13,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${pos.battery}%',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                        color: _batteryColor(pos.battery!),
                                      ),
                                    ),
                                  ],
                                  if (updatedAgo != null) ...[
                                    const Text(' · ',
                                        style: TextStyle(
                                            color: AppColors.textHint)),
                                    Text(
                                      updatedAgo,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Bouton agrandir (chevron up)
                        IconButton(
                          icon: const Icon(
                            Icons.keyboard_arrow_up_rounded,
                            size: 24,
                            color: AppColors.primary,
                          ),
                          tooltip: 'Agrandir',
                          onPressed: () => setState(() => _isCollapsed = false),
                        ),
                        // Bouton fermer
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 20,
                            color: AppColors.textHint,
                          ),
                          tooltip: 'Fermer',
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // ── Vue étendue (Expanded) ───────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icône voiture
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.directions_car_outlined,
                        color: AppColors.textSecondary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Nom + adresse
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            vehicle.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: AppColors.primaryDark,
                            ),
                          ),
                          if (pos != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 13,
                                  color: AppColors.textHint,
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: addressAsync != null
                                      ? addressAsync.when(
                                          data: (address) => Text(
                                            address ??
                                                pos.address ??
                                                'Position inconnue',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          loading: () => const Text(
                                            'Localisation...',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                          error: (err, _) => const Text(
                                            'Position inconnue',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        )
                                      : const Text(
                                          'Position inconnue',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // LIVE badge + Chevron down pour réduire + Close
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Bouton Réduire
                            IconButton(
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 24,
                                color: AppColors.textSecondary,
                              ),
                              tooltip: 'Réduire',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () =>
                                  setState(() => _isCollapsed = true),
                            ),
                            const SizedBox(width: 8),
                            // Bouton Fermer
                            GestureDetector(
                              onTap: widget.onClose,
                              child: const Icon(
                                Icons.close,
                                size: 20,
                                color: AppColors.textHint,
                              ),
                            ),
                          ],
                        ),
                        if (updatedAgo != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Mis à jour $updatedAgo',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.divider),
                const SizedBox(height: 16),

                // ── Stats ────────────────────────────────────────────────────
                IntrinsicHeight(
                  child: Row(
                    children: [
                      // Speed
                      _StatBox(
                        label: 'Vitesse',
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '${pos?.speedKmh.toInt() ?? 0}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 24,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              const TextSpan(
                                text: ' km/h',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(width: 1, color: AppColors.divider),
                      // Battery
                      _StatBox(
                        label: 'Batterie',
                        child: pos?.battery != null
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.battery_charging_full_rounded,
                                    color: _batteryColor(pos!.battery!),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${pos.battery}%',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 20,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                '--',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                  color: AppColors.textHint,
                                ),
                              ),
                      ),
                      Container(width: 1, color: AppColors.divider),
                      // Status
                      _StatBox(
                        label: 'Statut',
                        child: Text(
                          vehicle.status.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: _statusColor(vehicle.status),
                          ),
                        ),
                      ),
                      Container(width: 1, color: AppColors.divider),
                      // Ignition
                      _StatBox(
                        label: 'Allumage',
                        child: Icon(
                          pos?.ignition == true
                              ? Icons.key_rounded
                              : Icons.key_off_rounded,
                          size: 22,
                          color: pos?.ignition == true
                              ? AppColors.statusOnline
                              : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Boutons ─────────────────────────────────────────────────
                Row(
                  children: [
                    // Détails — vert rempli
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          TrackeoRoute(
                            builder: (_) => VehicleDetailsView(vehicle: vehicle),
                          ),
                        ),
                        icon: const Icon(Icons.info_outline_rounded, size: 17),
                        label: const Text(
                          'Détails',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.primaryDark,
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // History — contour gris
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onHistoryTap,
                        icon: const Icon(Icons.history_rounded, size: 17),
                        label: const Text(
                          'Historique',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(
                            color: AppColors.divider,
                            width: 1.5,
                          ),
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(VehicleStatus status) => switch (status) {
        VehicleStatus.online => AppColors.statusOnline,
        VehicleStatus.idle => AppColors.statusIdle,
        VehicleStatus.offline => AppColors.statusOffline,
      };

  Color _batteryColor(int battery) {
    if (battery > 50) return AppColors.batteryGood;
    if (battery > 20) return AppColors.batteryMedium;
    return AppColors.batteryLow;
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'il y a ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours}h';
    return 'il y a ${diff.inDays}j';
  }
}

/// Colonne stat individuelle (Speed / Battery / Status)
class _StatBox extends StatelessWidget {
  final String label;
  final Widget child;

  const _StatBox({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textHint,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
