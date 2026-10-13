import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/map_attribution.dart';
import '../../../core/widgets/app_tile_layer.dart';
import '../../../core/widgets/product_ui.dart';
import '../models/vehicle_model.dart';
import '../providers/vehicles_provider.dart';
import '../../../core/providers/geocoding_provider.dart';
import '../../../core/navigation/app_shell.dart';
import 'widgets/status_badge.dart';
import '../../entitlements/providers/entitlements_provider.dart';
import '../../security/providers/security_provider.dart';

class VehicleDetailsView extends ConsumerWidget {
  final Vehicle vehicle;
  final bool isDesktopPanel;
  const VehicleDetailsView({super.key, required this.vehicle, this.isDesktopPanel = false});

  static const double _heroHeight = 220.0;

  IconData _vehicleIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('bus') || n.contains('school')) return Icons.directions_bus;
    if (n.contains('truck') || n.contains('transit') || n.contains('van')) {
      return Icons.local_shipping;
    }
    if (n.contains('moto') || n.contains('pcx') || n.contains('bike')) {
      return Icons.pedal_bike;
    }
    return Icons.directions_car;
  }

  Color _heroAccent(String name) {
    final n = name.toLowerCase();
    if (n.contains('toyota')) return const Color(0xFF3B82F6);
    if (n.contains('transit')) return const Color(0xFFE65100);
    if (n.contains('bus')) return const Color(0xFF9C27B0);
    if (n.contains('tesla')) return const Color(0xFFEF4444);
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveVehicles = ref.watch(vehiclesProvider).valueOrNull ?? const [];
    var vehicle = this.vehicle;
    for (final candidate in liveVehicles) {
      if (candidate.id == this.vehicle.id) {
        vehicle = candidate;
        break;
      }
    }
    final pos = vehicle.position;
    final addressAsync = pos != null
        ? ref.watch(reverseGeocodeProvider(LatLng(pos.lat, pos.lon)))
        : null;
    final accent = _heroAccent(vehicle.name);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Hero SliverAppBar ──────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: _heroHeight,
            pinned: true,
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: isDesktopPanel
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
            leadingWidth: isDesktopPanel ? 0 : 56,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded, size: 20),
                tooltip: 'Modifier',
                onPressed: () => _showEditSheet(context, ref, vehicle),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.parallax,
              background: _HeroBackground(
                vehicle: vehicle,
                icon: _vehicleIcon(vehicle.name),
                accent: accent,
              ),
            ),
          ),

          // ── Content ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: ProductPage(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),

                  // ── Status Row ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        StatusBadge(status: vehicle.status),
                        const SizedBox(width: 10),
                        Text(
                          vehicle.lastUpdate != null
                              ? 'Mis à jour ${timeago.format(vehicle.lastUpdate!, locale: 'fr')}'
                              : 'Jamais mis à jour',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ProductSurface(
                      padding: const EdgeInsets.all(8),
                      child: GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 2.15,
                        children: [
                          _StatPill(
                            icon: Icons.battery_charging_full_rounded,
                            label: 'Batterie',
                            value: pos?.battery != null
                                ? '${pos!.battery}%'
                                : '--',
                            color: (pos?.battery ?? 100) > 20
                                ? AppColors.primary
                                : AppColors.statusAlert,
                          ),
                          _StatPill(
                            icon: Icons.speed_rounded,
                            label: 'Vitesse',
                            value: pos?.speedKmh != null
                                ? '${pos!.speedKmh.toStringAsFixed(0)} km/h'
                                : '0 km/h',
                            color: (pos?.speedKmh ?? 0) > 120
                                ? AppColors.statusAlert
                                : AppColors.statusIdle,
                          ),
                          _StatPill(
                            icon: Icons.power_settings_new_rounded,
                            label: 'Moteur',
                            value: pos?.ignition == true ? 'Allumé' : 'Éteint',
                            color: pos?.ignition == true
                                ? AppColors.primary
                                : AppColors.textHint,
                          ),
                          _StatPill(
                            icon: Icons.signal_cellular_alt_rounded,
                            label: 'Signal',
                            value: (pos?.rssi ?? 25) > 20 ? 'Fort' : 'Faible',
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _SleepModePanel(vehicle: vehicle),
                  ),

                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _SecurityActionsPanel(vehicle: vehicle),
                  ),

                  const SizedBox(height: 20),

                  // ── Map Preview ───────────────────────────────────────────
                  if (pos != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ProductSectionHeader(
                            title: 'Position actuelle',
                            subtitle:
                                'Touchez la carte pour l’ouvrir en plein écran.',
                          ),
                          const SizedBox(height: 10),
                          _MapCard(
                            vehicle: vehicle,
                            pos: pos,
                            addressAsync: addressAsync,
                            ref: ref,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    Vehicle vehicle,
  ) async {
    final nameController = TextEditingController(text: vehicle.name);
    final plateController = TextEditingController(text: vehicle.plate ?? '');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditVehicleSheet(
        nameController: nameController,
        plateController: plateController,
        serialNumber: vehicle.serialNumber,
        onSave: () async {
          Navigator.pop(ctx);
          try {
            await ref.read(vehiclesProvider.notifier).updateVehicle(
              vehicle.id,
              {
                'name': nameController.text,
                'attributes': {'plate': plateController.text},
              },
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: AppColors.primaryDark, size: 18),
                      SizedBox(width: 10),
                      Text('Véhicule mis à jour',
                          style: TextStyle(color: AppColors.primaryDark)),
                    ],
                  ),
                  backgroundColor: AppColors.primary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Impossible de modifier le véhicule.'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        },
      ),
    );
  }
}

class _SecurityActionsPanel extends ConsumerStatefulWidget {
  final Vehicle vehicle;
  const _SecurityActionsPanel({required this.vehicle});
  @override
  ConsumerState<_SecurityActionsPanel> createState() =>
      _SecurityActionsPanelState();
}

class _SecurityActionsPanelState extends ConsumerState<_SecurityActionsPanel> {
  bool busy = false;
  Future<void> _run(String kind) async {
    if (busy) return;
    if (kind == 'theft') {
      final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                      title: const Text('Signaler ce véhicule volé ?'),
                      content: const Text(
                          'Un incident critique sera créé. Vous disposerez de 60 secondes pour annuler un faux signalement.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Annuler')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Confirmer le vol'))
                      ])) ??
          false;
      if (!confirmed) return;
    }
    setState(() => busy = true);
    try {
      final repo = ref.read(securityRepositoryProvider);
      if (kind == 'sos') await repo.sos(widget.vehicle.id);
      if (kind == 'theft') {
        final incident = await repo.theft(widget.vehicle.id);
        if (mounted) {
          final cancel = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const _TheftCountdownDialog(),
          ) ?? false;
          if (cancel) {
            await repo.cancelTheft(incident['id'] as String);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Signalement annulé.')));
            }
          }
        }
      }
      if (kind == 'share') {
        final result = await repo.createLink(widget.vehicle.id, 60);
        if (mounted) {
          await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                      title: const Text('Lien de suivi créé'),
                      content: SelectableText(result['url'] as String),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Fermer'))
                      ]));
        }
      }
      if (mounted && kind == 'sos') {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('SOS transmis au support.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Action indisponible pour votre plan ou votre véhicule.')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rights = ref.watch(entitlementsProvider).valueOrNull;
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sécurité & partage',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: busy || !(rights?.has('sos_alerts') ?? false)
                        ? null
                        : () => _run('sos'),
                    icon: const Icon(Icons.sos_rounded),
                    label: const Text('SOS'))),
            const SizedBox(width: 8),
            Expanded(
                child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.statusAlert),
                    onPressed: busy || !(rights?.has('theft_mode') ?? false)
                        ? null
                        : () => _run('theft'),
                    icon: const Icon(Icons.shield_rounded),
                    label: const Text('Mode vol')))
          ]),
          const SizedBox(height: 8),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                  onPressed:
                      busy || !(rights?.has('public_tracking_links') ?? false)
                          ? null
                          : () => _run('share'),
                  icon: const Icon(Icons.share_location_rounded),
                  label: const Text('Partager le suivi pendant 1 heure')))
        ]));
  }
}

