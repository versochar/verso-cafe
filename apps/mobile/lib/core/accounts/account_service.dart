/// Kullanıcı hesapları — kendi hesap sunucumuzun HTTP istemcisi.
///
/// Model: giriş kimliği kullanıcı adı + parola; hesap servisi ev
/// bilgisayarında çalışır (Firebase/Google gerekmez). Kayıtta Nostr anahtar
/// çifti üretilir, **NIP-49 ile parolayla şifrelenir** ve sunucuya yalnız
/// `ncryptsec` paketi gönderilir. Sunucu parolayı PBKDF2 ile, anahtarı ise
/// yalnız şifreli hâlde saklar.
///
/// Roller: `host` (tek yetkili; devredilebilir), `mod` (duyuru yazar),
/// `user` (normal). Tohum host `hosthesap` adıyla doğar; sonraki roller
/// yalnız mevcut host tarafından atanır (ADR-015).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import '../nostr/keys.dart';
import '../nostr/nip49.dart';

enum AccountRole { host, mod, user, anon;

  static AccountRole parse(Object? v) => switch (v?.toString()) {
        'host' => AccountRole.host,
        'mod' => AccountRole.mod,
        _ => AccountRole.user,
      };

  String get labelTR => switch (this) {
        AccountRole.host => 'Host',
        AccountRole.mod => 'Mod',
        AccountRole.user => 'Üye',
        AccountRole.anon => 'Misafir',
      };
}

class Account {
  const Account({
    required this.uid,
    required this.username,
    required this.role,
    required this.pubkey,
  });

  final String uid;
  final String username;
  final AccountRole role;
  final String pubkey;

  bool get isHost => role == AccountRole.host;
  bool get canAnnounce => role == AccountRole.host || role == AccountRole.mod;

  static Account fromJson(Map<String, dynamic> data) => Account(
        uid: data['id']?.toString() ?? data['uid']?.toString() ?? '',
        username: data['username']?.toString() ?? '',
        role: AccountRole.parse(data['role']),
        pubkey: data['pubkey']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': uid,
        'username': username,
        'role': role.name,
        'pubkey': pubkey,
      };
}

class AccountException implements Exception {
  const AccountException(this.message, {this.statusCode});

  final String message;

  /// Sunucunun HTTP durumu (401 = oturum düştü); ağ hatasında null.
  final int? statusCode;

  @override
  String toString() => message;
}

final RegExp usernamePattern = RegExp(r'^[a-z0-9_.]{3,32}$');

class AccountService {
  AccountService._();
  static final AccountService instance = AccountService._();

  static const _tokenKey = 'account.token.v1';
  static const _accountKey = 'account.me.v1';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  String? _token;
  String? _ncryptsec;
  Account? _account;

  Account? get account => _account;
  bool get signedIn => _token != null;

  /// Yeni hesap: anahtar üret + NIP-49 ile sar + sunucuya kaydet.
  Future<({Account account, KeyPair keys})> register(
      String username, String password) async {
    final name = username.toLowerCase().trim();
    if (!usernamePattern.hasMatch(name)) {
      throw const AccountException(
          'Kullanıcı adı 3-32 karakter olmalı: küçük harf, rakam, _ veya .');
    }
    if (password.length < 6) {
      throw const AccountException('Parola en az 6 karakter olmalı.');
    }

    final keys = KeyPair.generate();
    final ncryptsec = await Nip49.encrypt(keys.privateKeyHex, password);

    final json = await _request('POST', '/v1/register', body: {
      'username': name,
      'password': password,
      'pubkey': keys.publicKeyHex,
      'npub': keys.npub,
      'ncryptsec': ncryptsec,
    });
    final account = Account.fromJson(_accountJson(json));
    await _persist(account, json['token']?.toString(), ncryptsec: ncryptsec);
    return (account: account, keys: keys);
  }

  /// Giriş: parolayla şifreli anahtarı çözer. Hata mesajları kullanıcıya
  /// gösterilir.
  Future<({Account account, KeyPair keys})> signIn(
      String username, String password) async {
    final name = username.toLowerCase().trim();
    final json = await _request('POST', '/v1/login', body: {
      'username': name,
      'password': password,
    });
    final data = _accountJson(json);
    final ncryptsec = data['ncryptsec']?.toString();
    if (ncryptsec == null || ncryptsec.isEmpty) {
      throw const AccountException(
          'Sunucu anahtar paketini göndermedi — hesap bozuk olabilir.');
    }
    final KeyPair keys;
    try {
      final hex = await Nip49.decrypt(ncryptsec, password);
      keys = KeyPair.fromPrivateHex(hex);
    } catch (_) {
      throw const AccountException(
          'Anahtar çözülemedi — hesap başka bir parolayla mı şifrelendi?');
    }
    final account = Account.fromJson(data);
    await _persist(account, json['token']?.toString(), ncryptsec: ncryptsec);
    return (account: account, keys: keys);
  }

