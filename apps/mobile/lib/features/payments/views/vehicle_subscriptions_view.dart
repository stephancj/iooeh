import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/product_ui.dart';
import '../../../core/navigation/trackeo_route.dart';
import '../../../core/navigation/app_shell.dart';
import '../../vehicles/repositories/vehicle_repository.dart';
import '../../vehicles/views/add_vehicle_view.dart';
import '../../entitlements/models/entitlements_model.dart';
import 'payments_view.dart';

const _protectionGreen = Color(0xFF086B55);
const _attentionInk = Color(0xFF855000);
const _attentionSurface = Color(0xFFFFF3DC);
const _attentionBadge = Color(0xFFFFE2A7);
const _activeBadge = Color(0xFFD4EFE3);
const _pageBackground = Color(0xFFFAF9F6);

final vehicleSubscriptionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
        (ref) => ref.watch(vehicleRepositoryProvider).getSubscriptions());

bool needsSubscriptionAttention(Entitlements rights) {
  if (!rights.accessAllowed) return true;
  return rights.status == 'trial' &&
      rights.trialEndsAt != null &&
      rights.trialEndsAt!.difference(DateTime.now()) <= const Duration(days: 3);
}

String subscriptionStatusLabel(Entitlements rights) {
  if (!rights.accessAllowed) return 'Expiré ou suspendu';
  if (rights.status == 'trial') {
    if (rights.trialEndsAt == null) return 'Essai gratuit';
    final days =
        (rights.trialEndsAt!.difference(DateTime.now()).inSeconds / 86400)
            .ceil();
    return days <= 1 ? 'Dernier jour' : '$days jours restants';
  }
  final date = rights.nextBillingDate?.toLocal();
  return date == null
      ? '${rights.planName} · Actif'
      : '${rights.planName} · Échéance ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class VehicleSubscriptionsView extends ConsumerStatefulWidget {
  const VehicleSubscriptionsView({super.key});
  @override
  ConsumerState<VehicleSubscriptionsView> createState() =>
      _VehicleSubscriptionsViewState();
}

