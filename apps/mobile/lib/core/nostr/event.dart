import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'bech32.dart';
import 'keys.dart';

/// NIP-01 event yapısı.
class NostrEvent {
  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  /// `note1...` / `nevent` yerine sade geçici kodlama.
  String get noteId => bech32Encode('note', hexToBytes(id));

  Map<String, dynamic> toJson() => {
        'id': id,
        'pubkey': pubkey,
        'created_at': createdAt,
        'kind': kind,
        'tags': tags,
        'content': content,
        'sig': sig,
      };

  factory NostrEvent.fromJson(Map<String, dynamic> json) {
    return NostrEvent(
      id: json['id'] as String,
      pubkey: json['pubkey'] as String,
      createdAt: (json['created_at'] as num).toInt(),
      kind: (json['kind'] as num).toInt(),
      tags: (json['tags'] as List)
          .map((t) => (t as List).map((e) => e.toString()).toList())
          .toList(),
      content: json['content'] as String,
      sig: json['sig'] as String,
    );
  }

  /// NIP-01'e göre `[0, pubkey, created_at, kind, tags, content]` serileştirip
  /// sha256 alır.
  static String computeId({
    required String pubkey,
    required int createdAt,
    required int kind,
    required List<List<String>> tags,
    required String content,
  }) {
    final serialized = jsonEncode([0, pubkey, createdAt, kind, tags, content]);
    return sha256.convert(utf8.encode(serialized)).toString();
  }

  /// Yeni event oluşturur, imzalar ve id hesaplar.
  static NostrEvent create({
    required int kind,
    required String content,
    required KeyPair keys,
    List<List<String>> tags = const [],
    int? createdAt,
  }) {
    final ts = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = computeId(
      pubkey: keys.publicKeyHex,
      createdAt: ts,
      kind: kind,
      tags: tags,
      content: content,
    );
    final sig = keys.sign(id);
    return NostrEvent(
      id: id,
      pubkey: keys.publicKeyHex,
      createdAt: ts,
      kind: kind,
      tags: tags,
      content: content,
      sig: sig,
    );
  }

  /// Id bütünlüğü + Schnorr imza doğrulaması.
  bool verify() {
    final expected = computeId(
      pubkey: pubkey,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
    );
    if (expected != id) return false;
    return KeyPair.verify(pubkey, id, sig);
  }

  @override
  String toString() => 'NostrEvent(kind=$kind, id=${id.substring(0, 8)}…)';
}

/// Sık kullanılan kind'lar.
class EventKind {
  static const int profile = 0;
  static const int note = 1;
  static const int contacts = 3;
  static const int delete = 5;
  static const int repost = 6;
  static const int reaction = 7;
  static const int comment = 10;
  static const int giftWrap = 1059;
  static const int muteList = 10000;
}
