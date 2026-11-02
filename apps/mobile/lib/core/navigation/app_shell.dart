import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../../features/vehicles/views/fleet_list_view.dart';
import '../../features/map/views/map_view.dart';
import '../../features/alerts/views/alerts_view.dart';
import '../../features/settings/views/settings_view.dart';
import '../../features/reports/views/reports_view.dart';
import '../../features/entitlements/views/feature_gate.dart';
import '../../features/vehicles/providers/vehicles_provider.dart';
import '../../features/vehicles/views/vehicle_details_view.dart';
import '../layout/responsive_layout.dart';

/// Index : 0=Véhicules, 1=Carte, 2=Alertes, 3=Rapports, 4=Réglages.
final activeTabProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleDeepLink(Uri.base);
    });
  }

  void _handleDeepLink(Uri uri) {
    // 1. Paramètre Véhicule : ?vehicle=123 ou ?v=123
    final vehicleParam = uri.queryParameters['vehicle'] ??
        uri.queryParameters['v'] ??
        (uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'vehicles'
            ? uri.pathSegments[1]
            : null);
    if (vehicleParam != null) {
      final vehicleId = int.tryParse(vehicleParam);
      if (vehicleId != null) {
        ref.read(selectedVehicleIdProvider.notifier).state = vehicleId;
        ref.read(activeTabProvider.notifier).state = 1; // Bascule sur la carte
        return;
      }
    }

    // 2. Paramètre Onglet : ?tab=carte, ?tab=alertes, ?tab=rapports, etc.
    final tabParam = uri.queryParameters['tab'] ??
        (uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : null);
    if (tabParam != null) {
      switch (tabParam.toLowerCase()) {
        case 'vehicles':
        case 'vehicules':
        case 'flotte':
        case '0':
          ref.read(activeTabProvider.notifier).state = 0;
          break;
        case 'map':
        case 'carte':
        case '1':
          ref.read(activeTabProvider.notifier).state = 1;
          break;
        case 'alerts':
        case 'alertes':
        case '2':
          ref.read(activeTabProvider.notifier).state = 2;
          break;
        case 'reports':
        case 'rapports':
        case '3':
          ref.read(activeTabProvider.notifier).state = 3;
          break;
        case 'settings':
        case 'reglages':
        case 'parametres':
        case '4':
          ref.read(activeTabProvider.notifier).state = 4;
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = ref.watch(activeTabProvider);

    final body = IndexedStack(
      index: activeTab,
      children: [
        FleetListView(),
        MapView(),
        FeatureGate(
          anyOf: const ['geofencing'],
          title: 'Alertes et Zones',
          description:
              'La création de zones de sécurité et le suivi des alertes nécessitent un plan Basic ou Premium.',
          child: AlertsView(),
        ),
        FeatureGate(
          anyOf: [
            'activity_reports',
            'trip_reports',
            'speed_reports',
            'idle_reports',
            'geofence_reports',
          ],
          title: 'Rapports avancés',
          description:
              'Les rapports détaillés sont disponibles avec les plans Basic et Premium.',
          child: ReportsView(),
        ),
        SettingsView(),
      ],
    );

    final selectedVehicleId = ref.watch(selectedVehicleIdProvider);
    final vehicles = ref.watch(vehiclesProvider).valueOrNull ?? [];
    final selectedVehicle =
        vehicles.where((v) => v.id == selectedVehicleId).firstOrNull;

    final desktopBody = IndexedStack(
      index: activeTab,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 380,
              child: FleetListView(),
            ),
            const VerticalDivider(
                width: 1, thickness: 1, color: AppColors.divider),
            Expanded(
              child: Stack(
                children: [
                  const MapView(),
                  if (selectedVehicle != null)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: 400,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(-5, 0),
                            ),
                          ],
                        ),
                        child: VehicleDetailsView(
                          vehicle: selectedVehicle,
                          isDesktopPanel: true,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const MapView(),
        FeatureGate(
          anyOf: const ['geofencing'],
          title: 'Alertes et Zones',
          description:
              'La création de zones de sécurité et le suivi des alertes nécessitent un plan Basic ou Premium.',
          child: AlertsView(),
        ),
        const FeatureGate(
          anyOf: [
            'activity_reports',
            'trip_reports',
            'speed_reports',
            'idle_reports',
            'geofence_reports',
          ],
          title: 'Rapports avancés',
          description:
              'Les rapports détaillés sont disponibles avec les plans Basic et Premium.',
          child: ReportsView(),
        ),
        const SettingsView(),
      ],
    );

    void onTabChanged(int i) => ref.read(activeTabProvider.notifier).state = i;

    return ResponsiveLayout(
      mobile: Scaffold(
        body: body,
        bottomNavigationBar: _TrackeoBottomNav(
          activeTab: activeTab,
          onTabChanged: onTabChanged,
        ),
      ),
      tablet: Scaffold(
        body: Row(
          children: [
            _TrackeoNavigationRail(
              activeTab: activeTab,
              onTabChanged: onTabChanged,
            ),
            Expanded(child: body),
          ],
        ),
      ),
      desktop: Scaffold(
        body: Row(
          children: [
            _TrackeoSidebar(
              activeTab: activeTab,
              onTabChanged: onTabChanged,
            ),
            Expanded(child: desktopBody),
          ],
        ),
      ),
    );
  }
}

// ── Bottom Navigation Bar ──────────────────────────────────────────────────

class _TrackeoBottomNav extends StatelessWidget {
  final int activeTab;
  final ValueChanged<int> onTabChanged;