class _VehicleSubscriptionsViewState
    extends ConsumerState<VehicleSubscriptionsView> {
  String query = '';
  String filter = 'Tous';
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _pageBackground,
        appBar: AppBar(
          backgroundColor: _pageBackground,
          centerTitle: false,
          title: const Text('Mes abonnements',
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark)),
        ),
        bottomNavigationBar: MediaQuery.sizeOf(context).width < 600
            ? const _ProfileSubpageNavigation()
            : null,
        body: ref.watch(vehicleSubscriptionsProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => ProductEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Abonnements indisponibles',
                  message: 'Vérifiez votre connexion.',
                  actionLabel: 'Réessayer',
                  onAction: () => ref.invalidate(vehicleSubscriptionsProvider)),
              data: (all) {
                final rows = all.where((entry) {
                  final vehicle =
                      Map<String, dynamic>.from(entry['vehicle'] as Map);
                  final rights = Entitlements.fromJson(
                      Map<String, dynamic>.from(entry['entitlements'] as Map));
                  final text =
                      '${vehicle['name']} ${vehicle['plate'] ?? ''} ${vehicle['serialNumber']}'
                          .toLowerCase();
                  final active =
                      rights.accessAllowed && rights.status == 'active';
                  final trial =
                      rights.accessAllowed && rights.status == 'trial';
                  return text.contains(query.toLowerCase()) &&
                      (filter == 'Tous' ||
                          (filter == 'Actifs' && active) ||
                          (filter == 'En essai' && trial) ||
                          (filter == 'À traiter' &&
                              needsSubscriptionAttention(rights)));
                }).toList();
                rows.sort((a, b) {
                  final ar = Entitlements.fromJson(
                      Map<String, dynamic>.from(a['entitlements'] as Map));
                  final br = Entitlements.fromJson(
                      Map<String, dynamic>.from(b['entitlements'] as Map));
                  final priority = (needsSubscriptionAttention(br) ? 1 : 0)
                      .compareTo(needsSubscriptionAttention(ar) ? 1 : 0);
                  if (priority != 0) return priority;
                  return (ar.trialEndsAt ??
                          ar.nextBillingDate ??
                          DateTime(9999))
                      .compareTo(br.trialEndsAt ??
                          br.nextBillingDate ??
                          DateTime(9999));
                });
                final attentionCount = all
                    .where((entry) => needsSubscriptionAttention(
                        Entitlements.fromJson(Map<String, dynamic>.from(
                            entry['entitlements'] as Map))))
                    .length;
                final allRights = all
                    .map((entry) => Entitlements.fromJson(
                        Map<String, dynamic>.from(
                            entry['entitlements'] as Map)))
                    .toList();
                final counts = <String, int>{
                  'Tous': all.length,
                  'À traiter': attentionCount,
                  'En essai': allRights
                      .where((rights) =>
                          rights.accessAllowed && rights.status == 'trial')
                      .length,
                  'Actifs': allRights
                      .where((rights) =>
                          rights.accessAllowed && rights.status == 'active')
                      .length,
                };
                return ListView(children: [
                  ProductPage(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            '${all.length} véhicule${all.length > 1 ? 's' : ''}${attentionCount > 0 ? ' · $attentionCount à traiter' : ''}',
                            style: AppTextStyles.bodySecondary
                                .copyWith(fontSize: 14)),
                        const SizedBox(height: 20),
                        TextField(
                            decoration: const InputDecoration(
                                labelText: 'Rechercher un véhicule',
                                hintText: 'Nom, plaque ou IMEI',
                                prefixIcon: Icon(Icons.search),
                                filled: true,
                                fillColor: AppColors.surface,
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(24)))),
                            onChanged: (v) => setState(() => query = v)),
                        const SizedBox(height: 16),
                        Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              'Tous',
                              'À traiter',
                              'En essai',
                              'Actifs'
                            ]
                                .map((v) => ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(minHeight: 44),
                                    child: ChoiceChip(
                                        label: Text('$v (${counts[v]})'),
                                        selected: filter == v,
                                        showCheckmark: false,
                                        selectedColor: _protectionGreen,
                                        backgroundColor: AppColors.surface,
                                        visualDensity: VisualDensity.compact,
                                        labelPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 2),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 3),
                                        labelStyle: TextStyle(
                                            color: filter == v
                                                ? Colors.white
                                                : AppColors.textPrimary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(24),
                                            side: const BorderSide(
                                                color: AppColors.divider)),
                                        onSelected: (_) =>
                                            setState(() => filter = v))))
                                .toList()),
                        const SizedBox(height: 16),
                        if (all.isEmpty)
                          ProductEmptyState(
                            icon: Icons.two_wheeler_outlined,
                            title: 'Votre véhicule n’est pas encore protégé',
                            message: 'Ajoutez un véhicule pour commencer.',
                            actionLabel: 'Ajouter un véhicule',
                            onAction: () async {
                              await Navigator.push(
                                  context,
                                  TrackeoRoute(
                                      builder: (_) => const AddVehicleView()));
                              if (mounted) {
                                ref.invalidate(vehicleSubscriptionsProvider);
                              }
                            },
                          )
                        else if (rows.isEmpty)
                          const ProductEmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'Aucun véhicule trouvé',
                            message: 'Modifiez votre recherche ou vos filtres.',
                            compact: true,
                          ),
                        ...rows.map((entry) {
                          final vehicle = Map<String, dynamic>.from(
                              entry['vehicle'] as Map);
                          final rights = Entitlements.fromJson(
                              Map<String, dynamic>.from(
                                  entry['entitlements'] as Map));
                          final label = subscriptionStatusLabel(rights);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Material(
                              color: AppColors.surface,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  side: const BorderSide(
                                      color: AppColors.divider)),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => Navigator.push(
                                    context,
                                    TrackeoRoute(
                                        builder: (_) => _Details(
                                            vehicle: vehicle, rights: rights))),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(children: [
                                    const CircleAvatar(
                                      radius: 24,
                                      backgroundColor: AppColors.pastelGreen,
                                      child: Icon(Icons.two_wheeler_outlined,
                                          color: _protectionGreen, size: 25),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Wrap(
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              Text(vehicle['name'] as String,
                                                  style: AppTextStyles.cardTitle
                                                      .copyWith(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w700)),
                                              _SubscriptionBadge(
                                                  rights: rights),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                              '${(vehicle['plate'] as String?)?.isNotEmpty == true ? vehicle['plate'] : vehicle['serialNumber']}',
                                              style:
                                                  AppTextStyles.bodySecondary),
                                          const SizedBox(height: 7),
                                          Text(label,
                                              style: AppTextStyles.bodySecondary
                                                  .copyWith(
                                                      color: needsSubscriptionAttention(
                                                              rights)
                                                          ? _attentionInk
                                                          : AppColors
                                                              .textSecondary)),
                                        ])),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chevron_right_rounded,
                                        color: AppColors.textHint),
                                  ]),
                                ),
                              ),
                            ),
                          );
                        }),
                      ]))
                ]);
              },
            ),
      );
}