class _SleepModePanel extends ConsumerStatefulWidget {
  final Vehicle vehicle;
  const _SleepModePanel({required this.vehicle});

  @override
  ConsumerState<_SleepModePanel> createState() => _SleepModePanelState();
}

class _SleepModePanelState extends ConsumerState<_SleepModePanel> {
  bool _saving = false;

  Future<void> _toggle() async {
    setState(() => _saving = true);
    try {
      if (widget.vehicle.sleepMode?.active == true) {
        await ref
            .read(vehiclesProvider.notifier)
            .disableSleepMode(widget.vehicle.id);
      } else {
        await ref
            .read(vehiclesProvider.notifier)
            .enableSleepMode(widget.vehicle.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.vehicle.sleepMode?.active == true
                ? 'Veille désactivée'
                : 'Veille activée, ioeh surveille ce véhicule.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible de modifier la veille. Vérifiez que le véhicule est bien à l’arrêt.',
          ),
          backgroundColor: AppColors.statusAlert,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rights = ref.watch(entitlementsProvider).valueOrNull;
    final sleepIncluded = rights?.has('sleep_mode') ?? true;
    final mode = widget.vehicle.sleepMode;
    final isActive = mode?.active == true;
    final isTriggered = mode?.triggered == true;
    final canEnable = sleepIncluded &&
        widget.vehicle.status == VehicleStatus.idle &&
        widget.vehicle.position != null;
    final color = isTriggered
        ? AppColors.statusAlert
        : isActive
            ? AppColors.primary
            : AppColors.primaryDark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isTriggered
            ? AppColors.pastelRed
            : isActive
                ? AppColors.pastelGreen
                : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? color.withValues(alpha: 0.35) : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isTriggered
                      ? Icons.warning_amber_rounded
                      : Icons.shield_outlined,
                  color: color,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTriggered
                          ? 'Mouvement détecté'
                          : isActive
                              ? 'Veille active'
                              : 'Veille antivol',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isTriggered
                          ? 'Le véhicule a quitté son point de veille. Consultez sa position et désactivez la veille après vérification.'
                          : isActive
                              ? 'Une alerte sera envoyée au-delà de ${mode!.movementThresholdM} m du point actuel.'
                              : !sleepIncluded
                                  ? 'Disponible avec les plans Basic et Premium.'
                                  : canEnable
                                      ? 'Surveille le véhicule à l’arrêt et vous alerte s’il est déplacé.'
                                      : 'Disponible lorsque le véhicule est arrêté et transmet sa position.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: isActive
                ? OutlinedButton.icon(
                    onPressed: _saving ? null : _toggle,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.shield_outlined, size: 18),
                    label: const Text('Désactiver la veille'),
                  )
                : ElevatedButton.icon(
                    onPressed: canEnable && !_saving ? _toggle : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.shield_outlined, size: 18),
                    label: const Text('Activer la veille'),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Hero Background ────────────────────────────────────────────────────────────

class _HeroBackground extends StatelessWidget {
  final Vehicle vehicle;
  final IconData icon;
  final Color accent;

  const _HeroBackground({
    required this.vehicle,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryDark,
      child: Stack(
        children: [
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: vehicle.imageUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.network(
                            vehicle.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              icon,
                              size: 34,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : Icon(icon, size: 34, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vehicle.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.4,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (vehicle.plate?.isNotEmpty == true)
                            _HeroMeta(label: vehicle.plate!),
                          _HeroMeta(label: vehicle.serialNumber, muted: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMeta extends StatelessWidget {
  final String label;
  final bool muted;
  const _HeroMeta({required this.label, this.muted = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: muted ? .08 : .14),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: muted ? .65 : .95),
            fontSize: 11,
            fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
            letterSpacing: muted ? .2 : .8,
          ),
        ),
      );
}

// ── Stat Pill ─────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                Text(label, style: AppTextStyles.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Map Card ──────────────────────────────────────────────────────────────────

class _MapCard extends StatelessWidget {
  final Vehicle vehicle;
  final VehiclePosition pos;
  final AsyncValue<String?>? addressAsync;
  final WidgetRef ref;

  const _MapCard({
    required this.vehicle,
    required this.pos,
    required this.addressAsync,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              ref.read(activeTabProvider.notifier).state = 1;
              ref.read(selectedVehicleIdProvider.notifier).state = vehicle.id;
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            child: AbsorbPointer(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(pos.lat, pos.lon),
                  initialZoom: 15,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  AppTileLayer(urlTemplate: AppMapTiles.positron),
                  const MapAttribution(alignment: Alignment.topRight),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(pos.lat, pos.lon),
                        width: 44,
                        height: 44,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.primary.withValues(alpha: 0.45),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.directions_car,
                            color: AppColors.primaryDark,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Bottom address overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.65),
                  ],
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: Colors.white70,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: addressAsync?.when(
                          data: (addr) => Text(
                            addr ?? 'Position inconnue',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          loading: () => const Text(
                            'Localisation...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          error: (_, __) => const Text(
                            'Position inconnue',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ) ??
                        const SizedBox.shrink(),
                  ),
                  const Icon(
                    Icons.open_in_full_rounded,
                    color: Colors.white54,
                    size: 14,
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

// ── Edit Vehicle Bottom Sheet ─────────────────────────────────────────────────

class _EditVehicleSheet extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController plateController;
  final String serialNumber;
  final VoidCallback onSave;

  const _EditVehicleSheet({
    required this.nameController,
    required this.plateController,
    required this.serialNumber,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        8,
        24,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
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

            const Text(
              'Modifier le véhicule',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 24),

            _SheetField(
              controller: nameController,
              label: 'Nom du véhicule',
              hint: 'ex. Toyota RAV4',
              icon: Icons.directions_car_rounded,
            ),
            const SizedBox(height: 14),
            _SheetField(
              controller: plateController,
              label: 'Plaque d\'immatriculation',
              hint: 'ex. ABC-1234',
              icon: Icons.badge_rounded,
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.fingerprint_rounded,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('IMEI', style: AppTextStyles.label),
                        Text(serialNumber, style: AppTextStyles.cardTitle),
                      ],
                    ),
                  ),
                  const Icon(Icons.lock_outline_rounded,
                      color: AppColors.textHint, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.primaryDark,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_rounded, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Enregistrer',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;

  const _SheetField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

class _TheftCountdownDialog extends StatefulWidget {
  const _TheftCountdownDialog();

  @override
  State<_TheftCountdownDialog> createState() => _TheftCountdownDialogState();
}

class _TheftCountdownDialogState extends State<_TheftCountdownDialog> {
  late Timer _timer;
  int _secondsLeft = 60;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mode vol activé'),
      content: Text(
        'Le support a été alerté. En cas de faux signalement, vous pouvez encore annuler pendant ${_secondsLeft > 0 ? _secondsLeft : 0} seconde(s).'
      ),
      actions: [
        TextButton(
          onPressed: _secondsLeft > 0 ? () => Navigator.pop(context, true) : null,
          child: const Text('Annuler le signalement'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Continuer'),
        ),
      ],
    );
  }
}
