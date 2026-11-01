// Sosyal medya sunucusu.
//
// Sıfır bağımlılık ilkesi: yalnızca dart:io + bip340 + crypto.
//   POST /upload   → NIP-98 (kind:27235) imzalı izinle ham görsü kaydedir
//   GET  /m/<ad>   → içeriği sha256 adı ile servis eder (immutable cache)
//   GET  /healthz  → canlılık kontrolü
//
// Çalıştırma:  dart run bin/server.dart
// Ortam:      PORT=8080  MEDIALIB=$HOME/sosyal-media  MAX_BYTES=12582912
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bip340/bip340.dart' as bip340;
import 'package:crypto/crypto.dart';

const _kindAuth = 27235; // NIP-98
const _maxAgeSeconds = 300;

const _extensions = <String, String>{
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/webp': 'webp',
};

final _filePattern = RegExp(r'^[0-9a-f]{64}\.(jpg|png|gif|webp)$');

late final Directory mediaDir;
late final int maxBytes;

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final dir = Platform.environment['MEDIALIB'] ??
      '${Platform.environment['HOME']}/sosyal-media';
  mediaDir = await Directory(dir).create(recursive: true);
  maxBytes = int.tryParse(Platform.environment['MAX_BYTES'] ?? '') ??
      12 * 1024 * 1024;

  final server = await HttpServer.bind(
    InternetAddress.anyIPv4,
    port,
    shared: false,
  );
  stdout.writeln(
    'medya sunucusu :$port  kitaplık=${mediaDir.path}  tavan=$maxBytes bayt',
  );

  await for (final request in server) {
    unawaited(_handle(request));
  }
}

Future<void> _handle(HttpRequest request) async {
  try {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/healthz') {
      return _json(request, 200, {'ok': true});
    }
    if (request.method == 'GET' && path.startsWith('/m/')) {
      return _serve(request, path.substring(3));
    }
    if (request.method == 'POST' && path == '/upload') {
      return _upload(request);
    }
    _json(request, 404, {'status': 'error', 'message': 'yok'});
  } catch (e, st) {
    stderr.writeln('hata: $e\n$st');
    try {
      _json(request, 500, {'status': 'error', 'message': 'iç hata'});
    } catch (_) {}
  }
}

void _json(HttpRequest request, int code, Map<String, Object> body) {
  request.response
    ..statusCode = code
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  request.response.close();
}

Future<void> _serve(HttpRequest request, String name) async {
  if (!_filePattern.hasMatch(name)) {
    return _json(request, 400, {'status': 'error', 'message': 'ad geçersiz'});
  }
  final file = File('${mediaDir.path}/$name');
  if (!file.existsSync()) {
    return _json(request, 404, {'status': 'error', 'message': 'bulunamadı'});
  }
  final ext = name.split('.').last;
  final mime = _extensions.entries.firstWhere((e) => e.value == ext).key;
  request.response
    ..headers.contentType = ContentType.parse(mime)
    ..headers.set('Cache-Control', 'public, max-age=31536000, immutable')
    ..headers.set('Access-Control-Allow-Origin', '*');
  await request.response.addStream(file.openRead());
  await request.response.close();
}

