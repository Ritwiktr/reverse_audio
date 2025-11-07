import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/routes/app_router.dart';
import 'core/themes/app_theme.dart';
import 'features/audio/application/audio_controller.dart';
import 'features/audio/presentation/pages/audio_page.dart';

class ReverseAudioApp extends StatelessWidget {
  const ReverseAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AudioController()..init(),
      child: MaterialApp(
        title: AppConstants.appTitle,
        theme: AppTheme.light(),
        debugShowCheckedModeBanner: false,
        onGenerateRoute: AppRouter.onGenerateRoute,
        initialRoute: AudioPage.routeName,
      ),
    );
  }
}