  Future<void> signOut() async {
    if (_token != null) {
      try {
        await _request('POST', '/v1/logout', timeout: const Duration(seconds: 5));
      } catch (_) {
        // Sunucu kapalı olsa da yerel oturum kapanır.
      }
    }
    await _clear();
  }

  /// Açılıştaki oturumu yükler.
  ///
  /// Önce cihazdaki önbellek kullanılır; ardından `/v1/me` ile tazelenir.
  /// Sunucu kapalıysa/çevrimdışıysa önbellek geçerli kalır — uygulama açılır.
  /// Jeton geçersizse (401) oturum temizlenir.
  Future<Account?> restore() async {
    _token = await _read(_tokenKey);
    _ncryptsec = await _read(_secretKey);
    final raw = await _read(_accountKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _account = Account.fromJson(
            (jsonDecode(raw) as Map).cast<String, dynamic>());
      } catch (_) {
        // Bozuk önbellek: sunucudan tazelenecek.
      }
    }
    if (_token == null) {
      _account = null;
      return null;
    }
    try {
      final json = await _request('GET', '/v1/me',
          timeout: const Duration(seconds: 6));
      final data = _accountJson(json);
      final account = Account.fromJson(data);
      _account = account;
      final secret = data['ncryptsec']?.toString();
      if (secret != null && secret.isNotEmpty) _ncryptsec = secret;
      await _cacheAccount(account, _ncryptsec);
      return account;
    } on AccountException catch (e) {
      if (e.statusCode == 401) {
        await _clear();
        return null;
      }
      return _account;
    } catch (_) {
      return _account;
    }
  }

  // ------------------------------------------------------ yönetim (host)

  /// Host: tüm hesaplar (rol ekranı listesi).
  Future<List<Account>> listUsers() async {
    final json = await _request('GET', '/v1/users');
    final raw = json['users'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Account.fromJson(m.cast<String, dynamic>()))
        .toList()
      ..sort((a, b) => a.username.compareTo(b.username));
  }

  /// Host: rol atar (`mod` / `user`). Hostluk devri ayrı uçtadır.
  Future<void> setRole(String uid, AccountRole role) async {
    await _request('PATCH', '/v1/users/$uid/role',
        body: {'role': role.name});
  }

  /// Hostluğu devret: hedef host olur, sen normal üyeye düşersin.
  Future<void> transferHost(String targetUid) async {
    final json = await _request('POST', '/v1/host/transfer',
        body: {'targetId': targetUid});
    final data = _accountJson(json);
    final account = Account.fromJson(data);
    _account = account;
    await _cacheAccount(account, _ncryptsec);
  }

  /// Parola değişimi: anahtarı yeni parolayla yeniden sar.
  Future<void> changePassword(String oldPassword, String newPassword) async {
    if (_token == null || _account == null) {
      throw const AccountException('Oturum açık değil.');
    }
    if (newPassword.length < 6) {
      throw const AccountException('Yeni parola en az 6 karakter olmalı.');
    }
    var secret = _ncryptsec;
    if (secret == null || secret.isEmpty) {
      final json = await _request('GET', '/v1/me');
      secret = _accountJson(json)['ncryptsec']?.toString();
    }
    if (secret == null || secret.isEmpty) {
      throw const AccountException('Anahtar paketi bulunamadı.');
    }
    String hex;
    try {
      hex = await Nip49.decrypt(secret, oldPassword);
    } catch (_) {
      throw const AccountException('Mevcut parola yanlış.');
    }
    final fresh = await Nip49.encrypt(hex, newPassword);
    await _request('POST', '/v1/password', body: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
      'ncryptsec': fresh,
    });
    _ncryptsec = fresh;
    await _cacheAccount(_account!, fresh);
  }

  // --------------------------------------------------------------- duyurular

  Future<List<Announcement>> fetchAnnouncements({int limit = 50}) async {
    final json =
        await _request('GET', '/v1/announcements?limit=${limit.clamp(1, 100)}');
    final raw = json['announcements'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Announcement.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  Future<void> postAnnouncement(
      {required String title, required String body}) async {
    await _request('POST', '/v1/announcements', body: {
      'title': title,
      'body': body,
    });
  }

  Future<void> deleteAnnouncement(String id) async {
    await _request('DELETE', '/v1/announcements/$id');
  }

  // ---------------------------------------------------------------- HTTP

  static const _secretKey = 'account.ncryptsec.v1';

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final base = AppConfig.accountUrl.replaceFirst(RegExp(r'/+$'), '');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, Uri.parse('$base$path'));
      request.headers.contentType = ContentType.json;
      if (_token != null) {
        request.headers
            .set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        request.headers.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {
        // Boş/JSON olmayan gövde: durum koduna göre karar verilir.
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json ?? const {};
      }
      throw AccountException(
        json?['message']?.toString() ??
            'Sunucu hatası (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    } on AccountException {
      rethrow;
    } on SocketException {
      throw const AccountException(
          'Hesap sunucusuna ulaşılamadı — sunucu açık mı, internet var mı?');
    } on TimeoutException {
      throw const AccountException(
          'Hesap sunucusu yanıt vermedi — bağlantını kontrol et.');
    } on HttpException {
      throw const AccountException('Hesap sunucusuyla bağlantı kurulamadı.');
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic> _accountJson(Map<String, dynamic> json) {
    final raw = json['account'];
    if (raw is Map) return raw.cast<String, dynamic>();
    throw const AccountException('Sunucu hesap bilgisini göndermedi.');
  }

  Future<void> _persist(Account account, String? token,
      {String? ncryptsec}) async {
    if (token == null || token.isEmpty) {
      throw const AccountException('Sunucu oturum jetonu göndermedi.');
    }
    _token = token;
    _account = account;
    if (ncryptsec != null) _ncryptsec = ncryptsec;
    try {
      await _storage.write(key: _tokenKey, value: token);
      if (_ncryptsec != null) {
        await _storage.write(key: _secretKey, value: _ncryptsec);
      }
      await _cacheAccount(account, _ncryptsec);
    } catch (_) {
      // Keystore yazılamazsa oturum bu açılışta yine geçerli.
    }
  }

  Future<void> _cacheAccount(Account account, String? secret) async {
    try {
      await _storage.write(
          key: _accountKey, value: jsonEncode(account.toJson()));
      if (secret != null) {
        await _storage.write(key: _secretKey, value: secret);
      }
    } catch (_) {
      // Önbellek yazılamazsa da oturum bellekte sürer.
    }
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clear() async {
    _token = null;
    _ncryptsec = null;
    _account = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _secretKey);
      await _storage.delete(key: _accountKey);
    } catch (_) {
      // Keystore silinemezse bir sonraki açılışta restore() temizler.
    }
  }
}

/// Giriş/kayıt hatalarını kullanıcıya anlaşılır metne çevirir.
String accountErrorText(Object error) {
  if (error is AccountException) return error.message;
  if (error is SocketException || error is TimeoutException) {
    return 'Hesap sunucusuna ulaşılamadı — sunucu açık mı, internet var mı?';
  }
  return 'Beklenmeyen hata: $error';
}

// ------------------------------------------------------------------ duyurular

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.authorName,
    required this.authorUid,
    required this.createdAtMs,
  });

  final String id;
  final String title;
  final String body;
  final String authorName;
  final String authorUid;
  final int createdAtMs;

  static Announcement fromJson(Map<String, dynamic> data) {
    int ms;
    final raw = data['createdAt'];
    if (raw is String) {
      ms = DateTime.tryParse(raw)?.millisecondsSinceEpoch ?? 0;
    } else {
      ms = (raw as num?)?.toInt() ?? 0;
    }
    return Announcement(
      id: data['id']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      body: data['body']?.toString() ?? '',
      authorName: data['authorName']?.toString() ?? '',
      authorUid: data['authorId']?.toString() ?? data['authorUid']?.toString() ?? '',
      createdAtMs: ms,
    );
  }

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
}

