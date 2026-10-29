import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../../core/platform/payment_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/product_ui.dart';
import '../../entitlements/models/entitlements_model.dart';
import '../../entitlements/providers/entitlements_provider.dart';
import '../providers/payments_provider.dart';

class PaymentsView extends ConsumerStatefulWidget {
  final bool isDesktopPanel;
  final int? vehicleId;
  final String? vehicleName;
  final Entitlements? vehicleRights;
  const PaymentsView(
      {super.key,
      this.isDesktopPanel = false,
      this.vehicleId,
      this.vehicleName,
      this.vehicleRights});

  @override
  ConsumerState<PaymentsView> createState() => _PaymentsViewState();
}

class _PaymentsViewState extends ConsumerState<PaymentsView> {
  String? _selectedPlanId;
  String? _loadingPlanId;
  final _couponController = TextEditingController();

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  Future<void> _checkout(Map<String, dynamic> plan) async {
    final id = plan['id'] as String;
    if (widget.vehicleId == null) return;
    final coupon = _couponController.text.trim();
    setState(() => _loadingPlanId = id);
    try {
      final quote = await ref.read(paymentsRepositoryProvider).quote(
            id,
            deviceId: widget.vehicleId!,
            couponCode: coupon.isNotEmpty ? coupon : null,
          );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmer le paiement'),
          content: Text(
              '${widget.vehicleName ?? 'Véhicule'}\n${plan['name']}\nMontant : ${_formatAmount((quote['amount'] as num).toDouble())} ${quote['currency']}\n${quote['referralDiscount'] == true ? 'Réduction de parrainage appliquée.\n' : ''}${quote['testMode'] == true ? 'Paiement en mode test.' : ''}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Continuer')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final result = await ref.read(paymentsRepositoryProvider).checkout(
            id,
            deviceId: widget.vehicleId!,
            expectedAmount: (quote['amount'] as num).toInt(),
            couponCode: coupon.isNotEmpty ? coupon : null,
          );
      await openPaymentUrl(result['paymentLink'] as String);
    } on DioException catch (e) {
      final msg = e.response?.data is Map && e.response?.data['message'] != null
          ? (e.response!.data['message'] is List
              ? (e.response!.data['message'] as List).join(', ')
              : e.response!.data['message'].toString())
          : 'Le paiement n’a pas pu démarrer. Réessayez.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.statusAlert,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Le paiement n’a pas pu démarrer. Réessayez.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.statusAlert,
        ));
      }
    } finally {
      if (mounted) setState(() => _loadingPlanId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(purchasablePlansProvider);
    final rightsAsync = ref.watch(entitlementsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.isDesktopPanel
          ? null
          : AppBar(
              title: Text(widget.vehicleName == null
                  ? 'Abonnement'
                  : 'Abonnement · ${widget.vehicleName}')),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ProductEmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Plans indisponibles',
          message: 'Vérifiez votre connexion, puis réessayez.',
          actionLabel: 'Réessayer',
          onAction: () => ref.invalidate(purchasablePlansProvider),
        ),
        data: (allPlans) {
          final plans = allPlans
              .where((plan) => _amount(plan) > 0)
              .toList(growable: false);
          final rights = widget.vehicleRights ?? rightsAsync.valueOrNull;
          final selected = _selectedPlan(plans, rights);
          return SingleChildScrollView(
            child: ProductPage(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CurrentPlanSummary(rights: rights),
                  const SizedBox(height: 28),
                  const ProductSectionHeader(
                    title: 'Choisir votre protection',
                    subtitle:
                        'Choisissez le niveau de protection adapté à vos besoins.',
                  ),
                  const SizedBox(height: 12),
                  if (plans.isEmpty)
                    const ProductSurface(
                      child:
                          Text('Aucun plan payant disponible pour le moment.'),
                    )
                  else ...[
                    ProductSurface(
                      padding: const EdgeInsets.all(6),
                      child: Row(
                        children: [
                          for (final plan in plans)
                            Expanded(
                              child: _PlanSelector(
                                label: plan['name'] as String,
                                selected: plan['id'] == selected?['id'],
                                current: plan['code'] == rights?.planCode,
                                onTap: () => setState(
                                  () => _selectedPlanId = plan['id'] as String,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (selected != null)
                      _PlanDetails(
                        plan: selected,
                        active: selected['code'] == rights?.planCode,
                        loading: selected['id'] == _loadingPlanId,
                        disabled:
                            _loadingPlanId != null || widget.vehicleId == null,
                        couponController: _couponController,
                        onCheckout: () => _checkout(selected),
                      ),
                  ],
                  const SizedBox(height: 16),
                  const _PaymentTrustNote(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Map<String, dynamic>? _selectedPlan(
    List<Map<String, dynamic>> plans,
    Entitlements? rights,
  ) {
    if (plans.isEmpty) return null;
    for (final plan in plans) {
      if (plan['id'] == _selectedPlanId) return plan;
    }
    for (final plan in plans) {
      if (plan['code'] == rights?.planCode) return plan;
    }
    return plans.first;
  }
}

class _CurrentPlanSummary extends StatelessWidget {
  final Entitlements? rights;
  const _CurrentPlanSummary({required this.rights});

  @override
  Widget build(BuildContext context) => ProductSurface(
        color: AppColors.primaryDark,
        borderColor: AppColors.primaryDark,
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rights == null
                        ? 'Votre abonnement'
                        : 'Plan ${rights!.planName}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _statusText(rights),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .68),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                rights?.status == 'trial' ? 'ESSAI' : 'ACTIF',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .7,
                ),
              ),
            ),
          ],
        ),
      );

  static String _statusText(Entitlements? rights) {
    if (rights == null) return 'Chargement de votre statut…';
    final date = rights.nextBillingDate ?? rights.trialEndsAt;
    if (date == null) {
      return rights.status == 'trial'
          ? 'Période d’essai en cours'
          : 'Protection active';
    }
    final local = date.toLocal();
    final formatted = '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
    return rights.status == 'trial'
        ? 'Essai jusqu’au $formatted'
        : 'Prochain renouvellement le $formatted';
  }
}

class _PlanSelector extends StatelessWidget {
  final String label;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  const _PlanSelector({
    required this.label,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.quint,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryDark : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (current)
                Text(
                  'actuel',
                  style: TextStyle(
                    color: selected ? AppColors.primary : AppColors.textHint,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
      );
}

class _PlanDetails extends StatelessWidget {
  final Map<String, dynamic> plan;
  final bool active;
  final bool loading;
  final bool disabled;
  final TextEditingController couponController;
  final VoidCallback onCheckout;

  const _PlanDetails({
    required this.plan,
    required this.active,
    required this.loading,
    required this.disabled,
    required this.couponController,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final name = plan['name'] as String;
    final description = plan['description'] as String?;
    final benefits = _benefitsFor(plan);
    return ProductSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: AppTextStyles.sectionTitle),
          const SizedBox(height: 5),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _formatAmount(_amount(plan)),
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.6,
                  ),
                ),
                const TextSpan(
                  text: ' MGA / mois',
                  style: AppTextStyles.bodySecondary,
                ),
              ],
            ),
          ),
          if (description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(description!,
                style: AppTextStyles.bodySecondary.copyWith(height: 1.45)),
          ],
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 16),
          for (final benefit in benefits) ...[
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary, size: 19),
                const SizedBox(width: 10),
                Expanded(child: Text(benefit, style: AppTextStyles.body)),
              ],
            ),
            const SizedBox(height: 11),
          ],
          ...[
            const SizedBox(height: 10),
            TextField(
              controller: couponController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Code promo (Optionnel)',
                hintText: 'Ex: WELCOME20',
                prefixIcon: Icon(Icons.local_offer_outlined, size: 18),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: disabled ? null : onCheckout,
              child: Text(
                loading
                    ? 'Préparation du paiement…'
                    : active
                        ? 'Renouveler $name'
                        : 'Choisir $name',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentTrustNote extends StatelessWidget {
  const _PaymentTrustNote();

  @override
  Widget build(BuildContext context) => const ProductSurface(
        color: AppColors.pastelGreen,
        borderColor: AppColors.pastelGreen,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded,
                color: AppColors.primaryDark, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Paiement sécurisé par PAPI.mg. Vous serez redirigé vers leur page, puis ramené ici après confirmation.',
                style: TextStyle(
                  color: AppColors.primaryDark,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
}

double _amount(Map<String, dynamic> plan) =>
    double.tryParse('${plan['priceMonthly']}') ?? 0;

String _formatAmount(double amount) {
  final digits = amount.round().toString();
  final output = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) output.write(' ');
    output.write(digits[i]);
  }
  return output.toString();
}

List<String> _benefitsFor(Map<String, dynamic> plan) {
  final grants = plan['planFeatures'] as List<dynamic>? ?? const [];
  return grants.whereType<Map>().where((grant) {
    final feature = grant['feature'];
    return grant['enabled'] == true &&
        feature is Map &&
        feature['isActive'] == true &&
        grant['value'] != false;
  }).map((grant) {
    final feature = grant['feature'] as Map;
    final value = grant['value'];
    final unit = feature['unit'];
    return value is num
        ? '${feature['name']} : $value ${unit ?? ''}'.trim()
        : '${feature['name']}';
  }).toList();
}
