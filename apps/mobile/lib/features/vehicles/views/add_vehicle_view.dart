import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../models/vehicle_model.dart';
import '../providers/vehicles_provider.dart';

class AddVehicleView extends ConsumerStatefulWidget {
  const AddVehicleView({super.key});

  @override
  ConsumerState<AddVehicleView> createState() => _AddVehicleViewState();
}

class _AddVehicleViewState extends ConsumerState<AddVehicleView> {
  final _formKey = GlobalKey<FormState>();
  final _serialController = TextEditingController();
  final _nameController = TextEditingController();
  final _plateController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;
  Vehicle? _claimedVehicle;

  @override
  void dispose() {
    _serialController.dispose();
    _nameController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final vehicle = await ref.read(vehiclesProvider.notifier).claimVehicle(
            serialNumber: _serialController.text.replaceAll(' ', '').trim(),
            name: _nameController.text.trim(),
            plate: _plateController.text.trim(),
          );
      if (mounted) {
        setState(() {
          _claimedVehicle = vehicle;
          _isSubmitting = false;
        });
      }
    } on DioException catch (exception) {
      final data = exception.response?.data;
      final rawMessage = data is Map ? data['message'] : null;
      final message = rawMessage is List && rawMessage.isNotEmpty
          ? rawMessage.first.toString()
          : rawMessage?.toString() ??
              'Impossible d’associer le véhicule. Vérifiez votre connexion.';
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = 'Impossible d’associer le véhicule. Réessayez.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_claimedVehicle != null) {
      final liveVehicles = ref.watch(vehiclesProvider).valueOrNull ?? [];
      final latest = liveVehicles.where((v) => v.id == _claimedVehicle!.id);
      return _ActivationStatusView(
        vehicle: latest.isEmpty ? _claimedVehicle! : latest.first,
        onDone: (vehicle) => Navigator.pop<Vehicle>(context, vehicle),
      );
    }

    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Ajouter un véhicule'),
          automaticallyImplyLeading: !_isSubmitting,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.pastelGreen,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: const Icon(
                      Icons.sensors_rounded,
                      color: AppColors.primary,
                      size: 27,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Associez votre traceur',
                    style: AppTextStyles.pageTitleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Saisissez l’identifiant inscrit sur le traceur ou son emballage.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 26),
                  TextFormField(
                    controller: _serialController,
                    enabled: !_isSubmitting,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: const InputDecoration(
                      labelText: 'IMEI ou numéro de série',
                      hintText: 'Ex. 867234567890123',
                      prefixIcon: Icon(Icons.qr_code_2_rounded),
                      helperText: 'L’IMEI comporte généralement 15 chiffres.',
                    ),
                    validator: (value) {
                      final serial = value?.replaceAll(' ', '').trim() ?? '';
                      if (serial.isEmpty) return 'Identifiant requis';
                      if (serial.length < 4) return 'Identifiant trop court';
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Personnalisez le véhicule',
                    style: AppTextStyles.sectionTitle,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Ces informations vous aideront à le reconnaître dans votre flotte.',
                    style: AppTextStyles.bodySecondary,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nameController,
                    enabled: !_isSubmitting,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nom du véhicule',
                      hintText: 'Ex. Toyota Hilux',
                      prefixIcon: Icon(Icons.directions_car_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _plateController,
                    enabled: !_isSubmitting,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Immatriculation (facultatif)',
                      hintText: 'Ex. 1234 TAA',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.pastelRed,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: AppColors.statusAlert.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.statusAlert,
                            size: 19,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.statusAlert,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Associer le véhicule'),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'Un traceur ne peut être associé qu’à un seul compte.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivationStatusView extends StatelessWidget {
  const _ActivationStatusView({required this.vehicle, required this.onDone});

  final Vehicle vehicle;
  final ValueChanged<Vehicle> onDone;

  @override
  Widget build(BuildContext context) {
    final hasSignal = vehicle.position != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Activation du traceur')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: hasSignal
                      ? AppColors.pastelGreen
                      : AppColors.pastelOrange,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(
                  hasSignal
                      ? Icons.check_circle_rounded
                      : Icons.sensors_rounded,
                  color:
                      hasSignal ? AppColors.primary : AppColors.batteryMedium,
                  size: 32,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                hasSignal ? 'Premier signal reçu' : 'Traceur associé',
                style: AppTextStyles.pageTitleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                hasSignal
                    ? '${vehicle.name} transmet correctement sa position.'
                    : '${vehicle.name} est ajouté. Nous attendons maintenant sa première position GPS.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 28),
              _ActivationStep(
                done: true,
                title: 'Compte associé',
                subtitle: vehicle.serialNumber,
              ),
              const SizedBox(height: 14),
              _ActivationStep(
                done: hasSignal,
                title: 'Connexion au réseau',
                subtitle: hasSignal
                    ? 'Le traceur communique avec iooeh.'
                    : 'Laissez le traceur alimenté dans une zone couverte.',
              ),
              const SizedBox(height: 14),
              _ActivationStep(
                done: hasSignal,
                title: 'Position GPS',
                subtitle: hasSignal
                    ? 'La position est disponible sur la carte.'
                    : 'Le premier signal peut prendre quelques minutes.',
              ),
              if (!hasSignal) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Text(
                    'Vérifiez que le traceur est alimenté, que la carte SIM est active et que l’APN a été configuré.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () => onDone(vehicle),
                child: Text(hasSignal ? 'Voir sur la carte' : 'Voir ma flotte'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivationStep extends StatelessWidget {
  const _ActivationStep({
    required this.done,
    required this.title,
    required this.subtitle,
  });

  final bool done;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          color: done ? AppColors.primary : AppColors.textHint,
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.cardTitle),
              const SizedBox(height: 2),
              Text(subtitle, style: AppTextStyles.bodySecondary),
            ],
          ),
        ),
      ],
    );
  }
}
