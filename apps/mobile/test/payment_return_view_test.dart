import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/payments/providers/payments_provider.dart';
import 'package:mobile/features/payments/repositories/payments_repository.dart';
import 'package:mobile/features/payments/views/payment_return_view.dart';

class _FakePaymentsRepository implements PaymentsRepository {
  final String paymentStatus;
  int checks = 0;

  _FakePaymentsRepository(this.paymentStatus);

  @override
  Future<Map<String, dynamic>> status(String reference) async {
    checks += 1;
    return {'status': paymentStatus};
  }

  @override
  Future<Map<String, dynamic>> checkout(String planId,
          {required int deviceId,
          required int expectedAmount,
          String? provider,
          String? couponCode}) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> quote(String planId,
          {required int deviceId, String? couponCode}) =>
      throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> getPlans() => throw UnimplementedError();
}

Widget _view(_FakePaymentsRepository repository) => ProviderScope(
      overrides: [
        paymentsRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const PaymentReturnView(
          reference: 'IOOEH-test-reference',
          hintedStatus: 'success',
        ),
      ),
    );

void main() {
  testWidgets('affiche la confirmation serveur quand le paiement est validé',
      (tester) async {
    await tester.pumpWidget(_view(_FakePaymentsRepository('success')));
    await tester.pump();
    await tester.pump(AppMotion.base);

    expect(find.text('Paiement confirmé'), findsOneWidget);
    expect(find.text('Continuer dans iooeh'), findsOneWidget);
  });

  testWidgets('quitte l’attente infinie et propose une nouvelle vérification',
      (tester) async {
    final repository = _FakePaymentsRepository('pending');
    await tester.pumpWidget(_view(repository));
    await tester.pump();

    for (var i = 0; i < 16; i += 1) {
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
    }
    await tester.pump(AppMotion.base);

    expect(find.text('La confirmation prend plus de temps'), findsOneWidget);
    expect(find.text('Vérifier à nouveau'), findsOneWidget);
    expect(repository.checks, 15);
  });
}
