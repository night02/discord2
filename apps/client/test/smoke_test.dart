import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veylor/main.dart';

void main() {
  testWidgets('renders login without native secure-storage dependency', (tester) async {
    await tester.pumpWidget(const VeylorApp(sessionRestorationEnabled:false));
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Bem-vindo ao Veylor'), findsOneWidget);
    expect(find.textContaining('Servidor:'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
