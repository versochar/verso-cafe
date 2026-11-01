/// Giriş / kayıt ekranı — kullanıcı adı + parola (kendi hesap sunucumuz).
///
/// Başarılı girişte anahtar cihaz Keystore'una yazılır, oturum çağırıcıya
/// devredilir. Kayıtta Nostr anahtarı üretilir ve parolayla (NIP-49) sarılıp
/// ev sunucusundaki hesap servisine yedeklenir. Mevcut yerel hesaplar
/// "Yerel anahtarla devam" ile eskisi gibi çalışmaya devam eder.
library;

import 'package:flutter/material.dart';

import '../../core/accounts/account_service.dart';
import '../../core/config/app_config.dart';
import '../../core/identity/key_storage.dart';
import '../../core/nostr/keys.dart';
import '../../ui/theme.dart';

/// Oturum açıldıktan sonra çağrılacak iş: oturumu başlat + ana ekrana geç.
typedef OnAuthenticated = Future<void> Function();

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onAuthenticated});

  final OnAuthenticated onAuthenticated;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _username.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _submit(bool register) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = _username.text.toLowerCase().trim();
      final pass = _password.text;
      final result = register
          ? await _register(name, pass)
          : await AccountService.instance.signIn(name, pass);
      await KeyStorage().savePrivateKey(result.keys);
      await widget.onAuthenticated();
    } on AccountException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = accountErrorText(e);
      });
    }
  }

  Future<({Account account, KeyPair keys})> _register(
      String name, String pass) async {
    if (_password.text != _password2.text) {
      throw const AccountException('Parolalar eşleşmiyor.');
    }
    return AccountService.instance.register(name, pass);
  }

  Future<void> _continueLocal() async {
    // Hesap açmadan kullanma yolu: yalnız yerel anahtar (cihazda kalır).
    final storage = KeyStorage();
    final keys = await storage.loadKeys() ?? KeyPair.generate();
    await storage.savePrivateKey(keys);
    await widget.onAuthenticated();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.coffee_rounded, size: 56, color: AppColors.accent),
                const SizedBox(height: 12),
                Text(
                  AppConfig.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Arkadaş çemberin — giriş yap ya da katıl',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                TabBar(
                  controller: _tabs,
                  tabs: const [Tab(text: 'Giriş'), Tab(text: 'Kayıt')],
                  labelColor: AppColors.accent,
                  unselectedLabelColor: AppColors.textMuted,
                  indicatorColor: AppColors.accent,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _username,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Kullanıcı adı',
                    hintText: 'ornek: hosthesap',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _tabs.index == 0 ? _submit(false) : null,
                  decoration: const InputDecoration(
                    labelText: 'Parola',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (_tabs.index == 1) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password2,
                    obscureText: true,
                    onSubmitted: (_) => _submit(true),
                    decoration: const InputDecoration(
                      labelText: 'Parola (tekrar)',
                      prefixIcon: Icon(Icons.lock_reset),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accentWash,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: AppColors.offline, width: 1),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.offline),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: _busy
                      ? null
                      : () => _submit(_tabs.index == 1),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(_tabs.index == 1
                          ? 'Hesap oluştur'
                          : 'Giriş yap'),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _continueLocal,
                  child: Text(
                    'Yerel anahtarla devam et',
                    style: TextStyle(
                        color: AppColors.textFaint, fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Kayıt olurken anahtarın senin parolanla şifrelenir; '
                  'sunucuda düz anahtar ya da parola saklanmaz.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
