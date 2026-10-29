import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/payments/views/vehicle_subscriptions_view.dart';

Map<String, dynamic> row(int id, String name, String plate) => {
  'vehicle': {'id': id, 'name': name, 'plate': plate, 'serialNumber': 'IMEI$id'},
  'entitlements': {'subscription': {'id': 'sub$id', 'status': 'trial', 'trialEndsAt': DateTime.now().add(const Duration(days: 3)).toIso8601String()}, 'plan': {'id': 'plan', 'code': 'free', 'name': 'Free'}, 'accessAllowed': true, 'features': {'live_tracking': true}},
};
void main() {
  testWidgets('filters vehicles by name, plate and serial number', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [vehicleSubscriptionsProvider.overrideWith((ref) async => [row(1, 'Yamaha', 'ABC'), row(2, 'Honda', 'XYZ')])], child: const MaterialApp(home: VehicleSubscriptionsView())));
    await tester.pumpAndSettle();
    expect(find.text('Yamaha'), findsOneWidget);
    expect(find.text('Honda'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'XYZ');
    await tester.pumpAndSettle();
    expect(find.text('Yamaha'), findsNothing);
    expect(find.text('Honda'), findsOneWidget);
  });
}
