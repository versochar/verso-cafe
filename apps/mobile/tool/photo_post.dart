// Uçtan uca fotoğraf gönderisi testi: medya sunucusuna NIP-98 imzalı yükleme
// yapar, imeta etiketli kind:1 gönderisini relay'e yayar.
//
// Kullanım: dart run tool/photo_post.dart <resim-dosyası> [açıklama]
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:sosyal/core/media/media_uploader.dart';
import 'package:sosyal/core/nostr/event.dart';
import 'package:sosyal/core/nostr/keys.dart';
import 'package:sosyal/core/nostr/relay_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || !File(args[0]).existsSync()) {
    stderr.writeln('kullanım: dart run tool/photo_post.dart <resim> [açıklama]');
    exit(2);
  }
  final mediaBase =
      Platform.environment['MEDIA_URL'] ?? 'http://192.168.1.109:8080';
  final relayUrl =
      Platform.environment['RELAY_URL'] ?? 'ws://192.168.1.109:7777';
  final caption = args.length > 1 ? args[1] : 'Fotoğraf denemesi 📷';

  final b = KeyPair.fromPrivateHex(
      '0000000000000000000000000000000000000000000000000000000000000002');
  print('B pub: ${b.publicKeyHex}');

  final bytes = await File(args[0]).readAsBytes();
  final mime = bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50
      ? 'image/png'
      : 'image/jpeg';
  print('yükleniyor: ${args[0]} (${bytes.length}B, $mime)');
  final ref = await MediaUploader(mediaBase).upload(
    bytes: bytes,
    mime: mime,
    keys: b,
  );
  print('yüklendi: ${ref.url}  sha=${ref.sha256.substring(0, 12)}…');

  final client = RelayClient(relayUrl, reconnect: false);
  await client.connect();
  final note = NostrEvent.create(
    kind: EventKind.note,
    content: caption,
    keys: b,
    tags: [ref.toImetaTag()],
  );
  final ok = await client.publish(note);
  print('gönderi: ${ok ? 'YAYINDA' : 'REDDEDİLDİ'} (${note.id.substring(0, 12)}…)');
  client.dispose();
  exit(ok ? 0 : 1);
}
