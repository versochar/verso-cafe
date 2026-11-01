import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/accounts/account_service.dart';
import 'core/background/background_watch.dart';
import 'core/config/app_config.dart';
import 'core/config/endpoints.dart';
import 'features/shell/auth_gate.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase: kullanıcı adı/parola girişi + roller + duyurular (ADR-013).
  // Ağ adresleri: gömülü varsayılan + network.json (ADR-014). İkisi paralel
  // yürür; Endpoints zaman aşımına uğrarsa gömülü adresler geçerli kalır.
  await Future.wait([
    _initFirebase(),
    Endpoints.load(),
  ]);

  BackgroundWatch.init();
  // Kimlik/oturum kararını AuthGate verir; arayüz hemen çizilir.
  runApp(const SosyalApp());
}

/// Firebase yapılandırılmamışsa (yer tutucu `google-services.json`) uygulama
/// çökmemeli: hesaplar çalışmaz ama yerel anahtarla kullanım sürer.
Future<void> _initFirebase() async {
  try {
    await Firebase.initializeApp();
    await AccountService.configure();
  } catch (e) {
    debugPrint('Firebase başlatılamadı, yerel anahtarla devam: $e');
  }
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
