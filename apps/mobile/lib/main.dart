import 'package:flutter/material.dart';

import 'core/background/background_watch.dart';
import 'core/config/app_config.dart';
import 'core/config/endpoints.dart';
import 'features/shell/auth_gate.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ağ adresleri: gömülü varsayılan + network.json (ADR-014). Zaman aşımına
  // uğrarsa gömülü/önbellek adresler geçerli kalır; uygulama beklemez.
  await Endpoints.load();

  BackgroundWatch.init();
  // Kimlik/oturum kararını AuthGate verir; arayüz hemen çizilir.
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
      home: const AuthGate(),
    );
  }
}