class _ProfileSubpageNavigation extends ConsumerWidget {
  const _ProfileSubpageNavigation();

  @override
  Widget build(BuildContext context, WidgetRef ref) => BottomNavigationBar(
        currentIndex: 4,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: _protectionGreen,
        unselectedItemColor: AppColors.textSecondary,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        onTap: (index) {
          ref.read(activeTabProvider.notifier).state = index;
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.directions_car_outlined), label: 'Véhicules'),
          BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined), label: 'Carte'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications_none_rounded), label: 'Alertes'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded), label: 'Rapports'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded), label: 'Profil'),
        ],
      );
}

class _SubscriptionBadge extends StatelessWidget {
  final Entitlements rights;
  const _SubscriptionBadge({required this.rights});

  @override
  Widget build(BuildContext context) {
    final trial = rights.accessAllowed && rights.status == 'trial';
    final warning = trial || !rights.accessAllowed;
    final label = !rights.accessAllowed
        ? 'À renouveler'
        : trial
            ? 'Essai gratuit'
            : 'Actif';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: warning ? _attentionBadge : _activeBadge,
          borderRadius: BorderRadius.circular(24)),
      child: Text(label,
          style: AppTextStyles.label.copyWith(
              color: warning ? _attentionInk : _protectionGreen,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _Details extends ConsumerWidget {
  final Map<String, dynamic> vehicle;
  final Entitlements rights;
  const _Details({required this.vehicle, required this.rights});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptions = ref.watch(vehicleSubscriptionsProvider).valueOrNull;
    final matching = subscriptions
        ?.where((entry) => (entry['vehicle'] as Map)['id'] == vehicle['id']);
    final latest =
        matching != null && matching.isNotEmpty ? matching.first : null;
    final currentRights = latest == null
        ? rights
        : Entitlements.fromJson(
            Map<String, dynamic>.from(latest['entitlements'] as Map));
    final currentVehicle = latest == null
        ? vehicle
        : Map<String, dynamic>.from(latest['vehicle'] as Map);
    final trial =
        currentRights.accessAllowed && currentRights.status == 'trial';
    final ends = currentRights.trialEndsAt?.toLocal();
    final endLabel = ends == null
        ? null
        : '${ends.day.toString().padLeft(2, '0')}/${ends.month.toString().padLeft(2, '0')}/${ends.year}';
    return Scaffold(
        backgroundColor: _pageBackground,
        appBar: AppBar(
          backgroundColor: _pageBackground,
          centerTitle: false,
          title: const Text('Abonnement',
              style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark)),
        ),
        bottomNavigationBar: MediaQuery.sizeOf(context).width < 600
            ? const _ProfileSubpageNavigation()
            : null,
        body: SingleChildScrollView(
            child: ProductPage(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Row(children: [
                Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                        color: AppColors.pastelGreen, shape: BoxShape.circle),
                    child: const Icon(Icons.two_wheeler_outlined,
                        color: _protectionGreen, size: 28)),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(currentVehicle['name'] as String,
                          style: AppTextStyles.pageTitle),
                      const SizedBox(height: 4),
                      Text(
                          '${(currentVehicle['plate'] as String?)?.isNotEmpty == true ? currentVehicle['plate'] : currentVehicle['serialNumber']}',
                          style: AppTextStyles.bodySecondary),
                    ])),
              ]),
              const SizedBox(height: 24),
              ProductSurface(
                  color: trial || !currentRights.accessAllowed
                      ? _attentionSurface
                      : AppColors.pastelGreen,
                  borderColor: trial || !currentRights.accessAllowed
                      ? _attentionSurface
                      : AppColors.pastelGreen,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SubscriptionBadge(rights: currentRights),
                        const SizedBox(height: 14),
                        Text(
                            trial
                                ? subscriptionStatusLabel(currentRights)
                                : currentRights.planName,
                            style: AppTextStyles.pageTitleLarge),
                        const SizedBox(height: 6),
                        Text(
                            trial && endLabel != null
                                ? 'Fin de l’essai : $endLabel'
                                : currentRights.accessAllowed
                                    ? subscriptionStatusLabel(currentRights)
                                        .replaceFirst(
                                            '${currentRights.planName} · ', '')
                                    : subscriptionStatusLabel(currentRights),
                            style: AppTextStyles.bodySecondary
                                .copyWith(fontSize: 14))
                      ])),
              const SizedBox(height: 24),
              const ProductSectionHeader(title: 'Votre formule comprend'),
              const SizedBox(height: 10),
              ProductSurface(
                  child: Column(children: [
                if (currentRights.has('live_tracking'))
                  const ListTile(
                      leading: CircleAvatar(
                          backgroundColor: AppColors.pastelGreen,
                          child: Icon(Icons.location_on_outlined,
                              color: _protectionGreen)),
                      title: Text('Localisation en temps réel')),
                if (currentRights.has('history'))
                  ListTile(
                      leading: const CircleAvatar(
                          backgroundColor: AppColors.pastelGreen,
                          child: Icon(Icons.history_rounded,
                              color: _protectionGreen)),
                      title: Text(
                          'Historique : ${currentRights.limit('history_retention_days')} jours')),
                if (currentRights.has('geofence_alerts'))
                  const ListTile(
                      leading: CircleAvatar(
                          backgroundColor: AppColors.pastelGreen,
                          child: Icon(Icons.shield_outlined,
                              color: _protectionGreen)),
                      title: Text('Alertes de zones')),
                if (!currentRights.accessAllowed)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Renouvelez votre abonnement pour retrouver les services de votre formule.')),
              ])),
              const SizedBox(height: 24),
              ProductSurface(
                color: AppColors.pastelGreen,
                borderColor: AppColors.pastelGreen,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const ProductIcon(
                                icon: Icons.shield_outlined,
                                color: _protectionGreen),
                            const SizedBox(width: 14),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text('Choisir votre protection',
                                      style: AppTextStyles.sectionTitle),
                                  const SizedBox(height: 5),
                                  Text(
                                      'Comparez les formules et leurs avantages pour ce véhicule.',
                                      style: AppTextStyles.bodySecondary),
                                ])),
                          ]),
                      const SizedBox(height: 18),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.push(
                                context,
                                TrackeoRoute(
                                    builder: (_) => PaymentsView(
                                        vehicleId: currentVehicle['id'] as int,
                                        vehicleName:
                                            currentVehicle['name'] as String,
                                        vehicleRights: currentRights))),
                            style: FilledButton.styleFrom(
                                backgroundColor: _protectionGreen,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(48)),
                            child: Text(currentRights.status == 'active' &&
                                    currentRights.accessAllowed
                                ? 'Gérer ma formule'
                                : 'Découvrir les formules'),
                          )),
                    ]),
              ),
            ]))));
  }
}
