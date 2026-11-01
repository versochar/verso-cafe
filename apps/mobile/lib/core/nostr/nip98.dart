import 'dart:convert';

import 'event.dart';
import 'keys.dart';

/// NIP-98: `Authorization: Nostr <base64(kind:27235 olayı)>` başlık üretimi.
///
/// Medya sunucusu bu başlıkla yükleyenin kimliğini (pubkey) doğrular; push
/// sunucusu gerektiren "hesap/şifre" yerine imzalı olay kullanır.
String buildNip98AuthHeader({
  required String url,
  required String method,
  required KeyPair keys,
}) {
  final createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final innerTags = [
    ['t', 'upload'],
    ['method', method],
    ['u', url],
  ];
  final inner = jsonEncode({
    'content': '',
    'kind': 27235,
    'created_at': createdAt,
    'tags': innerTags,
  });
  final event = NostrEvent.create(
    kind: 27235,
    content: base64.encode(utf8.encode(inner)),
    keys: keys,
    tags: innerTags,
    createdAt: createdAt,
  );
  return 'Nostr ${base64.encode(utf8.encode(jsonEncode(event.toJson())))}';
}
