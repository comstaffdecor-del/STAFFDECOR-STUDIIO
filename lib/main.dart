/// Point d'entrée — Staff Décor Studio (port Flutter fidèle au design
/// d'origine, moteur de rendu produit corrigé — voir lib/core/perspective/).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/app_shell.dart';
import 'state/app_state.dart';

void main() {
  runApp(const StaffDecorApp());
}

class StaffDecorApp extends StatelessWidget {
  const StaffDecorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Staff Décor Studio',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const AppShell(),
      ),
    );
  }
}
