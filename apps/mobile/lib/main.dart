import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/background/background_watch.dart';
import 'core/config/app_config.dart';
import 'core/config/endpoints.dart';
import 'core/settings/app_settings.dart';
import 'features/shell/auth_gate.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ağ adresleri: gömülü varsayılan + network.json (ADR-014). Zaman aşımına
  // uğrarsa gömülü/önbellek adresler geçerli kalır; uygulama beklemez.
  await Endpoints.load();

  // Ayarları yükle (tema, dil, font)
  await AppSettings.instance.init();

  BackgroundWatch.init();
  // Kimlik/oturum kararını AuthGate verir; arayüz hemen çizilir.
  runApp(const SosyalApp());
}

class SosyalApp extends StatelessWidget {
  const SosyalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return MaterialApp(
          title: AppConfig.name,
          debugShowCheckedModeBanner: false,
          theme: AppThemeData.light(context, settings.fontScaleFactor),
          darkTheme: AppThemeData.dark(context, settings.fontScaleFactor),
          themeMode: settings.effectiveThemeMode,
          locale: settings.locale,
          localizationsDelegates: const [
            // Material localizations
            // TODO: Add app localizations when needed
          ],
          supportedLocales: const [
            Locale('tr'),
            Locale('en'),
          ],
          home: const AuthGate(),
        );
      },
    );
  }
}