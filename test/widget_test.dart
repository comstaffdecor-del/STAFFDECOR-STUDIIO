// Test de fumée basique — vérifie que l'app démarre et affiche l'écran Home.

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/main.dart';

void main() {
  testWidgets('App démarre et affiche l\'écran Home', (WidgetTester tester) async {
    await tester.pumpWidget(const StaffDecorApp());
    await tester.pumpAndSettle();

    expect(find.text('Staff Décor'), findsWidgets);
    expect(find.text('Studio'), findsWidgets);
  });
}
