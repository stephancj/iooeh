import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/payments/views/vehicle_subscriptions_view.dart';

Map<String, dynamic> row(int id, String name, String plate) => {
      'vehicle': {
        'id': id,
        'name': name,
        'plate': plate,
        'serialNumber': 'IMEI$id'
      },
      'entitlements': {
        'subscription': {
          'id': 'sub$id',
          'status': 'trial',
          'trialEndsAt':
              DateTime.now().add(const Duration(days: 3)).toIso8601String()
        },
        'plan': {'id': 'plan', 'code': 'free', 'name': 'Free'},
        'accessAllowed': true,
        'features': {'live_tracking': true}
      },
    };
void main() {
  testWidgets('filters vehicles by name, plate and serial number',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      vehicleSubscriptionsProvider.overrideWith(
          (ref) async => [row(1, 'Yamaha', 'ABC'), row(2, 'Honda', 'XYZ')])
    ], child: const MaterialApp(home: VehicleSubscriptionsView())));
    await tester.pumpAndSettle();
    expect(find.text('Yamaha'), findsOneWidget);
    expect(find.text('Honda'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'XYZ');
    await tester.pumpAndSettle();
    expect(find.text('Yamaha'), findsNothing);
    expect(find.text('Honda'), findsOneWidget);
  });

  testWidgets(
      'shows trial details and accessible plan action on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        vehicleSubscriptionsProvider
            .overrideWith((ref) async => [row(1, 'Yamaha', 'ABC')])
      ],
      child: const MaterialApp(home: VehicleSubscriptionsView()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Essai gratuit'), findsOneWidget);
    await tester.tap(find.text('Yamaha'));
    await tester.pumpAndSettle();
    expect(find.text('Votre formule comprend'), findsOneWidget);
    expect(find.text('Localisation en temps réel'), findsOneWidget);
    await tester.ensureVisible(find.text('Découvrir les formules'));
    expect(find.text('Découvrir les formules'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers an action when there are no vehicles', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [vehicleSubscriptionsProvider.overrideWith((ref) async => [])],
      child: const MaterialApp(home: VehicleSubscriptionsView()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un véhicule'), findsOneWidget);
  });

  testWidgets('remains usable with large text in landscape', (tester) async {
    tester.view.physicalSize = const Size(812, 375);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        vehicleSubscriptionsProvider
            .overrideWith((ref) async => [row(1, 'Yamaha', 'ABC')])
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const VehicleSubscriptionsView(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Yamaha'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Yamaha'));
    await tester.tap(find.text('Yamaha'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Découvrir les formules'));
    expect(tester.takeException(), isNull);
  });
}
