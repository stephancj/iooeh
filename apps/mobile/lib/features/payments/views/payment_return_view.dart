import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../entitlements/providers/entitlements_provider.dart';
import '../providers/payments_provider.dart';
import 'vehicle_subscriptions_view.dart';

class PaymentReturnView extends ConsumerStatefulWidget {
  final String reference;
  final String hintedStatus;

  const PaymentReturnView({
    super.key,
    required this.reference,
    required this.hintedStatus,
  });

  @override
  ConsumerState<PaymentReturnView> createState() => _PaymentReturnViewState();
}

class _PaymentReturnViewState extends ConsumerState<PaymentReturnView> {
  static const _maxAttempts = 15;

  String status = 'pending';
  Timer? timer;
  int attempts = 0;
  bool checking = false;
  bool timedOut = false;

  bool get _isTerminal =>
      status == 'success' || status == 'failed' || status == 'requires_review';

  @override
  void initState() {
    super.initState();
    status = widget.reference.isEmpty ? 'invalid' : 'pending';
    if (status == 'pending') _check();
  }

  Future<void> _check({bool restart = false}) async {
    if (!mounted || widget.reference.isEmpty || _isTerminal || checking) return;
    timer?.cancel();
    if (restart) {
      attempts = 0;
      timedOut = false;
    }
    setState(() => checking = true);

    try {
      final data =
          await ref.read(paymentsRepositoryProvider).status(widget.reference);
      if (!mounted) return;
      final nextStatus = (data['status'] as String? ?? 'pending').toLowerCase();
      setState(() {
        status = nextStatus;
        checking = false;
      });
      if (status == 'success') {
        ref.invalidate(entitlementsProvider);
        ref.invalidate(vehicleSubscriptionsProvider);
        ref.invalidate(vehicleEntitlementsProvider);
        return;
      }
      if (status == 'failed' || status == 'requires_review') return;
    } catch (_) {
      if (!mounted) return;
      setState(() => checking = false);
    }

    attempts += 1;
    if (!mounted) return;
    if (attempts >= _maxAttempts) {
      setState(() => timedOut = true);
      return;
    }
    timer = Timer(const Duration(seconds: 2), _check);
  }

  void _leave() =>
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final success = status == 'success';
    final failed = status == 'failed';
    final invalid = status == 'invalid';
    final review = status == 'requires_review';
    final waiting = !success && !failed && !invalid && !review && !timedOut;
    final stateColor = success
        ? AppColors.primary
        : failed || invalid
            ? AppColors.statusAlert
            : timedOut || review
                ? AppColors.batteryMedium
                : AppColors.statusIdle;
    final title = success
        ? 'Paiement confirmé'
        : failed
            ? 'Paiement non abouti'
            : invalid
                ? 'Lien de retour invalide'
                : review
                    ? 'Paiement à vérifier'
                    : timedOut
                        ? 'La confirmation prend plus de temps'
                        : 'Vérification du paiement';
    final message = success
        ? 'Votre abonnement est actif. Vous pouvez profiter immédiatement de vos nouvelles fonctionnalités.'
        : failed
            ? 'Le paiement n’a pas été confirmé. Aucun abonnement n’a été activé.'
            : invalid
                ? 'La référence du paiement est absente. Revenez dans l’application pour consulter votre abonnement.'
                : review
                    ? 'Votre paiement a été reçu, mais le véhicule a changé de propriétaire. Contactez le support avec votre référence avant de payer à nouveau.'
                    : timedOut
                        ? 'Votre paiement peut déjà être validé chez PAPI. Ne payez pas une seconde fois. Relancez simplement la vérification.'
                        : 'PAPI a terminé le parcours. Nous vérifions maintenant la confirmation sécurisée côté serveur.';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth < 520 ? AppSpacing.lg : 32,
              vertical: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - (AppSpacing.xl * 2),
              ),
              child: Center(
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 480),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppColors.divider),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDark.withValues(alpha: .06),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                    child: AnimatedSwitcher(
                      duration: AppMotion.base,
                      switchInCurve: AppMotion.quint,
                      switchOutCurve: AppMotion.quint,
                      child: Column(
                        key: ValueKey('$status-$timedOut'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _SecurityLabel(),
                          const SizedBox(height: 30),
                          _StatusMark(
                            color: stateColor,
                            waiting: waiting,
                            icon: success
                                ? Icons.check_rounded
                                : failed || invalid
                                    ? Icons.close_rounded
                                    : timedOut || review
                                        ? Icons.schedule_rounded
                                        : Icons.verified_user_outlined,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.pageTitleLarge.copyWith(
                              fontSize: 24,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body.copyWith(
                              height: 1.55,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (waiting) ...[
                            const SizedBox(height: 24),
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                              child: const LinearProgressIndicator(
                                minHeight: 5,
                                color: AppColors.statusIdle,
                                backgroundColor: AppColors.pastelBlue,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Vérification automatique en cours',
                              style: AppTextStyles.label.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (widget.reference.isNotEmpty) ...[
                            const SizedBox(height: 26),
                            _ReferenceBlock(reference: widget.reference),
                          ],
                          const SizedBox(height: 26),
                          SizedBox(
                            width: double.infinity,
                            child: timedOut
                                ? FilledButton.icon(
                                    onPressed: checking
                                        ? null
                                        : () => _check(restart: true),
                                    icon: checking
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.refresh_rounded),
                                    label: Text(checking
                                        ? 'Vérification…'
                                        : 'Vérifier à nouveau'),
                                  )
                                : FilledButton.icon(
                                    onPressed: _leave,
                                    icon: Icon(success
                                        ? Icons.arrow_forward_rounded
                                        : Icons.home_outlined),
                                    label: Text(success
                                        ? 'Continuer dans iooeh'
                                        : 'Retour à l’application'),
                                  ),
                          ),
                          if (timedOut) ...[
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _leave,
                              child: const Text('Vérifier plus tard'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityLabel extends StatelessWidget {
  const _SecurityLabel();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 16,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 7),
          Text(
            'PAIEMENT SÉCURISÉ · PAPI.MG',
            style: AppTextStyles.caps.copyWith(
              letterSpacing: .8,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      );
}

class _StatusMark extends StatelessWidget {
  final Color color;
  final bool waiting;
  final IconData icon;

  const _StatusMark({
    required this.color,
    required this.waiting,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: .11),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 38, color: color),
            if (waiting)
              SizedBox.square(
                dimension: 84,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        ),
      );
}

class _ReferenceBlock extends StatelessWidget {
  final String reference;
  const _ReferenceBlock({required this.reference});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            const Text('RÉFÉRENCE', style: AppTextStyles.caps),
            const SizedBox(height: 5),
            SelectableText(
              reference,
              textAlign: TextAlign.center,
              style: AppTextStyles.label.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}
