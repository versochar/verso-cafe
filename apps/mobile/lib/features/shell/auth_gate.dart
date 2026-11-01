/// Açılış kapısı: hesap oturumu/yerel anahtar varsa akışa, yoksa girişe.
///
/// Sıra: Firebase oturumu tek başına yetmez — anahtar parolayla şifreli
/// olduğundan cihazda anahtar bulunmalı (yoksa yeniden giriş istenir).
library;

import 'package:flutter/material.dart';

import '../../core/accounts/account_service.dart';
import '../../core/background/background_watch.dart';
import '../../core/identity/key_storage.dart';
import '../../core/session/app_session.dart';
import '../auth/login_page.dart';
import 'home_shell.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _Phase { deciding, signedIn, signedOut }

class _AuthGateState extends State<AuthGate> {
  _Phase _phase = _Phase.deciding;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    var firebaseSignedIn = false;
    try {
      await AccountService.instance.restore();
      firebaseSignedIn = AccountService.instance.signedIn;
    } catch (_) {
      // Firebase yok/erişilemez (yer tutucu yapılandırma ya da çevrimdışı):
      // yerel anahtar yeter, uygulama açılmaya devam eder.
    }
    final keys = await KeyStorage().loadKeys();
    if (keys == null) {
      if (firebaseSignedIn) {
        // Oturum var ama anahtar cihazda yok: parola gerekir → temiz gir.
        try {
          await AccountService.instance.signOut();
        } catch (_) {
          // Firebase'e ulaşılamıyorsa yerel durum zaten anahtarsız.
        }
      }
      if (mounted) setState(() => _phase = _Phase.signedOut);
      return;
    }
    await _startSession();
  }

  Future<void> _startSession() async {
    await AppSession.instance.init();
    BackgroundWatch.restore();
    if (mounted) setState(() => _phase = _Phase.signedIn);
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.deciding:
        return const Scaffold(
          body: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        );
      case _Phase.signedIn:
        return const HomeShell();
      case _Phase.signedOut:
        return LoginPage(onAuthenticated: _startSession);
    }
  }
}
