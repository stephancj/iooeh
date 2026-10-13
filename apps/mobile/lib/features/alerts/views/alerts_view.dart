import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:math' as math;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/map_attribution.dart';
import '../../../core/widgets/app_tile_layer.dart';
import '../../../core/widgets/product_ui.dart';
import '../providers/alerts_provider.dart';
import '../providers/geofences_provider.dart';
import '../models/geofence_model.dart';
import '../models/geofence_type.dart';
import '../models/alert_model.dart';
import '../../vehicles/models/vehicle_model.dart';
import 'create_geofence_view.dart';
import 'all_alerts_view.dart';
import 'widgets/alert_skeletons.dart';
import 'widgets/alert_detail_sheet.dart';
import '../../vehicles/providers/vehicles_provider.dart';
import '../../../core/providers/geocoding_provider.dart';
import '../../settings/views/alert_settings_view.dart';
import '../../../core/navigation/trackeo_route.dart';
import '../../../core/layout/responsive_layout.dart';

// Local _reverseGeocodeProvider removed in favor of global reverseGeocodeProvider

class AlertsView extends ConsumerStatefulWidget {
  const AlertsView({super.key});

  @override
  ConsumerState<AlertsView> createState() => _AlertsViewState();
}

class _AlertsViewState extends ConsumerState<AlertsView> {
  @override
  Widget build(BuildContext context) {
    final geofencesState = ref.watch(geofencesProvider);
    final alertsState = ref.watch(alertsProvider);
    final mobileBody = RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => Future.wait([
        ref.read(alertsProvider.notifier).silentRefresh(),
        ref.read(geofencesProvider.notifier).silentRefresh(),
      ]),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ProductPage(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(
                    'Zones de sécurité',
                    action: 'Ajouter',
                    onActionTap: () {
                      Navigator.push(
                        context,
                        TrackeoRoute(
                          builder: (context) => const CreateGeofenceView(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  geofencesState.when(
                    data: (geofences) {
                      if (geofences.isEmpty) {
                        return _buildGeofencesEmptyState();
                      }
                      return SizedBox(
                        height: 300,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          itemCount: geofences.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => SizedBox(
                            width: (MediaQuery.of(context).size.width - 32).clamp(280.0, 688.0),
                            child: _buildActiveGeofenceCard(geofences[i]),
                          ),
                        ),
                      );
                    },
                    loading: () => const GeofenceCarouselSkeleton(),
                    error: (e, st) => _buildErrorState('Impossible de charger les zones.'),
                  ),
                  const SizedBox(height: 32),
                  _buildActivitySectionHeader(),
                  const SizedBox(height: 12),
                  alertsState.when(
                    data: (alerts) => _buildRecentActivityList(alerts),
                    loading: () => const AlertListSkeleton(),
                    error: (e, st) => _buildErrorState('Impossible de charger les alertes.'),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final desktopBody = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 440,
          child: RefreshIndicator(
            onRefresh: () => ref.read(geofencesProvider.notifier).silentRefresh(),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              children: [
                _buildSectionHeader(
                  'Zones de sécurité',
                  action: 'Ajouter',
                  onActionTap: () {
                    Navigator.push(
                      context,
                      TrackeoRoute(
                        builder: (context) => const CreateGeofenceView(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                geofencesState.when(
                  data: (geofences) {
                    if (geofences.isEmpty) {
                      return _buildGeofencesEmptyState();
                    }
                    return Column(
                      children: [
                        for (final g in geofences) ...[
                          _buildActiveGeofenceCard(g),
                          const SizedBox(height: 16),
                        ],
                      ],
                    );
                  },
                  loading: () => const GeofenceCarouselSkeleton(),
                  error: (e, st) => _buildErrorState('Impossible de charger les zones.'),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: AppColors.divider),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(alertsProvider.notifier).silentRefresh(),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              children: [
                _buildActivitySectionHeader(),
                const SizedBox(height: 16),
                alertsState.when(
                  data: (alerts) => _buildRecentActivityList(alerts),
                  loading: () => const AlertListSkeleton(),
                  error: (e, st) => _buildErrorState('Impossible de charger les alertes.'),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return ResponsiveLayout(
      mobile: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Alertes & Zones'),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_active_outlined, color: AppColors.primary),
              tooltip: 'Paramètres d\'alertes',
              onPressed: () => Navigator.push(
                context,
                TrackeoRoute(builder: (_) => const AlertSettingsView()),
              ),
            ),
          ],
        ),
        body: mobileBody,
      ),
      desktop: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Alertes & Zones'),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_active_outlined, color: AppColors.primary),
              tooltip: 'Paramètres d\'alertes',
              onPressed: () => Navigator.push(
                context,
                TrackeoRoute(builder: (_) => const AlertSettingsView()),
              ),
            ),
          ],
        ),
        body: desktopBody,
      ),
    );
  }

  Widget _buildSectionHeader(
    String title, {
    String? action,
    VoidCallback? onActionTap,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTextStyles.sectionTitle,
        ),
        if (action != null)
          InkWell(
            onTap: onActionTap,
            borderRadius: BorderRadius.circular(6),
            hoverColor: AppColors.primary.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                action,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// En-tête "RECENT ACTIVITY" avec menu 3-points.
  Widget _buildActivitySectionHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Activité récente',
          style: AppTextStyles.sectionTitle,
        ),
        SizedBox(
          height: 28,
          width: 28,
          child: PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: const Icon(
              Icons.more_horiz_rounded,
              color: AppColors.textHint,
              size: 20,
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) async {
              if (value == 'mark_read') {
                try {
                  await ref.read(alertsProvider.notifier).markAllRead();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Toutes les alertes marquées comme lues'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Impossible de mettre à jour les alertes.'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.statusAlert,
                      ),
                    );
                  }
                }
              } else if (value == 'view_all') {
                Navigator.push(
                  context,
                  TrackeoRoute(builder: (_) => const AllAlertsView()),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'mark_read',
                child: Row(
                  children: [
                    Icon(Icons.done_all_rounded,
                        size: 18, color: AppColors.textSecondary),
                    SizedBox(width: 10),
                    Text('Marquer tout comme lu'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'view_all',
                child: Row(
                  children: [
                    Icon(Icons.list_alt_rounded,
                        size: 18, color: AppColors.textSecondary),
                    SizedBox(width: 10),
                    Text('Voir tout'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Returns a comma-separated list of vehicle names for the geofence,
  /// or null if no filter is applied (= all vehicles).
  String? _vehicleNamesFor(Geofence geofence) {
    final ids = geofence.deviceIds;
    if (ids == null || ids.isEmpty) return null;
    final vehiclesAsync = ref.watch(vehiclesProvider);
    return vehiclesAsync.whenOrNull(
          data: (vehicles) {
            final names = vehicles
                .where((v) => ids.contains(v.id))
                .map((v) => v.name)
                .toList();
            if (names.isEmpty) {
              return '${ids.length} véhicule${ids.length > 1 ? 's' : ''}';
            }
            return names.join(', ');
          },
        ) ??
        '${ids.length} véhicule${ids.length > 1 ? 's' : ''}';
  }

  /// Nom du véhicule lié à une alerte (via deviceId), ou null si introuvable.
  String? _vehicleNameFor(int deviceId) {
    final vehicles = ref.watch(vehiclesProvider).valueOrNull;
    if (vehicles == null) return null;
    for (final Vehicle v in vehicles) {
      if (v.id == deviceId) return v.name;
    }
    return null;
  }

  Widget _metaChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveGeofenceCard(Geofence geofence) {
    final vehicleNames = _vehicleNamesFor(geofence);
    final info = geofenceTypeInfo(geofence.type);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Map mockup — tap uniquement sur la partie carte
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              TrackeoRoute(
                builder: (_) => CreateGeofenceView(geofence: geofence),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: SizedBox(
                height: 140,
                child: Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(
                          geofence.centerLat,
                          geofence.centerLon,
                        ),
                        initialZoom: _calculateZoom(
                          geofence.radiusM,
                          geofence.centerLat,
                        ),
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        AppTileLayer(urlTemplate: AppMapTiles.positron),
                        const MapAttribution(alignment: Alignment.topRight),
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: LatLng(
                                geofence.centerLat,
                                geofence.centerLon,
                              ),
                              color: AppColors.primary.withValues(alpha: 0.2),
                              borderColor: AppColors.primary,
                              borderStrokeWidth: 2,
                              radius: geofence.radiusM,
                              useRadiusInMeter: true,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(
                                geofence.centerLat,
                                geofence.centerLon,
                              ),
                              width: 20,
                              height: 20,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.1,
                                      ),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              info.icon,
                              size: 14,
                              color: info.color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              geofence.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ), // end ClipRRect
          ), // end GestureDetector (carte)
          // Info row
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Ligne 1 : icône + nom/adresse + contrôles
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: info.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(info.icon, color: info.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Nom de la zone (titre)
                          Text(
                            geofence.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          // Adresse (sous-titre, géocodée)
                          Builder(
                            builder: (context) {
                              final addressAsync = ref.watch(
                                reverseGeocodeProvider(
                                  LatLng(
                                      geofence.centerLat, geofence.centerLon),
                                ),
                              );
                              return Text(
                                addressAsync.maybeWhen(
                                  data: (addr) =>
                                      addr ?? 'Position enregistrée',
                                  orElse: () => 'Localisation…',
                                ),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textHint,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: geofence.isActive,
                      activeColor: AppColors.primary,
                      onChanged: (v) {
                        ref
                            .read(geofencesProvider.notifier)
                            .toggleGeofence(geofence, v);
                      },
                    ),
                    // Bouton édition directe
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.push(
                            context,
                            TrackeoRoute(
                              builder: (_) =>
                                  CreateGeofenceView(geofence: geofence),
                            ),
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            size: 18,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Bouton actions — remplace le longPress (non fiable sur PWA)
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _showQuickActionsSheet(geofence),
                          child: const Icon(
                            Icons.more_vert_rounded,
                            size: 18,
                            color: AppColors.textHint,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Badges pleine largeur (rayon + déclencheurs actifs)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _metaChip(
                      Icons.adjust_rounded,
                      '${geofence.radiusM.toInt()} m',
                      AppColors.textSecondary,
                    ),
                    if (geofence.alertOnEntry)
                      _metaChip(Icons.login_rounded, 'Entrée', Colors.green),
                    if (geofence.alertOnExit)
                      _metaChip(Icons.logout_rounded, 'Sortie', Colors.orange),
                    if (geofence.alertViaWhatsapp)
                      _metaChip(Icons.chat_rounded, 'WhatsApp',
                          const Color(0xFF25D366)),
                  ],
                ),
                if (vehicleNames != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.directions_car_rounded,
                          size: 12, color: AppColors.textHint),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          vehicleNames,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textHint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ); // end Container
  }

  void _showQuickActionsSheet(Geofence geofence) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GeofenceActionsSheet(geofence: geofence),
    );
  }

  Widget _buildRecentActivityList(List<AlertModel> alerts) {
    if (alerts.isEmpty) {
      return _buildActivityEmptyState();
    }

    const maxVisible = 5;
    final displayed = alerts.take(maxVisible).toList();
    final hasMore = alerts.length > maxVisible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              for (var i = 0; i < displayed.length; i++) ...[
                if (i > 0)
                  const Divider(
                      height: 1, indent: 32, color: AppColors.divider),
                _buildActivityItem(displayed[i]),
              ],
            ],
          ),
        ),
        if (hasMore) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () => Navigator.push(
              context,
              TrackeoRoute(builder: (_) => const AllAlertsView()),
            ),
            borderRadius: BorderRadius.circular(16),
            hoverColor: AppColors.primary.withValues(alpha: 0.04),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: AppColors.divider.withValues(alpha: 0.8)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Voir tout (${alerts.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward_rounded,
                      color: AppColors.primary, size: 16),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Color _alertDotColor(String type) {
    switch (type) {
      case 'geofence_enter':
        return Colors.green;
      case 'geofence_exit':
        return Colors.orange;
      case 'speed_limit':
        return AppColors.statusAlert;
      case 'low_battery':
        return Colors.amber;
      case 'sleep_movement':
      case 'theft':
      case 'sos':
        return AppColors.statusAlert;
      default:
        return AppColors.primary;
    }
  }

  String _alertTitle(String type) {
    switch (type) {
      case 'geofence_enter':
        return 'Entrée dans la zone';
      case 'geofence_exit':
        return 'Sortie de la zone';
      case 'speed_limit':
        return 'Excès de vitesse';
      case 'low_battery':
        return 'Batterie faible';
      case 'sleep_movement':
        return 'Mouvement en veille';
      case 'theft':
        return 'Vol déclaré';
      case 'sos':
        return 'SOS';
      default:
        return type;
    }
  }

  Widget _buildGeofencesEmptyState() {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        TrackeoRoute(builder: (context) => const CreateGeofenceView()),
      ),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      hoverColor: AppColors.primary.withValues(alpha: 0.04),
      child: ProductSurface(
        color: AppColors.pastelGreen,
        borderColor: AppColors.primary.withValues(alpha: .22),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.radar_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Créez votre première zone',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Recevez une alerte à chaque entrée ou sortie.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textHint,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Créer',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityEmptyState() {
    return const ProductSurface(
      padding: EdgeInsets.zero,
      child: ProductEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: 'Tout est calme',
        message: 'Aucune alerte récente. Vos véhicules sont dans leurs zones.',
        compact: true,
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityItem(AlertModel alert) {
    final isOpen = alert.status == 'open';
    final dotColor = isOpen ? _alertDotColor(alert.type) : AppColors.textHint;
    final vehicleName = _vehicleNameFor(alert.deviceId);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => AlertDetailSheet.show(context, alert),
      child: Container(
        // Légère teinte de fond pour les alertes non lues
        color: isOpen
            ? _alertDotColor(alert.type).withValues(alpha: 0.04)
            : Colors.transparent,
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indicateur lu/non-lu
            Container(
              margin: const EdgeInsets.only(top: 5),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _alertTitle(alert.type),
                          style: TextStyle(
                            fontSize: 14,
                            // Gras si non lu, normal si lu
                            fontWeight:
                                isOpen ? FontWeight.w700 : FontWeight.w500,
                            color: isOpen
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (isOpen)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _alertDotColor(alert.type)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Nouveau',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _alertDotColor(alert.type),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (vehicleName != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.directions_car_rounded,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            vehicleName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isOpen
                                  ? AppColors.textSecondary
                                  : AppColors.textHint,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    alert.message ?? 'Aucun détail',
                    style: TextStyle(
                      fontSize: 12,
                      color: isOpen
                          ? AppColors.textHint
                          : AppColors.textHint.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              timeago.format(alert.createdAt),
              style: TextStyle(
                fontSize: 11,
                color: isOpen
                    ? AppColors.textHint
                    : AppColors.textHint.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateZoom(double radiusM, double lat) {
    // We want the circle to take up about 60% of the map's height (140px)
    // So 84 pixels should represent the diameter (2 * radius)
    final double metersPerPixel = (2 * radiusM) / 84;
    // zoom = log2(156543.03392 * cos(lat) / metersPerPixel)
    final double zoom = math.log(
          156543.03392 * math.cos(lat * math.pi / 180) / metersPerPixel,
        ) /
        math.ln2;
    return zoom.clamp(3.0, 18.0);
  }
}

// ── Quick-action bottom sheet ────────────────────────────────────────────────

class _GeofenceActionsSheet extends ConsumerStatefulWidget {
  final Geofence geofence;
  const _GeofenceActionsSheet({required this.geofence});

  @override
  ConsumerState<_GeofenceActionsSheet> createState() =>
      _GeofenceActionsSheetState();
}

class _GeofenceActionsSheetState extends ConsumerState<_GeofenceActionsSheet> {
  late Set<int> _selectedIds;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<int>.from(widget.geofence.deviceIds ?? []);
  }

  Future<void> _applyVehicles() async {
    setState(() => _isSaving = true);
    await ref.read(geofencesProvider.notifier).updateGeofence(
      widget.geofence.id,
      {'deviceIds': _selectedIds.toList()},
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Supprimer la zone ?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Supprimer la zone "${widget.geofence.name}" ?\nCette action est irréversible.',
          style: const TextStyle(color: AppColors.textHint),
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
    if (confirmed == true && mounted) {
      await ref
          .read(geofencesProvider.notifier)
          .deleteGeofence(widget.geofence.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehiclesAsync = ref.watch(vehiclesProvider);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          // Title
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.geofence.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Rayon ${widget.geofence.radiusM.toInt()} m',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'VÉHICULES SURVEILLÉS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textHint,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedIds.isEmpty
                ? 'Tous les véhicules (aucun filtre)'
                : '${_selectedIds.length} véhicule${_selectedIds.length > 1 ? 's' : ''} sélectionné${_selectedIds.length > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 12, color: AppColors.textHint),
          ),
          const SizedBox(height: 10),
          vehiclesAsync.when(
            data: (vehicles) {
              if (vehicles.isEmpty) {
                return const Text(
                  'Aucun véhicule disponible',
                  style: TextStyle(color: AppColors.textHint, fontSize: 13),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: vehicles.map((v) {
                  final selected = _selectedIds.contains(v.id);
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        if (selected) {
                          _selectedIds.remove(v.id);
                        } else {
                          _selectedIds.add(v.id);
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
                            color: selected
                                ? AppColors.primary
                                : AppColors.textHint,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            v.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textHint,
                            ),
                          ),
                          if (v.plate != null && v.plate!.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            Text(
                              '· ${v.plate}',
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
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              ),
            ),
            error: (e, st) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 20),
          // Apply button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _applyVehicles,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.primaryDark,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Appliquer',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          // Delete button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _isSaving ? null : _confirmDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
      ),
    );
  }
}
