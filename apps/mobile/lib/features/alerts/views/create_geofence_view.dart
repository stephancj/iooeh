import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/map_attribution.dart';
import '../../../core/widgets/app_tile_layer.dart';
import '../../../core/providers/geocoding_provider.dart';
import '../providers/geofences_provider.dart';
import '../models/geofence_model.dart';
import '../models/geofence_type.dart';
import '../../vehicles/providers/vehicles_provider.dart';
import '../../entitlements/providers/entitlements_provider.dart';

class CreateGeofenceView extends ConsumerStatefulWidget {
  /// Pass a [geofence] to open in edit mode, null to create a new one.
  final Geofence? geofence;

  const CreateGeofenceView({super.key, this.geofence});

  @override
  ConsumerState<CreateGeofenceView> createState() => _CreateGeofenceViewState();
}

class _CreateGeofenceViewState extends ConsumerState<CreateGeofenceView>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  double _radius = 500;
  bool _onEntry = true;
  bool _onExit = true;
  bool _alertViaWhatsapp = false;
  String _type = 'home';
  LatLng _center = const LatLng(-18.8792, 47.5079);
  bool _isSaving = false;
  bool _isDragging = false;
  int _formStep = 0;
  final Set<int> _selectedVehicleIds = {};
  late final TextEditingController _nameController;

  // Rayon : bornes fixes, indépendantes du zoom de la carte.
  static const double _minRadius = 100;
  static const double _maxRadius = 5000;

  // Fond de carte cyclé par le bouton calques (plan clair → satellite).
  static const List<String> _tiles = [
    AppMapTiles.positron,
    AppMapTiles.satellite,
  ];
  static const List<String> _tileNames = ['Plan', 'Satellite'];
  int _tileIndex = 0;

  // Recherche de lieu (geocoding avant)
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<PlaceResult> _searchResults = [];
  bool _searching = false;
  Timer? _searchDebounce;

  // Localisation utilisateur (GPS) + adresse de l'épingle (reverse geocoding)
  bool _locating = false;
  String? _centerAddress;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool get _isEditing => widget.geofence != null;

  @override
  void initState() {
    super.initState();
    // Pre-fill fields when editing
    final gf = widget.geofence;
    if (gf != null) {
      _nameController = TextEditingController(text: gf.name);
      _center = LatLng(gf.centerLat, gf.centerLon);
      _radius = gf.radiusM.clamp(_minRadius, _maxRadius);
      _onEntry = gf.alertOnEntry;
      _onExit = gf.alertOnExit;
      _alertViaWhatsapp = gf.alertViaWhatsapp;
      _type = gf.type;
      if (gf.deviceIds != null) _selectedVehicleIds.addAll(gf.deviceIds!);
      // Fit circle into view after the map widget is ready
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureCircleVisible(),
      );
    } else {
      _nameController = TextEditingController(text: 'Domicile');
    }
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _updateAddress(); // adresse initiale de l'épingle
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _searchDebounce?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Recherche de lieu (geocoding avant) ──────────────────────────────────
  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _runSearch(value),
    );
  }

  Future<void> _runSearch(String query) async {
    final results = await NominatimCache.searchPlaces(query);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  void _selectPlace(PlaceResult place) {
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() {
      _center = LatLng(place.lat, place.lon);
      _searchResults = [];
      _searchController.text = place.shortName;
      _centerAddress = place.shortName;
    });
    _mapController.move(_center, 15);
    _ensureCircleVisible();
    _updateAddress();
  }

  void _cycleTiles() {
    HapticFeedback.selectionClick();
    setState(() => _tileIndex = (_tileIndex + 1) % _tiles.length);
    _showSnack('Fond : ${_tileNames[_tileIndex]}', AppColors.primaryDark);
  }

  // ── Ma position (GPS navigateur / appareil) ──────────────────────────────
  Future<void> _goToMyLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _showSnack(
          'Autorisez la localisation pour utiliser cette fonction.',
          Colors.orange.shade700,
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _center = LatLng(pos.latitude, pos.longitude);
        _searchResults = [];
      });
      _mapController.move(_center, 16);
      _ensureCircleVisible();
      _updateAddress();
    } catch (_) {
      _showSnack('Position indisponible.', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── Adresse de l'épingle (reverse geocoding) ─────────────────────────────
  Future<void> _updateAddress() async {
    final target = _center;
    final addr = await NominatimCache.reverseGeocode(
      target.latitude,
      target.longitude,
    );
    if (!mounted) return;
    // N'écrase pas si l'épingle a bougé entre-temps.
    if (target == _center) setState(() => _centerAddress = addr);
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _centerOnMarker() {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPanelHeight = screenHeight * 0.46;
    final zoom = _mapController.camera.zoom;

    // Visible area center is (screenHeight - bottomPanelHeight) / 2 from top,
    // which is bottomPanelHeight / 2 pixels above the screen center.
    // To place the marker there, shift the camera center downward by that offset.
    final metersPerPixel = 156543.03392 *
        math.cos(_center.latitude * math.pi / 180) /
        math.pow(2, zoom);
    final latPerPixel = metersPerPixel / 111320;
    final latOffset = (bottomPanelHeight / 2) * latPerPixel;

    _mapController.move(
      LatLng(_center.latitude - latOffset, _center.longitude),
      zoom,
    );
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    setState(() {
      _center = point;
      _searchResults = [];
    });
    _ensureCircleVisible();
    _updateAddress();
  }

  void _ensureCircleVisible() {
    final bottomPanelHeight = MediaQuery.of(context).size.height * 0.46;
    final distance = const Distance();
    final north = distance.offset(_center, _radius, 0);
    final south = distance.offset(_center, _radius, 180);
    final east = distance.offset(_center, _radius, 90);
    final west = distance.offset(_center, _radius, 270);

    final bounds = LatLngBounds.fromPoints([north, south, east, west]);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        // Extra bottom padding pushes the fit into the visible area above the panel
        padding: EdgeInsets.fromLTRB(60, 80, 60, bottomPanelHeight + 60),
      ),
    );
  }

  Future<void> _deleteGeofence() async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (_) => AlertDialog.adaptive(
        title: const Text('Supprimer la zone ?'),
        content: Text(
          'Supprimer "${_nameController.text.trim()}" ?\nCette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await ref
        .read(geofencesProvider.notifier)
        .deleteGeofence(widget.geofence!.id);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Impossible de supprimer. Veuillez réessayer.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _continueToRules() {
    if (_nameController.text.trim().isEmpty) {
      _showSnack('Donnez un nom à cette zone.', Colors.orange.shade700);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _formStep = 1);
  }

  Future<void> _saveGeofence() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Veuillez saisir un nom de zone'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    if (!_isEditing) {
      final rights = await ref.read(entitlementsProvider.future);
      final zoneCount = ref.read(geofencesProvider).valueOrNull?.length ?? 0;
      final limit = rights.limit('max_geofences');
      if (zoneCount >= limit) {
        _showSnack(
          'Votre plan ${rights.planName} autorise $limit zone${limit > 1 ? 's' : ''}.',
          Colors.orange.shade700,
        );
        return;
      }
    }

    final rights = await ref.read(entitlementsProvider.future);
    if (_alertViaWhatsapp && !rights.has('whatsapp_notifications')) {
      _showSnack(
        'WhatsApp n’est pas inclus dans votre plan.',
        Colors.orange.shade700,
      );
      return;
    }

    setState(() => _isSaving = true);

    final payload = {
      'name': name,
      'centerLat': _center.latitude,
      'centerLon': _center.longitude,
      'radiusM': _radius.toInt(),
      'type': _type,
      'isActive': widget.geofence?.isActive ?? true,
      'deviceIds': _selectedVehicleIds.toList(),
      'alertOnEntry': _onEntry,
      'alertOnExit': _onExit,
      'alertViaWhatsapp': _alertViaWhatsapp,
    };

    final notifier = ref.read(geofencesProvider.notifier);
    final result = _isEditing
        ? await notifier.updateGeofence(widget.geofence!.id, payload)
        : await notifier.createGeofence(payload);

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result != null) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Impossible de mettre à jour. Veuillez réessayer.'
                : 'Impossible d\'enregistrer. Veuillez réessayer.',
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPanelHeight = MediaQuery.of(context).size.height * 0.46;

    return Scaffold(
      body: Stack(
        children: [
          // ── MAP ──────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13,
              onTap: _onMapTap,
            ),
            children: [
              AppTileLayer(urlTemplate: _tiles[_tileIndex]),
              MapAttribution(
                satellite: _tileIndex == 1,
                alignment: Alignment.bottomLeft,
                padding:
                    EdgeInsets.only(bottom: bottomPanelHeight + 4, left: 6),
              ),
              // Geofence circle
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _center,
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderColor: AppColors.primary,
                    borderStrokeWidth: 2.5,
                    radius: _radius,
                    useRadiusInMeter: true,
                  ),
                ],
              ),
              // Draggable center marker
              MarkerLayer(
                markers: [
                  Marker(
                    point: _center,
                    width: 56,
                    height: 56,
                    child: GestureDetector(
                      onPanStart: (_) {
                        HapticFeedback.selectionClick();
                        setState(() => _isDragging = true);
                      },
                      onPanUpdate: (details) {
                        // Convert drag delta (pixels) to lat/lng offset
                        final camera = _mapController.camera;
                        final zoom = camera.zoom;
                        // Meters per pixel at current zoom and latitude
                        final metersPerPixel = 156543.03392 *
                            math.cos(_center.latitude * math.pi / 180) /
                            math.pow(2, zoom);
                        final latPerPixel = metersPerPixel / 111320;
                        final lonPerPixel = metersPerPixel /
                            (111320 *
                                math.cos(_center.latitude * math.pi / 180));

                        setState(() {
                          _center = LatLng(
                            _center.latitude - details.delta.dy * latPerPixel,
                            _center.longitude + details.delta.dx * lonPerPixel,
                          );
                        });
                      },
                      onPanEnd: (_) {
                        HapticFeedback.lightImpact();
                        setState(() => _isDragging = false);
                        _updateAddress();
                      },
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _isDragging ? 1.2 : _pulseAnimation.value,
                            child: child,
                          );
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glow ring
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary.withValues(
                                  alpha: _isDragging ? 0.25 : 0.15,
                                ),
                                border: Border.all(
                                  color: AppColors.primary.withValues(
                                    alpha: _isDragging ? 0.8 : 0.4,
                                  ),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            // Pin icon
                            const Icon(
                              Icons.location_on_rounded,
                              color: AppColors.primary,
                              size: 36,
                              shadows: [
                                Shadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── DRAG HINT ───────────────────────────────────────────────────
          if (!_isDragging)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.35,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_with_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Déplacez l\'épingle ou touchez la carte',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── TOP BAR + RECHERCHE DE LIEU ──────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildCircleButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          _isEditing ? 'Modifier la zone' : 'Nouvelle zone',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      _buildCircleButton(
                        icon: Icons.close_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildSearchBar(),
                  if (_searchResults.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildSearchResults(),
                  ],
                ],
              ),
            ),
          ),

          // ── MAP CONTROLS (right side) ────────────────────────────────────
          Positioned(
            right: 16,
            bottom: bottomPanelHeight + 20,
            child: Column(
              children: [
                // Fond de carte — bascule plan / satellite (placement précis)
                _buildMapFabButton(
                  icon: Icons.layers_rounded,
                  onTap: _cycleTiles,
                  tooltip: 'Fond de carte',
                ),
                const SizedBox(height: 8),
                // Ma position — déplace l'épingle vers la position GPS de l'user
                _buildMapFabButton(
                  icon: Icons.my_location_rounded,
                  onTap: _goToMyLocation,
                  tooltip: 'Ma position',
                  isPrimary: true,
                  loading: _locating,
                ),
                const SizedBox(height: 8),
                // Recentre la caméra sur l'épingle
                _buildMapFabButton(
                  icon: Icons.filter_center_focus_rounded,
                  onTap: _centerOnMarker,
                  tooltip: 'Centrer sur l\'épingle',
                ),
                const SizedBox(height: 8),
                // Zoom in
                _buildMapFabButton(
                  icon: Icons.add_rounded,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 8),
                // Zoom out
                _buildMapFabButton(
                  icon: Icons.remove_rounded,
                  onTap: () => _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  ),
                ),
              ],
            ),
          ),

          // ── ADRESSE / COORDONNÉES (reverse geocoding) ────────────────────
          Positioned(
            left: 16,
            bottom: bottomPanelHeight + 20,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.5,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 13,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _centerAddress ?? 'Localisation…',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_center.latitude.toStringAsFixed(5)}°, ${_center.longitude.toStringAsFixed(5)}°',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── BOTTOM PANEL ─────────────────────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: bottomPanelHeight,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    Row(
                      children: [
                        if (_formStep == 1)
                          IconButton(
                            tooltip: 'Revenir à l’emplacement',
                            onPressed: () => setState(() => _formStep = 0),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formStep == 0
                                    ? '1 sur 2 · Emplacement'
                                    : '2 sur 2 · Règles et notifications',
                                style: AppTextStyles.caps,
                              ),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                value: _formStep == 0 ? 0.5 : 1,
                                minHeight: 4,
                                borderRadius: BorderRadius.circular(4),
                                color: AppColors.primary,
                                backgroundColor: AppColors.divider,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (_formStep == 0) ...[
                      // ── Zone Name ──────────────────────────────────────────
                      _buildLabel('Nom de la zone'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.label_outline_rounded,
                            color: AppColors.textHint,
                            size: 20,
                          ),
                          hintText: 'ex. Domicile, Bureau…',
                          hintStyle: const TextStyle(color: AppColors.textHint),
                          filled: true,
                          fillColor: AppColors.background,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Zone Type ──────────────────────────────────────────
                      _buildLabel('Type de zone'),
                      const SizedBox(height: 10),
                      _buildTypeSelector(),
                      const SizedBox(height: 20),

                      // ── Radius Slider ──────────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildLabel('Rayon de la zone'),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _radius >= 1000
                                  ? '${(_radius / 1000).toStringAsFixed(1)} km'
                                  : '${_radius.toInt()} m',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 10,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 22,
                          ),
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: AppColors.primary.withValues(
                            alpha: 0.15,
                          ),
                          thumbColor: AppColors.primary,
                          overlayColor:
                              AppColors.primary.withValues(alpha: 0.12),
                        ),
                        child: Slider(
                          value: _radius.clamp(_minRadius, _maxRadius),
                          min: _minRadius,
                          max: _maxRadius,
                          onChanged: (val) {
                            setState(() => _radius = val);
                          },
                          onChangeEnd: (val) {
                            _ensureCircleVisible();
                            HapticFeedback.lightImpact();
                          },
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text(
                            '100 m',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            '5 km',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (_formStep == 1) ...[
                      // ── Monitored Vehicles ─────────────────────────────────
                      _buildLabel('Véhicules surveillés'),
                      const SizedBox(height: 4),
                      Text(
                        _selectedVehicleIds.isEmpty
                            ? 'Tous les véhicules (aucun filtre)'
                            : '${_selectedVehicleIds.length} véhicule${_selectedVehicleIds.length > 1 ? 's' : ''} sélectionné${_selectedVehicleIds.length > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildVehicleSelector(),
                      const SizedBox(height: 20),

                      // ── Alert Triggers ─────────────────────────────────────
                      _buildLabel('Déclencheurs d\'alertes'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTriggerCard(
                              'À l\'entrée',
                              Icons.login_rounded,
                              _onEntry,
                              (v) => setState(() => _onEntry = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTriggerCard(
                              'À la sortie',
                              Icons.logout_rounded,
                              _onExit,
                              (v) => setState(() => _onExit = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildWhatsappToggle(),
                      const SizedBox(height: 24),
                    ],

                    // ── Save / Delete Buttons ──────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isSaving
                            ? null
                            : (_formStep == 0
                                ? _continueToRules
                                : _saveGeofence),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.primaryDark,
                          disabledBackgroundColor: AppColors.primary.withValues(
                            alpha: 0.5,
                          ),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator.adaptive(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _formStep == 0
                                        ? Icons.arrow_forward_rounded
                                        : _isEditing
                                            ? Icons.edit_rounded
                                            : Icons
                                                .check_circle_outline_rounded,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formStep == 0
                                        ? 'Continuer'
                                        : _isEditing
                                            ? 'Mettre à jour'
                                            : 'Enregistrer',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    if (_isEditing && _formStep == 1) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : _deleteGeofence,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: BorderSide(
                              color: Colors.red.withValues(alpha: 0.4),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.delete_outline_rounded, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Supprimer la zone',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSelector() {
    final vehiclesAsync = ref.watch(vehiclesProvider);
    return vehiclesAsync.when(
      data: (vehicles) {
        if (vehicles.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Aucun véhicule disponible',
              style: TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          );
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: vehicles.map((vehicle) {
            final selected = _selectedVehicleIds.contains(vehicle.id);
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (selected) {
                    _selectedVehicleIds.remove(vehicle.id);
                  } else {
                    _selectedVehicleIds.add(vehicle.id);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : AppColors.divider.withValues(alpha: 0.5),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.directions_car_rounded,
                      size: 16,
                      color: selected ? AppColors.primary : AppColors.textHint,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      vehicle.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            selected ? AppColors.primary : AppColors.textHint,
                      ),
                    ),
                    if (vehicle.plate != null && vehicle.plate!.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Text(
                        '· ${vehicle.plate}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
      loading: () => const SizedBox(
        height: 36,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
      error: (e, st) => const SizedBox.shrink(),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textHint,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onTap,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded, color: AppColors.textHint, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: (v) => _runSearch(v),
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Rechercher un lieu, une adresse…',
                hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(right: 14, left: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            )
          else if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                _searchDebounce?.cancel();
                setState(() {
                  _searchResults = [];
                  _searching = false;
                });
                FocusScope.of(context).unfocus();
              },
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(right: 12, left: 4),
                child: Icon(
                  Icons.close_rounded,
                  color: AppColors.textHint,
                  size: 18,
                ),
              ),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 264),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: _searchResults.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          color: AppColors.divider.withValues(alpha: 0.6),
        ),
        itemBuilder: (_, i) {
          final p = _searchResults[i];
          return GestureDetector(
            onTap: () => _selectPlace(p),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  const Icon(
                    Icons.place_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.shortName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (p.context.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            p.context,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMapFabButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isPrimary = false,
    bool loading = false,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: isPrimary ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isPrimary ? Colors.white : AppColors.primary,
                      ),
                    ),
                  ),
                )
              : Icon(
                  icon,
                  color: isPrimary ? Colors.white : AppColors.textPrimary,
                  size: 20,
                ),
        ),
      ),
    );
  }

  Widget _buildTriggerCard(
    String title,
    IconData icon,
    bool isActive,
    ValueChanged<bool> onChanged,
  ) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!isActive);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? AppColors.primary
                : AppColors.divider.withValues(alpha: 0.5),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.divider.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isActive ? AppColors.primary : AppColors.textHint,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.primary : AppColors.textHint,
                ),
              ),
            ),
            Transform.scale(
              scale: 0.8,
              child: Switch.adaptive(
                value: isActive,
                activeColor: AppColors.primary,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: kGeofenceTypes.map((t) {
        final selected = _type == t.key;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _type = t.key);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? t.color.withValues(alpha: 0.12)
                  : AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? t.color
                    : AppColors.divider.withValues(alpha: 0.5),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  t.icon,
                  size: 16,
                  color: selected ? t.color : AppColors.textHint,
                ),
                const SizedBox(width: 6),
                Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? t.color : AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWhatsappToggle() {
    final active = _alertViaWhatsapp;
    const waGreen = Color(0xFF25D366);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _alertViaWhatsapp = !active);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              active ? waGreen.withValues(alpha: 0.08) : AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? waGreen : AppColors.divider.withValues(alpha: 0.5),
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: active
                    ? waGreen.withValues(alpha: 0.15)
                    : AppColors.divider.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.chat_rounded,
                color: active ? waGreen : AppColors.textHint,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aussi par WhatsApp',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          active ? const Color(0xFF1E9E4A) : AppColors.textHint,
                    ),
                  ),
                  const Text(
                    'Nécessite un numéro dans votre profil',
                    style: TextStyle(fontSize: 11, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.8,
              child: Switch.adaptive(
                value: active,
                activeColor: waGreen,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _alertViaWhatsapp = v);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
