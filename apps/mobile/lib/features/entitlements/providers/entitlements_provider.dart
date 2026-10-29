import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../models/entitlements_model.dart';
import '../../vehicles/repositories/vehicle_repository.dart';

final entitlementsProvider =
    FutureProvider.autoDispose<Entitlements>((ref) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get<Map<String, dynamic>>('/auth/entitlements');
  return Entitlements.fromJson(response.data!);
});

final vehicleEntitlementsProvider = FutureProvider.autoDispose
    .family<Entitlements, int>((ref, vehicleId) async {
  final subscriptions =
      await ref.watch(vehicleRepositoryProvider).getSubscriptions();
  final match = subscriptions
      .where((entry) => (entry['vehicle'] as Map)['id'] == vehicleId);
  if (match.isEmpty) throw StateError('Abonnement du véhicule introuvable.');
  return Entitlements.fromJson(
      Map<String, dynamic>.from(match.first['entitlements'] as Map));
});
