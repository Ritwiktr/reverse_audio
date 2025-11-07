import 'package:flutter/material.dart';

import '../../features/audio/presentation/pages/audio_page.dart';

class AppRouter {
  const AppRouter._();

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AudioPage.routeName:
      case '/':
        return MaterialPageRoute<void>(
          builder: (_) => const AudioPage(),
          settings: RouteSettings(
            name: AudioPage.routeName,
            arguments: settings.arguments,
          ),
        );
    }
    return MaterialPageRoute<void>(
      builder: (_) => const UnknownRouteScreen(),
      settings: settings,
    );
  }
}

class UnknownRouteScreen extends StatelessWidget {
  const UnknownRouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: const Center(
        child: Text('The page you are looking for was not found.'),
      ),
    );
  }
}
