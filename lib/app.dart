import 'package:flutter/material.dart';

import 'core/router.dart';
import 'core/theme.dart';

class AppNotas extends StatelessWidget {
  const AppNotas({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'App Notas',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: appRouter,
    );
  }
}
