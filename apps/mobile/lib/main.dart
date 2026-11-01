import 'package:flutter/material.dart';

import 'core/background/background_watch.dart';
import 'core/config/app_config.dart';
import 'core/session/app_session.dart';
import 'features/shell/home_shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundWatch.init();
  // Arayüz hemen çizilir; oturum (kimlik + relay) arka planda yüklenir.
  // Böylece açılışta beyaz/boş ekran görünmez.
  AppSession.instance.init();
  BackgroundWatch.restore();
  runApp(const SosyalApp());
}

class SosyalApp extends StatelessWidget {
  const SosyalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}
