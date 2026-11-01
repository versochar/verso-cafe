// Verso Cafe hesap servisi.
//
// Sıfır bağımlılık ilkesi: yalnızca dart:io + crypto. Ev bilgisayarında
// çalışır; Firebase/Google hesabı gerekmez. İçerik yine Nostr relay'inde,
// burada yalnızca kimlik, rol ve duyurular tutulur.
//
//   POST   /v1/register            → yeni hesap + oturum jetonu
//   POST   /v1/login               → giriş + oturum jetonu
//   POST   /v1/logout              → jetonu iptal et
//   GET    /v1/me                  → kendi hesabım
//   POST   /v1/password            → parola değiştir (anahtar yeniden sarılır)
//   GET    /v1/users               → tüm hesaplar (yalnız host)
//   PATCH  /v1/users/<id>/role     → rol ata (yalnız host)
//   POST   /v1/host/transfer       → hostluğu devret (yalnız host)
//   GET    /v1/announcements       → duyurular
//   POST   /v1/announcements       → duyuru yaz (host/mod)
//   DELETE /v1/announcements/<id>  → duyuru sil (host)
//   GET    /healthz                → canlılık
//
// Çalıştırma:  dart run bin/server.dart
// Ortam:      PORT=8090  ACCOUNT_DB=$HOME/sosyal-accounts/accounts.json
//
// Parola asla düz saklanmaz: PBKDF2-HMAC-SHA256 (kullanıcıya özel tuz).
// Nostr anahtarı da sunucuda düz durmaz: istemci onu NIP-49 ile parolayla
// şifreleyip `ncryptsec` olarak gönderir; sunucu yalnız o paketi saklar.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _pbkdf2Iterations = 60000;
const _tokenDays = 30;
const _maxBodyBytes = 64 * 1024;
const _maxLoginFailures = 8;
const _loginWindow = Duration(minutes: 10);

final _usernamePattern = RegExp(r'^[a-z0-9_.]{3,32}$');
final _pubkeyPattern = RegExp(r'^[0-9a-f]{64}$');

late final File dbFile;
late Map<String, dynamic> data;

/// username → son başarısız giriş zamanları (bellekte; sunucu yeniden
/// başlayınca sıfırlanır — kaba kuvvet denemesini yavaşlatmak için yeter).
final Map<String, List<DateTime>> _loginFailures = {};

Future<void> _saveQueue = Future<void>.value();

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8090;
  final path = Platform.environment['ACCOUNT_DB'] ??
      '${Platform.environment['HOME']}/sosyal-accounts/accounts.json';
  dbFile = File(path);
  await dbFile.parent.create(recursive: true);
  data = await _load();

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('hesap sunucusu :$port  veri=${dbFile.path}');

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('kapatılıyor…');
    await server.close(force: true);
    exit(0);
  });
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close(force: true);
    exit(0);
  });

  await for (final request in server) {
    unawaited(_handle(request));
  }
}

