/// Giriş / kayıt ekranı — kullanıcı adı + parola (kendi hesap sunucumuz).
///
/// Başarılı girişte anahtar cihaz Keystore'una yazılır, oturum çağırıcıya
/// devredilir. Kayıtta Nostr anahtarı üretilir ve parolayla (NIP-49) sarılıp
/// ev sunucusundaki hesap servisine yedeklenir. Mevcut yerel hesaplar
/// "Yerel anahtarla devam" ile eskisi gibi çalışmaya devam eder.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _acceptTerms = false;
  bool _isRegister = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _password2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_isRegister && !_acceptTerms) {
      setState(() => _error = 'Gizlilik Sözleşmesi ve Kullanım Şartları\'nı kabul etmelisiniz.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = _username.text.toLowerCase().trim();
      final pass = _password.text;
      final result = _isRegister
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
    final storage = KeyStorage();
    final keys = await storage.loadKeys() ?? KeyPair.generate();
    await storage.savePrivateKey(keys);
    await widget.onAuthenticated();
  }

  Future<void> _openTerms() async {
    const url = 'https://github.com/versochar/verso-cafe/blob/main/docs/kurulum.md#gizlilik-ve-kullan%C4%B1m-%C5%9Fartlar%C4%B1';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
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
              // Giriş / Kayıt geçişi: TabBar yerine ToggleButtons (çizgi yok)
              ToggleButtons(
                isSelected: [_isRegister == false, _isRegister == true],
                onPressed: (i) => setState(() => _isRegister = i == 1),
                borderColor: AppColors.line,
                selectedBorderColor: AppColors.accent,
                fillColor: AppColors.surface,
                selectedColor: AppColors.accent,
                color: AppColors.textMuted,
                constraints: const BoxConstraints.tightFor(height: 40),
                children: const [
                  SizedBox(width: 80, child: Center(child: Text('Giriş'))),
                  SizedBox(width: 80, child: Center(child: Text('Kayıt'))),
                ],
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
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.line, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.line, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.lineStrong, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Parola',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.line, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.line, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.lineStrong, width: 1.4),
                  ),
                ),
              ),
              if (_isRegister) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _password2,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Parola (tekrar)',
                    prefixIcon: Icon(Icons.lock_reset),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.line, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.line, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.lineStrong, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _acceptTerms,
                      onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                      activeColor: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: _openTerms,
                        child: Text.rich(
                          TextSpan(
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textMuted,
                            ),
                            children: [
                              const TextSpan(text: 'Gizlilik Sözleşmesi ve '),
                              TextSpan(
                                text: 'Kullanım Şartları',
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              const TextSpan(text: 'nı kabul ediyorum.'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(color: AppColors.line, width: 1),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.offline),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                  ),
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(_isRegister ? 'Hesap oluştur' : 'Giriş yap'),
                ),
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
    );
  }
}
