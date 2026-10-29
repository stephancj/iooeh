import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/product_ui.dart';
import '../../../core/navigation/trackeo_route.dart';
import '../../vehicles/repositories/vehicle_repository.dart';
import '../../entitlements/models/entitlements_model.dart';
import 'payments_view.dart';

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
    return days <= 1
        ? 'Essai gratuit · dernier jour'
        : 'Essai gratuit · $days jours restants';
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
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Mes abonnements')),
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
                return ListView(children: [
                  ProductPage(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            '${all.length} véhicule${all.length > 1 ? 's' : ''}',
                            style: AppTextStyles.bodySecondary),
                        const SizedBox(height: 20),
                        TextField(
                            decoration: const InputDecoration(
                                labelText: 'Rechercher un véhicule',
                                hintText: 'Nom, plaque ou IMEI',
                                prefixIcon: Icon(Icons.search)),
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
                                .map((v) => ChoiceChip(
                                    label: Text(v),
                                    selected: filter == v,
                                    onSelected: (_) =>
                                        setState(() => filter = v)))
                                .toList()),
                        const SizedBox(height: 16),
                        if (rows.isEmpty)
                          const ProductEmptyState(
                              icon: Icons.search_off_rounded,
                              title: 'Aucun véhicule trouvé',
                              message:
                                  'Modifiez votre recherche ou vos filtres.',
                              compact: true),
                        ...rows.map((entry) {
                          final vehicle = Map<String, dynamic>.from(
                              entry['vehicle'] as Map);
                          final rights = Entitlements.fromJson(
                              Map<String, dynamic>.from(
                                  entry['entitlements'] as Map));
                          final label = subscriptionStatusLabel(rights);
                          return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: ProductSurface(
                                  padding: EdgeInsets.zero,
                                  child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 8),
                                      leading: const ProductIcon(
                                          icon: Icons.directions_bike_outlined),
                                      title: Text(vehicle['name'] as String,
                                          style: AppTextStyles.cardTitle),
                                      subtitle: Text(
                                          '${vehicle['plate'] ?? vehicle['serialNumber']}\n$label'),
                                      isThreeLine: true,
                                      trailing: const Icon(
                                          Icons.chevron_right_rounded),
                                      onTap: () => Navigator.push(
                                          context,
                                          TrackeoRoute(
                                              builder: (_) => _Details(
                                                  vehicle: vehicle,
                                                  rights: rights))))));
                        }),
                      ]))
                ]);
              },
            ),
      );
}

class _Details extends StatelessWidget {
  final Map<String, dynamic> vehicle;
  final Entitlements rights;
  const _Details({required this.vehicle, required this.rights});
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Abonnement')),
      body: SingleChildScrollView(
          child: ProductPage(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text(vehicle['name'] as String, style: AppTextStyles.sectionTitle),
            Text('${vehicle['plate'] ?? vehicle['serialNumber']}',
                style: AppTextStyles.bodySecondary),
            const SizedBox(height: 24),
            ProductSurface(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(rights.planName, style: AppTextStyles.cardTitle),
                  const SizedBox(height: 8),
                  Text(subscriptionStatusLabel(rights))
                ])),
            const SizedBox(height: 24),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: () => Navigator.push(
                        context,
                        TrackeoRoute(
                            builder: (_) => PaymentsView(
                                vehicleId: vehicle['id'] as int,
                                vehicleName: vehicle['name'] as String,
                                vehicleRights: rights))),
                    child: const Text('Découvrir les formules'))),
            const SizedBox(height: 24),
            const ProductSectionHeader(title: 'Votre formule comprend'),
            const SizedBox(height: 10),
            ProductSurface(
                child: Column(children: [
              if (rights.has('live_tracking'))
                const ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('Localisation en temps réel')),
              if (rights.has('history'))
                ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(
                        'Historique : ${rights.limit('history_retention_days')} jours')),
              if (rights.has('geofence_alerts'))
                const ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('Alertes de zones'))
            ])),
          ]))));
}