Future<Map<String, dynamic>> _load() async {
  if (!await dbFile.exists()) {
    return {'version': 1, 'users': <String, dynamic>{}, 'sessions': <String, dynamic>{}, 'announcements': <String, dynamic>{}};
  }
  try {
    final json = jsonDecode(await dbFile.readAsString());
    if (json is! Map<String, dynamic>) throw const FormatException('kök nesne değil');
    return {
      'version': 1,
      'users': (json['users'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      'sessions': (json['sessions'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
      'announcements': (json['announcements'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
    };
  } catch (e) {
    stderr.writeln('HATA: ${dbFile.path} okunamadı: $e');
    stderr.writeln('Veriyi kaybetmemek için bozuk dosya yedekleniyor.');
    final backup = '${dbFile.path}.bozuk-${DateTime.now().millisecondsSinceEpoch}';
    await dbFile.copy(backup);
    return {'version': 1, 'users': <String, dynamic>{}, 'sessions': <String, dynamic>{}, 'announcements': <String, dynamic>{}};
  }
}

Map<String, dynamic> get _users =>
    (data['users'] as Map).cast<String, dynamic>();
Map<String, dynamic> get _sessions =>
    (data['sessions'] as Map).cast<String, dynamic>();
Map<String, dynamic> get _announcements =>
    (data['announcements'] as Map).cast<String, dynamic>();

Future<void> _save() {
  final snapshot = const JsonEncoder.withIndent('  ').convert(data);
  _saveQueue = _saveQueue.then((_) async {
    final tmp = File('${dbFile.path}.tmp');
    await tmp.writeAsString(snapshot, flush: true);
    await tmp.rename(dbFile.path);
  });
  return _saveQueue;
}

Future<void> _handle(HttpRequest request) async {
  final started = DateTime.now();
  var status = 500;
  try {
    status = await _route(request);
  } catch (e, st) {
    stderr.writeln('hata: $e\n$st');
    try {
      await _json(request, 500, {'status': 'error', 'message': 'iç hata'});
    } catch (_) {}
  } finally {
    final ms = DateTime.now().difference(started).inMilliseconds;
    stdout.writeln(
        '${request.method} ${request.uri.path} → $status (${ms}ms)');
  }
}

Future<int> _route(HttpRequest request) async {
  final path = request.uri.path;
  final method = request.method;

  if (method == 'GET' && path == '/healthz') {
    await _json(request, 200, {'ok': true, 'users': _users.length});
    return 200;
  }
  if (method == 'POST' && path == '/v1/register') return _register(request);
  if (method == 'POST' && path == '/v1/login') return _login(request);
  if (method == 'POST' && path == '/v1/logout') return _logout(request);
  if (method == 'GET' && path == '/v1/me') return _me(request);
  if (method == 'POST' && path == '/v1/password') return _changePassword(request);
  if (method == 'GET' && path == '/v1/users') return _listUsers(request);
  if (method == 'POST' && path == '/v1/host/transfer') {
    return _transferHost(request);
  }
  if (method == 'GET' && path == '/v1/announcements') {
    return _listAnnouncements(request);
  }
  if (method == 'POST' && path == '/v1/announcements') {
    return _postAnnouncement(request);
  }
  final roleMatch = RegExp(r'^/v1/users/([^/]+)/role$').firstMatch(path);
  if (method == 'PATCH' && roleMatch != null) {
    return _setRole(request, roleMatch.group(1)!);
  }
  final annMatch = RegExp(r'^/v1/announcements/([^/]+)$').firstMatch(path);
  if (method == 'DELETE' && annMatch != null) {
    return _deleteAnnouncement(request, annMatch.group(1)!);
  }

  await _json(request, 404, {'status': 'error', 'message': 'yok'});
  return 404;
}

// ------------------------------------------------------------------ hesaplar

Future<int> _register(HttpRequest request) async {
  final body = await _readJson(request);
  if (body == null) return 400;
  final name = (body['username']?.toString() ?? '').toLowerCase().trim();
  final password = body['password']?.toString() ?? '';
  final pubkey = (body['pubkey']?.toString() ?? '').toLowerCase();
  final npub = body['npub']?.toString() ?? '';
  final ncryptsec = body['ncryptsec']?.toString() ?? '';

  final bad = _validateCredentials(name, password) ??
      _validateKeyMaterial(pubkey, npub, ncryptsec);
  if (bad != null) return _fail(request, 400, bad);

  if (_findByUsername(name) != null) {
    return _fail(request, 409, 'Bu kullanıcı adı zaten kayıtlı.');
  }

  final passwordHash = _hashPassword(password);
  // Yavaş PBKDF2 sırasında başka bir istek aynı adı almış olabilir.
  if (_findByUsername(name) != null) {
    return _fail(request, 409, 'Bu kullanıcı adı zaten kayıtlı.');
  }

  final isSeedHost = name == 'hosthesap' && !_hasHost();
  final id = _randomHex(16);
  final user = <String, dynamic>{
    'id': id,
    'username': name,
    'role': isSeedHost ? 'host' : 'user',
    'pubkey': pubkey,
    'npub': npub,
    'ncryptsec': ncryptsec,
    'password': passwordHash,
    'createdAt': DateTime.now().millisecondsSinceEpoch,
  };
  _users[id] = user;
  final token = _newSession(id);
  await _save();

  await _json(request, 201, {
    'token': token,
    'account': _publicAccount(user, includeSecret: true),
  });
  return 201;
}

Future<int> _login(HttpRequest request) async {
  final body = await _readJson(request);
  if (body == null) return 400;
  final name = (body['username']?.toString() ?? '').toLowerCase().trim();
  final password = body['password']?.toString() ?? '';

  final wait = _loginThrottle(name);
  if (wait != null) {
    request.response.headers.set('Retry-After', '${wait.inSeconds}');
    return _fail(request, 429,
        'Çok fazla başarısız deneme. ${wait.inMinutes + 1} dakika sonra tekrar dene.');
  }

  final user = _findByUsername(name);
  if (user == null || !_verifyPassword(password, user['password'])) {
    _recordFailure(name);
    return _fail(request, 401, 'Kullanıcı adı ya da parola hatalı.');
  }
  _loginFailures.remove(name);
  final token = _newSession(user['id'] as String);
  await _save();
  await _json(request, 200, {
    'token': token,
    'account': _publicAccount(user, includeSecret: true),
  });
  return 200;
}

Future<int> _logout(HttpRequest request) async {
  final session = _authenticate(request);
  if (session == null) return _unauthorized(request);
  _sessions.remove(session.tokenHash);
  await _save();
  await _json(request, 200, {'ok': true});
  return 200;
}

Future<int> _me(HttpRequest request) async {
  final session = _authenticate(request);
  if (session == null) return _unauthorized(request);
  final user = _users[session.userId];
  if (user == null) return _unauthorized(request);
  await _json(request, 200, {
    'account': _publicAccount(user, includeSecret: true),
  });
  return 200;
}

Future<int> _changePassword(HttpRequest request) async {
  final session = _authenticate(request);
  if (session == null) return _unauthorized(request);
  final user = _users[session.userId];
  if (user == null) return _unauthorized(request);

  final body = await _readJson(request);
  if (body == null) return 400;
  final oldPassword = body['oldPassword']?.toString() ?? '';
  final newPassword = body['newPassword']?.toString() ?? '';
  final ncryptsec = body['ncryptsec']?.toString() ?? '';

  if (!_verifyPassword(oldPassword, user['password'])) {
    return _fail(request, 403, 'Mevcut parola yanlış.');
  }
  if (newPassword.length < 6 || newPassword.length > 128) {
    return _fail(request, 400, 'Yeni parola 6-128 karakter olmalı.');
  }
  if (ncryptsec.length < 20) {
    return _fail(request, 400, 'Şifreli anahtar paketi eksik.');
  }

  user['password'] = _hashPassword(newPassword);
  user['ncryptsec'] = ncryptsec;
  // Diğer cihazlardaki oturumları kapat; bu cihaz devam eder.
  _sessions.removeWhere((_, s) =>
      s is Map && s['userId'] == user['id'] && s['tokenHash'] != session.tokenHash);
  await _save();
  await _json(request, 200, {'ok': true});
  return 200;
}

Future<int> _listUsers(HttpRequest request) async {
  final session = _authenticate(request);
  if (session == null) return _unauthorized(request);
  final me = _users[session.userId];
  if (me == null) return _unauthorized(request);
  if (me['role'] != 'host') {
    return _fail(request, 403, 'Bu listeyi yalnız host görebilir.');
  }
  final list = _users.values
      .whereType<Map<String, dynamic>>()
      .map((u) => _publicAccount(u))
      .toList()
    ..sort((a, b) =>
        (a['username'] as String).compareTo(b['username'] as String));
  await _json(request, 200, {'users': list});
  return 200;
}

Future<int> _setRole(HttpRequest request, String userId) async {
  final session = _authenticate(request);
  if (session == null) return _unauthorized(request);
  final me = _users[session.userId];
  if (me == null) return _unauthorized(request);
  if (me['role'] != 'host') {
    return _fail(request, 403, 'Rol atamayı yalnız host yapar.');
  }
  final target = _users[userId];
  if (target == null) return _fail(request, 404, 'Hesap bulunamadı.');
  if (target['role'] == 'host') {
    return _fail(request, 400, 'Hostun rolü devir dışında değiştirilemez.');
  }
  final body = await _readJson(request);
  if (body == null) return 400;
  final role = body['role']?.toString();
  if (role != 'mod' && role != 'user') {
    return _fail(request, 400, 'Rol yalnız "mod" ya da "user" olabilir.');
  }
  target['role'] = role;
  await _save();
  await _json(request, 200, {'account': _publicAccount(target)});
  return 200;
}

Future<int> _transferHost(HttpRequest request) async {
  final session = _authenticate(request);
  if (session == null) return _unauthorized(request);
  final me = _users[session.userId];
  if (me == null) return _unauthorized(request);
  if (me['role'] != 'host') {
    return _fail(request, 403, 'Hostluğu yalnız host devredebilir.');
  }
  final body = await _readJson(request);
  if (body == null) return 400;
  final targetId = body['targetId']?.toString() ?? '';
  final target = _users[targetId];
  if (target == null) return _fail(request, 404, 'Hedef hesap bulunamadı.');
  if (targetId == me['id']) {
    return _fail(request, 400, 'Hostluk zaten sende.');
  }
  target['role'] = 'host';
  me['role'] = 'user';
  await _save();
  await _json(request, 200, {'account': _publicAccount(me)});
  return 200;
}

// --------------------------------------------------------------- duyurular

Future<int> _listAnnouncements(HttpRequest request) async {
  final session = _authenticate(request);
  if (session == null) return _unauthorized(request);
  final limit = (int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 50)
      .clamp(1, 100);
  final list = _announcements.values
      .whereType<Map<String, dynamic>>()
      .toList()
    ..sort((a, b) =>
        (b['createdAt'] as num).compareTo(a['createdAt'] as num));
  await _json(request, 200, {'announcements': list.take(limit).toList()});
  return 200;
}

Future<int> _postAnnouncement(HttpRequest request) async {
  final session = _authenticate(request);
  if (session == null) return _unauthorized(request);
  final me = _users[session.userId];
  if (me == null) return _unauthorized(request);
  if (me['role'] != 'host' && me['role'] != 'mod') {
    return _fail(request, 403, 'Duyuru yazma yetkin yok.');
  }
  final body = await _readJson(request);
  if (body == null) return 400;
  final title = (body['title']?.toString() ?? '').trim();
  final text = (body['body']?.toString() ?? '').trim();
  if (title.isEmpty && text.isEmpty) {
    return _fail(request, 400, 'Boş duyuru gönderilmez.');
  }
  if (title.length > 120 || text.length > 4000) {
    return _fail(request, 400, 'Duyuru çok uzun.');
  }
  final id = _randomHex(12);
  final item = <String, dynamic>{
    'id': id,
    'title': title.isEmpty ? 'Duyuru' : title,
    'body': text,
    'authorId': me['id'],
    'authorName': me['username'],
    'createdAt': DateTime.now().millisecondsSinceEpoch,
  };
  _announcements[id] = item;
  await _save();
  await _json(request, 201, {'announcement': item});
  return 201;
}

Future<int> _deleteAnnouncement(HttpRequest request, String id) async {
  final session = _authenticate(request);
  if (session == null) return _unauthorized(request);
  final me = _users[session.userId];
  if (me == null) return _unauthorized(request);
  if (me['role'] != 'host') {
    return _fail(request, 403, 'Duyuruyu yalnız host siler.');
  }
  if (_announcements.remove(id) == null) {
    return _fail(request, 404, 'Duyuru bulunamadı.');
  }
  await _save();
  await _json(request, 200, {'ok': true});
  return 200;
}

// ---------------------------------------------------------------- yardımcılar

class _Session {
  const _Session(this.tokenHash, this.userId);
  final String tokenHash;
  final String userId;
}

String _newSession(String userId) {
  final token = _randomHex(32);
  final now = DateTime.now();
  _sessions[_sha256Hex(token)] = <String, dynamic>{
    'tokenHash': _sha256Hex(token),
    'userId': userId,
    'createdAt': now.millisecondsSinceEpoch,
    'expiresAt':
        now.add(const Duration(days: _tokenDays)).millisecondsSinceEpoch,
  };
  return token;
}

_Session? _authenticate(HttpRequest request) {
  final header = request.headers.value(HttpHeaders.authorizationHeader);
  if (header == null || !header.startsWith('Bearer ')) return null;
  final token = header.substring(7).trim();
  if (token.length < 20) return null;
  final hash = _sha256Hex(token);
  final raw = _sessions[hash];
  if (raw is! Map) return null;
  final expiresAt = (raw['expiresAt'] as num?)?.toInt() ?? 0;
  if (expiresAt < DateTime.now().millisecondsSinceEpoch) {
    _sessions.remove(hash);
    return null;
  }
  return _Session(hash, raw['userId']?.toString() ?? '');
}

Map<String, dynamic>? _findByUsername(String name) {
  for (final user in _users.values) {
    if (user is Map && user['username'] == name) {
      return user.cast<String, dynamic>();
    }
  }
  return null;
}

bool _hasHost() =>
    _users.values.any((u) => u is Map && u['role'] == 'host');

String? _validateCredentials(String name, String password) {
  if (!_usernamePattern.hasMatch(name)) {
    return 'Kullanıcı adı 3-32 karakter olmalı: küçük harf, rakam, _ veya .';
  }
  if (password.length < 6) return 'Parola en az 6 karakter olmalı.';
  if (password.length > 128) return 'Parola en fazla 128 karakter olabilir.';
  return null;
}

String? _validateKeyMaterial(String pubkey, String npub, String ncryptsec) {
  if (!_pubkeyPattern.hasMatch(pubkey)) return 'Geçersiz açık anahtar.';
  if (!npub.startsWith('npub1') || npub.length < 20) {
    return 'Geçersiz npub.';
  }
  if (!ncryptsec.startsWith('ncryptsec1') || ncryptsec.length < 40) {
    return 'Geçersiz şifreli anahtar.';
  }
  return null;
}

Map<String, dynamic> _publicAccount(Map<String, dynamic> user,
    {bool includeSecret = false}) {
  return <String, dynamic>{
    'id': user['id'],
    'username': user['username'],
    'role': user['role'],
    'pubkey': user['pubkey'],
    'npub': user['npub'],
    'createdAt': user['createdAt'],
    if (includeSecret) 'ncryptsec': user['ncryptsec'],
  };
}

Future<Map<String, dynamic>?> _readJson(HttpRequest request) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request) {
    builder.add(chunk);
    if (builder.length > _maxBodyBytes) {
      await _fail(request, 413, 'Gövde çok büyük.');
      return null;
    }
  }
  try {
    final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
    if (decoded is! Map<String, dynamic>) {
      await _fail(request, 400, 'JSON nesne bekleniyor.');
      return null;
    }
    return decoded;
  } catch (_) {
    await _fail(request, 400, 'JSON çözülemedi.');
    return null;
  }
}

Future<int> _fail(HttpRequest request, int code, String message) async {
  await _json(request, code, {'status': 'error', 'message': message});
  return code;
}

Future<int> _unauthorized(HttpRequest request) =>
    _fail(request, 401, 'Oturum geçersiz ya da süresi dolmuş.');

Future<void> _json(
    HttpRequest request, int code, Map<String, Object?> body) async {
  request.response
    ..statusCode = code
    ..headers.contentType = ContentType.json
    ..headers.set('Cache-Control', 'no-store');
  request.response.write(jsonEncode(body));
  await request.response.close();
}

// ------------------------------------------------------------ kriptografi

String _randomHex(int bytes) {
  final rnd = Random.secure();
  final out = StringBuffer();
  for (var i = 0; i < bytes; i++) {
    out.write(rnd.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

String _sha256Hex(String value) =>
    sha256.convert(utf8.encode(value)).toString();

Map<String, dynamic> _hashPassword(String password) {
  final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)));
  final derived = _pbkdf2(
    utf8.encode(password),
    salt,
    _pbkdf2Iterations,
    32,
  );
  return {
    'algo': 'pbkdf2-sha256',
    'iterations': _pbkdf2Iterations,
    'salt': base64.encode(salt),
    'hash': base64.encode(derived),
  };
}

bool _verifyPassword(String password, Object? stored) {
  if (stored is! Map) return false;
  final salt = base64.decode(stored['salt']?.toString() ?? '');
  final expected = base64.decode(stored['hash']?.toString() ?? '');
  final iterations = (stored['iterations'] as num?)?.toInt() ??
      _pbkdf2Iterations;
  final actual = _pbkdf2(utf8.encode(password), salt, iterations, expected.length);
  return _constantTimeEquals(actual, expected);
}

/// PBKDF2-HMAC-SHA256 (RFC 8018). `crypto` paketinde hazırı yok.
List<int> _pbkdf2(
    List<int> password, List<int> salt, int iterations, int length) {
  final hmac = Hmac(sha256, password);
  final out = <int>[];
  var block = 1;
  while (out.length < length) {
    final blockIndex = <int>[
      (block >> 24) & 0xff,
      (block >> 16) & 0xff,
      (block >> 8) & 0xff,
      block & 0xff,
    ];
    var u = hmac.convert([...salt, ...blockIndex]).bytes;
    final t = List<int>.from(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.addAll(t);
    block++;
  }
  return out.sublist(0, length);
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

// ------------------------------------------------------------- giriş sınırı

Duration? _loginThrottle(String username) {
  final list = _loginFailures[username];
  if (list == null) return null;
  final now = DateTime.now();
  list.removeWhere((t) => now.difference(t) > _loginWindow);
  if (list.length < _maxLoginFailures) return null;
  final oldest = list.first;
  final remaining = _loginWindow - now.difference(oldest);
  return remaining.isNegative ? null : remaining;
}

void _recordFailure(String username) {
  final now = DateTime.now();
  final list = _loginFailures.putIfAbsent(username, () => []);
  list.removeWhere((t) => now.difference(t) > _loginWindow);
  list.add(now);
  // Sınırsız büyümeyi engelle: yalnız son pencereyi tut.
  if (list.length > _maxLoginFailures) list.removeAt(0);
}
