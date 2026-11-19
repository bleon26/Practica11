import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_tasks/ui/widgets/offline_banner.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('Indicador visual: oculto en línea', (tester) async {
    await tester.pumpWidget(host(const OfflineBanner(online: true, pending: 3)));
    expect(find.byKey(const Key('offline-banner-text')), findsNothing);
  });

  testWidgets('Indicador visual: muestra estado offline y pendientes', (tester) async {
    await tester.pumpWidget(host(const OfflineBanner(online: false, pending: 3)));
    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(find.textContaining('3 cambios pendientes'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
  });
}