class AnnouncementService {
  AnnouncementService._();
  static final AnnouncementService instance = AnnouncementService._();

  /// Canlıya yakın akış: ilk istek hemen, sonra 15 saniyede bir tazelenir.
  ///
  /// WebSocket dinleyicisi yerine basit yoklama kullanılır; arkadaş çemberi
  /// için yeterli, ek bağımlılık gerektirmez. Hata durumunda boş liste
  /// yayınlanır (şerit görünmez, uygulama çalışmaya devam eder).
  Stream<List<Announcement>> watch({int limit = 50}) {
    late StreamController<List<Announcement>> controller;
    Timer? timer;
    var closed = false;

    Future<void> tick() async {
      if (closed) return;
      try {
        final items =
            await AccountService.instance.fetchAnnouncements(limit: limit);
        if (!closed) controller.add(items);
      } catch (_) {
        if (!closed) controller.add(const []);
      }
    }

    controller = StreamController<List<Announcement>>(
      onListen: () {
        unawaited(tick());
        timer = Timer.periodic(const Duration(seconds: 15), (_) => tick());
      },
      onCancel: () {
        closed = true;
        timer?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> post({required String title, required String body}) async {
    final me = AccountService.instance.account;
    if (me == null || !me.canAnnounce) {
      throw const AccountException('Duyuru yazma yetkin yok.');
    }
    final t = title.trim();
    final b = body.trim();
    if (t.isEmpty && b.isEmpty) {
      throw const AccountException('Boş duyuru gönderilmez.');
    }
    await AccountService.instance.postAnnouncement(title: t, body: b);
  }

  Future<void> delete(String id) =>
      AccountService.instance.deleteAnnouncement(id);
}
