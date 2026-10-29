import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../entitlements/providers/entitlements_provider.dart';
import 'promotions_repository.dart';
import '../payments/views/vehicle_subscriptions_view.dart';

class RedeemDialog extends ConsumerStatefulWidget {
  const RedeemDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const RedeemDialog(),
    );
  }

  @override
  ConsumerState<RedeemDialog> createState() => _RedeemDialogState();
}

class _RedeemDialogState extends ConsumerState<RedeemDialog> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  int? _deviceId;
  String? _error;
  String? _successMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleRedeem() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final repo = ref.read(promotionsRepositoryProvider);
      final rows = ref.read(vehicleSubscriptionsProvider).valueOrNull ?? [];
      final selected = _deviceId ??
          (rows.length == 1
              ? (rows.first['vehicle'] as Map)['id'] as int
              : null);
      final preview = await repo.previewCode(code, deviceId: selected);
      if (!mounted) return;
      final vehicle = rows
          .map((row) => Map<String, dynamic>.from(row['vehicle'] as Map))
          .where((v) => v['id'] == selected)
          .firstOrNull;
      final isReferral = preview['type'] == 'REFERRAL';
      final description = isReferral
          ? 'Ce code de parrainage donne droit à une réduction sur votre premier paiement éligible.'
          : '${preview['days']} jours offerts${preview['planName'] != null ? ' sur le plan ${preview['planName']}' : ''} pour ${vehicle?['name'] ?? 'ce véhicule'}.';
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: const Text('Confirmer le code'),
                content: Text(description),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Annuler')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Confirmer')),
                ],
              ));
      if (confirmed != true || !mounted) return;
      final result = await repo.redeemCode(code, deviceId: selected);

      setState(() {
        final date =
            DateTime.tryParse('${result['nextBillingDate'] ?? ''}')?.toLocal();
        final dateLabel = date == null
            ? ''
            : ' Nouvelle échéance : ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}.';
        _successMessage =
            '${result['message'] as String? ?? 'Code appliqué avec succès !'}$dateLabel';
      });

      // Rafraîchir les droits utilisateur dans l'application
      ref.invalidate(entitlementsProvider);
      ref.invalidate(vehicleSubscriptionsProvider);
    } catch (e) {
      if (!mounted) return;
      String msg = 'Code invalide ou expiré.';
      if (e is DioException && e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map && data['message'] != null) {
          msg = data['message'].toString();
        }
      }
      setState(() {
        _error = msg;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.card_giftcard, color: Color(0xFF2563EB)),
          SizedBox(width: 8),
          Text('Code Promo / Parrainage'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Saisissez un code coupon ou un code de parrainage pour bénéficier d’une offre sur votre compte.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ref.watch(vehicleSubscriptionsProvider).when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) =>
                      const Text('Impossible de charger les véhicules.'),
                  data: (rows) => DropdownButtonFormField<int>(
                    value: _deviceId ??
                        (rows.length == 1
                            ? (rows.first['vehicle'] as Map)['id'] as int
                            : null),
                    decoration:
                        const InputDecoration(labelText: 'Véhicule concerné'),
                    items: rows.map((row) {
                      final vehicle =
                          Map<String, dynamic>.from(row['vehicle'] as Map);
                      return DropdownMenuItem<int>(
                          value: vehicle['id'] as int,
                          child: Text(
                              '${vehicle['name']} · ${vehicle['plate'] ?? vehicle['serialNumber']}'));
                    }).toList(),
                    onChanged: (value) => setState(() => _deviceId = value),
                  ),
                ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Code Promo (ex: WELCOME20 ou REF-XXXXXX)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.confirmation_number_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _controller.clear(),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
            if (_successMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_successMessage!,
                          style: const TextStyle(
                              color: Colors.green,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleRedeem,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Valider'),
        ),
      ],
    );
  }
}