Future<void> _upload(HttpRequest request) async {
  // 1) NIP-98 yetki başlığı.
  final auth = request.headers.value(HttpHeaders.authorizationHeader);
  if (auth == null || !auth.startsWith('Nostr ')) {
    return _json(request, 401, {'status': 'error', 'message': 'Nostr başlığı yok'});
  }
  Map<String, Object?> authEvent;
  try {
    authEvent = jsonDecode(utf8.decode(base64.decode(auth.substring(6))));
  } catch (_) {
    return _json(request, 400, {'status': 'error', 'message': 'başlık çözülemedi'});
  }
  final why = _verifyAuth(authEvent, request);
  if (why != null) {
    return _json(request, 403, {'status': 'error', 'message': why});
  }

  // 2) Gövde: yalnızca bilinen görsel türleri, tavanlı.
  final mime = request.headers.contentType?.mimeType ?? '';
  final ext = _extensions[mime];
  if (ext == null) {
    return _json(request, 415, {'status': 'error', 'message': 'desteklenmeyen tür: $mime'});
  }
  final declared = request.headers.contentLength;
  if (declared > maxBytes) {
    return _json(request, 413, {'status': 'error', 'message': 'çok büyük'});
  }

  // Gövde RAM'de toplanır (tavan 12 MB) — streaming sha256'a gerek yok.
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request) {
    builder.add(chunk);
    if (builder.length > maxBytes) {
      return _json(request, 413, {'status': 'error', 'message': 'çok büyük'});
    }
  }
  final bytes = builder.takeBytes();
  if (bytes.isEmpty) {
    return _json(request, 400, {'status': 'error', 'message': 'boş gövde'});
  }
  final hash = sha256.convert(bytes).toString();

  // 3) Ad = sha256 + uzantı; içerik adreslendiği için çakışma = aynı dosya.
  final name = '$hash.$ext';
  final file = File('${mediaDir.path}/$name');
  if (!file.existsSync()) {
    final tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  final host = request.headers.value('host') ?? 'localhost';
  _json(request, 200, {
    'status': 'success',
    'name': name,
    'url': 'http://$host/m/$name',
    'sha256': hash,
    'size': bytes.length,
  });
  stdout.writeln(
    'yüklendi: $name (${bytes.length}B) kim=${authEvent['pubkey']}',
  );
}

/// NIP-98 auth olayını doğrular; hata varsa nedenini döner (yoksa null).
String? _verifyAuth(Map<String, Object?> event, HttpRequest request) {
  try {
    final pubkey = event['pubkey'] as String;
    final createdAt = (event['created_at'] as num).toInt();
    final kind = (event['kind'] as num).toInt();
    final id = event['id'] as String;
    final sig = event['sig'] as String;
    final tags = (event['tags'] as List)
        .map((t) => (t as List).map((e) => e.toString()).toList())
        .toList();
    final content = event['content'] as String;

    if (kind != _kindAuth) return 'kind 27235 olmalı';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if ((now - createdAt).abs() > _maxAgeSeconds) return 'zaman penceresi dışı';

    // Id = sha256([0, pubkey, created_at, kind, tags, content])
    final serialized =
        jsonEncode([0, pubkey, createdAt, kind, tags, content]);
    if (sha256.convert(utf8.encode(serialized)).toString() != id) {
      return 'id tutarsız';
    }
    if (!bip340.verify(pubkey, id, sig)) return 'imza geçersiz';

    String? tagValue(String key) {
      for (final t in tags) {
        if (t.length >= 2 && t[0] == key) return t[1];
      }
      return null;
    }

    if (tagValue('t') != 'upload') return 't=upload eksik';
    if ((tagValue('method') ?? 'POST').toUpperCase() != 'POST') {
      return 'method POST olmalı';
    }
    final u = tagValue('u') ?? '';
    if (!u.endsWith('/upload')) return 'u yükleme adresini göstermiyor';

    // İç bildirim (content) dış olayla tutarlı olmalı (NIP-98).
    final inner = jsonDecode(utf8.decode(base64.decode(content)));
    if (inner is! Map) return 'iç bildirim bozuk';
    if ((inner['kind'] as num).toInt() != _kindAuth) return 'iç kind yanlış';
    if ((inner['created_at'] as num).toInt() != createdAt) return 'iç zaman yanlış';
    final innerTags = (inner['tags'] as List)
        .map((t) => (t as List).map((e) => e.toString()).toList())
        .toList();
    for (final want in [
      ['t', 'upload'],
      ['u', u],
    ]) {
      if (!innerTags.any((t) => t.length >= 2 && t[0] == want[0] && t[1] == want[1])) {
        return 'iç etiket eksik: ${want.join('=')}';
      }
    }
    return null;
  } catch (_) {
    return 'auth olayı çözülemedi';
  }
}
