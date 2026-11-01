/// Hikâyeler (stories) — 24 saatlik `kind:1` notları.
///
/// Ayrı bir Nostr türü yok: hikâye, `t` etiketi `story` olan bir nottur.
/// NIP-40 `expiration` etiketiyle relay'e son kullanma bildirilir; istemci
/// ayrıca kendi tarafında 24 saatten eski hikâyeleri göstermez (relay
/// etiketi yok saysa bile). Ana akış bu notları dışlar.
library;

import '../media/media_uploader.dart';
import '../nostr/event.dart';

class Story {
  Story._();

  static const String tag = 'story';
  static const Duration ttl = Duration(hours: 24);

  /// Not bir hikâye mi? (`kind:1` + `["t","story"]`)
  static bool isStory(NostrEvent event) {
    if (event.kind != EventKind.note) return false;
    for (final t in event.tags) {
      if (t.length >= 2 && t[0] == 't' && t[1].toLowerCase() == tag) {
        return true;
      }
    }
    return false;
  }

  /// NIP-40 son kullanma zamanı (unix saniye); yoksa null.
  static int? expirationSeconds(NostrEvent event) {
    for (final t in event.tags) {
      if (t.length >= 2 && t[0] == 'expiration') {
        final value = int.tryParse(t[1]);
        if (value != null) return value;
      }
    }
    return null;
  }

  /// Hikâye süresi dolmuş mu? Etiket yoksa [ttl] üzerinden yaşla karar verilir.
  static bool isExpired(NostrEvent event, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final exp = expirationSeconds(event);
    if (exp != null) {
      return exp <= current.millisecondsSinceEpoch ~/ 1000;
    }
    final age = current.millisecondsSinceEpoch ~/ 1000 - event.createdAt;
    return age > ttl.inSeconds;
  }

  /// Yayınlanacak hikâyeye eklenecek etiketler (t + NIP-40).
  static List<List<String>> tagsFor({DateTime? now}) {
    final at = now ?? DateTime.now();
    final expiration = at.add(ttl).millisecondsSinceEpoch ~/ 1000;
    return [
      ['t', tag],
      ['expiration', '$expiration'],
    ];
  }

  /// Hikâyeleri yazara göre gruplar; süresi dolanları ve sessize alınanları
  /// atar. Gruplar en yeni hikâyesine göre yeniden eskiye sıralanır; grup
  /// içindeki hikâyeler eskiden yeniye (izleme sırası) durur.
  static List<StoryGroup> group(
    Iterable<NostrEvent> events, {
    DateTime? now,
    bool Function(String pubkey)? isMuted,
  }) {
    final byAuthor = <String, List<NostrEvent>>{};
    for (final e in events) {
      if (!isStory(e) || isExpired(e, now: now)) continue;
      if (isMuted != null && isMuted(e.pubkey)) continue;
      byAuthor.putIfAbsent(e.pubkey, () => []).add(e);
    }
    final groups = <StoryGroup>[];
    byAuthor.forEach((pubkey, items) {
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      groups.add(StoryGroup(pubkey: pubkey, items: List.unmodifiable(items)));
    });
    groups.sort((a, b) => b.latest.createdAt.compareTo(a.latest.createdAt));
    return groups;
  }
}

/// Bir yazarın aktif hikâyeleri.
class StoryGroup {
  const StoryGroup({required this.pubkey, required this.items});

  final String pubkey;

  /// Eskiden yeniye sıralı.
  final List<NostrEvent> items;

  NostrEvent get latest => items.last;

  bool get hasImage =>
      items.any((e) => MediaRef.firstImageUrl(e) != null);

  /// Bu grupta görülmemiş hikâye var mı?
  bool hasUnseen(Set<String> seen) =>
      items.any((e) => !seen.contains(e.id));
}