  const _TrackeoBottomNav({
    required this.activeTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _NavItem(
                pageIndex: 0,
                icon: Icons.list_alt_outlined,
                activeIcon: Icons.list_alt,
                label: 'Véhicules',
                activeTab: activeTab,
                onTap: () => onTabChanged(0),
              ),
              _NavItem(
                pageIndex: 1,
                icon: Icons.map_outlined,
                activeIcon: Icons.map,
                label: 'Carte',
                activeTab: activeTab,
                onTap: () => onTabChanged(1),
              ),
              _NavItem(
                pageIndex: 2,
                icon: Icons.notifications_outlined,
                activeIcon: Icons.notifications,
                label: 'Alertes',
                activeTab: activeTab,
                onTap: () => onTabChanged(2),
              ),
              _NavItem(
                pageIndex: 3,
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart_rounded,
                label: 'Rapports',
                activeTab: activeTab,
                onTap: () => onTabChanged(3),
              ),
              _NavItem(
                pageIndex: 4,
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'Profil',
                activeTab: activeTab,
                onTap: () => onTabChanged(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Nav Item with bounce ──────────────────────────────────────────────────────

class _NavItem extends StatefulWidget {
  final int pageIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int activeTab;
  final VoidCallback onTap;

  const _NavItem({
    required this.pageIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.activeTab,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce;
  late final Animation<double> _scale;

  bool get isActive => widget.activeTab == widget.pageIndex;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: AppMotion.base,
    );
    // Pop-and-settle franc, sans rebond élastique (aligné sur la landing).
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.0, end: 1.18)
              .chain(CurveTween(curve: AppMotion.quint)),
          weight: 42),
      TweenSequenceItem(
          tween: Tween<double>(begin: 1.18, end: 1.0)
              .chain(CurveTween(curve: AppMotion.quint)),
          weight: 58),
    ]).animate(_bounce);
  }

  @override
  void didUpdateWidget(_NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (isActive && oldWidget.activeTab != widget.pageIndex) {
      if (AppMotion.reduce(context)) {
        _bounce.value = _bounce.upperBound; // pas de pop si motion réduit
      } else {
        _bounce.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: isActive,
        label: widget.label,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _scale,
                builder: (_, child) =>
                    Transform.scale(scale: _scale.value, child: child),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    isActive ? widget.activeIcon : widget.icon,
                    key: ValueKey(isActive),
                    color: isActive ? AppColors.primary : AppColors.textHint,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 150),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? AppColors.primary : AppColors.textHint,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tablet Navigation Rail ──────────────────────────────────────────────────

class _TrackeoNavigationRail extends StatelessWidget {
  final int activeTab;
  final ValueChanged<int> onTabChanged;

  const _TrackeoNavigationRail({
    required this.activeTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      color: AppColors.surface,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 24),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.gps_fixed_rounded,
                  color: AppColors.primary, size: 24),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: Column(
                children: [
                  _RailItem(
                    icon: Icons.list_alt_outlined,
                    activeIcon: Icons.list_alt,
                    label: 'Véhicules',
                    isActive: activeTab == 0,
                    onTap: () => onTabChanged(0),
                  ),
                  _RailItem(
                    icon: Icons.map_outlined,
                    activeIcon: Icons.map,
                    label: 'Carte',
                    isActive: activeTab == 1,
                    onTap: () => onTabChanged(1),
                  ),
                  _RailItem(
                    icon: Icons.notifications_outlined,
                    activeIcon: Icons.notifications,
                    label: 'Alertes',
                    isActive: activeTab == 2,
                    onTap: () => onTabChanged(2),
                  ),
                  _RailItem(
                    icon: Icons.bar_chart_outlined,
                    activeIcon: Icons.bar_chart_rounded,
                    label: 'Rapports',
                    isActive: activeTab == 3,
                    onTap: () => onTabChanged(3),
                  ),
                ],
              ),
            ),
            _RailItem(
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Profil',
              isActive: activeTab == 4,
              onTap: () => onTabChanged(4),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? AppColors.primary : AppColors.textHint,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? AppColors.primary : AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Desktop Sidebar ──────────────────────────────────────────────────────────

class _TrackeoSidebar extends StatelessWidget {
  final int activeTab;
  final ValueChanged<int> onTabChanged;

  const _TrackeoSidebar({
    required this.activeTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: AppColors.surface,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.gps_fixed_rounded,
                        color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Trackeo',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _SidebarItem(
                    icon: Icons.list_alt_outlined,
                    activeIcon: Icons.list_alt,
                    label: 'Véhicules',
                    isActive: activeTab == 0,
                    onTap: () => onTabChanged(0),
                  ),
                  _SidebarItem(
                    icon: Icons.map_outlined,
                    activeIcon: Icons.map,
                    label: 'Carte Live',
                    isActive: activeTab == 1,
                    onTap: () => onTabChanged(1),
                  ),
                  _SidebarItem(
                    icon: Icons.notifications_outlined,
                    activeIcon: Icons.notifications,
                    label: 'Alertes & Sécurité',
                    isActive: activeTab == 2,
                    onTap: () => onTabChanged(2),
                  ),
                  _SidebarItem(
                    icon: Icons.bar_chart_outlined,
                    activeIcon: Icons.bar_chart_rounded,
                    label: 'Rapports & Stats',
                    isActive: activeTab == 3,
                    onTap: () => onTabChanged(3),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: _SidebarItem(
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'Profil',
                isActive: activeTab == 4,
                onTap: () => onTabChanged(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? activeIcon : icon,
                color: isActive ? AppColors.primaryDark : AppColors.textHint,
                size: 22,
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color:
                      isActive ? AppColors.primaryDark : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
