import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../identity/key_storage.dart';
import '../media/media_uploader.dart';
import '../nostr/event.dart';
import '../nostr/keys.dart';
import '../nostr/nip17_nip44.dart';
import '../nostr/relay_client.dart';
import '../stories/story.dart';

/// Başka bir kullanıcının `kind:0` içeriğinden çıkarılan görünüm bilgisi.
class ProfileView {
  const ProfileView({
    required this.pubkey,
    this.name,
    this.about,
    this.picture,
    this.banner,
  });

  final String pubkey;
  final String? name;
  final String? about;
  final String? picture;
  final String? banner;

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return '${pubkey.substring(0, 8)}…';
  }

  static ProfileView fromEvent(NostrEvent event) {
    var name = event.pubkey;
    String? about;
    String? picture;
    String? banner;
    try {
      final data = jsonDecode(event.content);
      if (data is Map) {
        final n = data['name'] ?? data['display_name'];
        if (n is String && n.trim().isNotEmpty) name = n.trim();
        if (data['about'] is String) about = (data['about'] as String).trim();
        if (data['picture'] is String) picture = (data['picture'] as String).trim();
        if (data['banner'] is String) banner = (data['banner'] as String).trim();
      }
    } catch (_) {
      // Bozuk JSON: pubkey ile devam et.
    }
    return ProfileView(
      pubkey: event.pubkey,
      name: name,
      about: about,
      picture: picture,
      banner: banner,
    );
  }
}

/// Uygulama oturumu: kimlik, relay bağlantısı ve event önbelleği.
///
/// Ekranlar kendi bağlantılarını kurmak yerine bu tek örneği dinler; böylece
/// Akıştaki tek öğe: kendi başına bir gönderi ya da biri tarafından
/// yeniden gönderilmiş (`kind:6`, NIP-18) bir gönderi.
class FeedItem {
  FeedItem.note(this.note) : repostedBy = null;
  FeedItem.repost(this.note, this.repostedBy);

  final NostrEvent note;
  final NostrEvent? repostedBy;

  int get sortKey => repostedBy?.createdAt ?? note.createdAt;
}

/// Bildirim merkezi: kendi gönderimize yönelen tek bir eylem kaydı.
class ActivityItem {
  ActivityItem({
    required this.action,
    required this.actor,
    required this.targetId,
    required this.sourceId,
    required this.createdAt,
    this.commentText,
  });

  /// `like` | `comment` | `repost`
  final String action;

  /// Eylemi yapan pubkey.
  final String actor;

  /// Etkilenen kendi gönderimizin id'si (önbellekte sonra bulunabilir).
  final String targetId;

  /// Yorum eyleminde yorum metni.
  final String? commentText;

  /// Bu eylemi üreten nostr olayının id'si (yinelenme filtresi).
  final String sourceId;

  final int createdAt;
}

/// relay'e tek WebSocket açılır ve kimlik tüm sekmelerde aynıdır.
class AppSession extends ChangeNotifier {
  AppSession._();

  static final AppSession instance = AppSession._();

  final KeyStorage keyStorage = KeyStorage();
  RelayClient? _client;

  KeyPair? keys;
  RelayState relayState = RelayState.disconnected;
  bool ready = false;

  /// `kind:1` notları (en yeni önce).
  final List<NostrEvent> notes = [];

  /// Gelen/giden `kind:1059` zarfları (DM).
  final List<NostrEvent> giftWraps = [];

  /// `kind:6` yeniden gönderiler (en yeni önce).
  final List<NostrEvent> reposts = [];

  /// `kind:7` beğenileri ve `kind:10` yorumları, hedef event id'ye göre sayılır.
  final Map<String, Set<String>> _reactions = {};
  final Map<String, int> _comments = {};

  /// Hedef event id → yeniden gönderen pubkey kümesi.
  final Map<String, Set<String>> _reposters = {};

  /// Benim sessize aldığım (`kind:10000`) pubkey'ler.
  final Set<String> _muted = {};

  /// Son görülen kendi `kind:10000` zamanı (yenisiyle geçersiz kılınır).
  int _mutedAt = 0;

  /// Kendi gönderilerimize yönelen eylemler (en yeni önce); bildirim merkezi.
  final List<ActivityItem> activity = [];

  /// Bildirim merkezinin en son okunduğu an (unix saniye); kalıcıdır.
  int _activityReadAt = 0;

  /// pubkey → profil.
  final Map<String, ProfileView> profiles = {};

  /// pubkey → o kişinin `kind:3` listesindeki takip ettikleri.
  final Map<String, Set<String>> _contacts = {};

  /// pubkey → son görülen `kind:3` zamanı; daha yenisi gelirse liste değişir.
  final Map<String, int> _contactsAt = {};

  /// Kullanılabilir takip listeleri (diğer sayfalardan erişim için).
  Map<String, Set<String>> get contacts => _contacts;

  /// Beğeni reaksiyonları (diğer sayfalardan erişim için).
  Map<String, Set<String>> get reactions => _reactions;

  /// Son hata/uyarı mesajı (arayüzde gösterilir).
  String? lastNotice;

  /// `kind:10` yorumların kendisi, hedef event id'ye göre.
  final Map<String, List<NostrEvent>> _commentEvents = {};

  /// Yerel olarak kaydedilen (yer imi) gönderi id'leri; relay'e yazılmaz.
  final Set<String> _saved = {};

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  KeyPair? get _k => keys;

  bool get connected => relayState == RelayState.connected;

  ProfileView get me => profiles[keys?.publicKeyHex] ??
      ProfileView(pubkey: keys?.publicKeyHex ?? '', name: 'Sen');

  @override
  void dispose() {
    _changes.close();
    _client?.dispose();
    super.dispose();
  }

  Future<void> init() async {
    keys = await keyStorage.loadKeys();
    keys ??= KeyPair.generate();
    await keyStorage.savePrivateKey(keys!);
    _activityReadAt = await keyStorage.loadNotifReadAt();

    final client = RelayClient(AppConfig.relayUrl);
    _client = client;
    client.state.listen((state) {
      relayState = state;
      _notify();
    });
    client.notices.listen((notice) {
      lastNotice = notice;
      _notify();
    });
    client.events.listen(_ingest);

    await client.connect();
    try {
      client.subscribe('sosyal-main', [
        {
          'kinds': [
            EventKind.profile,
            EventKind.note,
            EventKind.contacts,
            EventKind.repost,
            EventKind.reaction,
            EventKind.comment,
            EventKind.muteList,
          ],
          'limit': 200,
        },
      ]);
      client.subscribe('sosyal-dm', [
        {'kinds': [EventKind.giftWrap], 'limit': 100},
      ]);
    } catch (_) {
      // Bağlantı koptuysa yeniden bağlanınca abonelikler tekrar gönderilir.
    }

    ready = true;
    _notify();
  }

  void _ingest(NostrEvent event) {
    switch (event.kind) {
      case EventKind.profile:
        final view = ProfileView.fromEvent(event);
        final existing = profiles[event.pubkey];
        if (existing == null) {
          profiles[event.pubkey] = view;
        } else {
          profiles[event.pubkey] = ProfileView(
            pubkey: event.pubkey,
            name: view.name ?? existing.name,
            about: view.about ?? existing.about,
            picture: view.picture ?? existing.picture,
          );
        }
        break;
      case EventKind.contacts:
        final last = _contactsAt[event.pubkey];
        if (last != null && last >= event.createdAt) break;
        _contactsAt[event.pubkey] = event.createdAt;
        _contacts[event.pubkey] = {
          for (final tag in event.tags)
            if (tag.length >= 2 && tag[0] == 'p' && tag[1].length == 64)
              tag[1].toLowerCase(),
        };
        break;
      case EventKind.note:
        if (notes.any((e) => e.id == event.id)) return;
        notes.insert(0, event);
        break;
      case EventKind.repost:
        if (reposts.any((e) => e.id == event.id)) break;
        final target = _targetOf(event);
        if (target == null) break;
        reposts.insert(0, event);
        _reposters
            .putIfAbsent(target, () => <String>{})
            .add(event.pubkey.toLowerCase());
        _maybeActivity('repost', event);
        break;
      case EventKind.muteList:
        // Yalnızca kendi listemiz bizi ilgilendirir (replaceable event).
        if (event.pubkey != keys?.publicKeyHex) break;
        if (event.createdAt <= _mutedAt) break;
        _mutedAt = event.createdAt;
        _muted
          ..clear()
          ..addAll([
            for (final tag in event.tags)
              if (tag.length >= 2 && tag[0] == 'p' && tag[1].length == 64)
                tag[1].toLowerCase(),
          ]);
        break;
      case EventKind.reaction:
        final target = _targetOf(event);
        if (target != null) {
          final set = _reactions.putIfAbsent(target, () => <String>{});
          if (event.content == '-') {
            set.remove(event.pubkey);
          } else {
            set.add(event.pubkey);
            _maybeActivity('like', event, target: target);
          }
        }
        break;
      case EventKind.comment:
        final target = _targetOf(event);
        if (target == null) break;
        final list = _commentEvents.putIfAbsent(target, () => <NostrEvent>[]);
        if (list.any((e) => e.id == event.id)) break;
        list.insert(0, event);
        _comments[target] = list.length;
        _maybeActivity('comment', event, target: target, text: event.content);
        break;
      case EventKind.giftWrap:
        if (giftWraps.any((e) => e.id == event.id)) return;
        giftWraps.insert(0, event);
        break;
      default:
        return;
    }
    _notify();
  }

  /// `e` etiketiyle hedef event; yoksa `a` etiketinin son parçası.
  String? _targetOf(NostrEvent event) {
    for (final tag in event.tags) {
      if (tag.length >= 2 && tag[0] == 'e') return tag[1];
    }
    return null;
  }

  int reactionCount(String eventId) => _reactions[eventId]?.length ?? 0;

  int commentCount(String eventId) => _comments[eventId] ?? 0;

  bool reactedByMe(String eventId) =>
      _reactions[eventId]?.contains(keys?.publicKeyHex) ?? false;

  /// O kişinin `kind:3` listesinde kaç kişi var (takip).
  int followingCount(String pubkey) => _contacts[pubkey]?.length ?? 0;

  /// Kaç kişinin `kind:3` listesinde bu pubkey var (takipçi).
  int followerCount(String pubkey) => _contacts.values
      .where((set) => set.contains(pubkey.toLowerCase()))
      .length;

  /// Bir kişinin gönderileri (en yeni önce); sessize aldıysam boş.
  /// Hikâyeler ana akış/profil listesinde görünmez.
  List<NostrEvent> notesBy(String pubkey) => isMuted(pubkey)
      ? const []
      : notes
          .where((e) =>
              e.pubkey == pubkey &&
              !Story.isStory(e) &&
              !Story.isExpired(e))
          .toList();

  /// Son günlerde gönderi atan kişiler.
  List<String> activeAuthors({int limit = 12}) {
    final seen = <String>{};
    for (final note in visibleNotes) {
      seen.add(note.pubkey);
      if (seen.length >= limit) break;
    }
    return seen.toList();
  }

  /// Aktif hikâyeler, yazara göre gruplu (en yeni grup önce).
  List<StoryGroup> get storyGroups =>
      Story.group(notes, isMuted: isMuted);

  /// Bir gönderiye yapılmış yorumlar (en yeni önce).
  List<NostrEvent> commentsFor(String eventId) =>
      _commentEvents[eventId] ?? const [];

  /// Bu kişiyi takip ediyor muyum?
  bool isFollowing(String pubkey) =>
      _contacts[keys?.publicKeyHex ?? '']?.contains(pubkey.toLowerCase()) ??
      false;

  /// Tek kişiyi mevcut takip listeme ekleyip `kind:3` olarak yayınlar.
  Future<bool> followPerson(String pubkey) {
    final mine = {...(_contacts[keys?.publicKeyHex] ?? <String>{}), pubkey};
    return follow(mine.toList());
  }

  bool savedByMe(String eventId) => _saved.contains(eventId);

  /// Yerel yer imi; relay'e bir şey yazılmaz, cihazda kalır.
  void toggleSave(String eventId) {
    if (!_saved.remove(eventId)) _saved.add(eventId);
    _notify();
  }

  // ------------------------------------------------------------- repost / mute

  int repostCount(String eventId) => _reposters[eventId]?.length ?? 0;

  bool repostedByMe(String eventId) =>
      _reposters[eventId]?.contains(keys?.publicKeyHex ?? '') ?? false;

  /// `kind:6` yeniden gönderim (NIP-18). Aynı gönderi ikinci kez gönderilmez.
  Future<bool> repostNote(NostrEvent target) async {
    final k = _k;
    if (k == null) return false;
    if (repostedByMe(target.id)) return false;
    final event = NostrEvent.create(
      kind: EventKind.repost,
      content: '',
      keys: k,
      tags: [
        ['e', target.id],
        ['p', target.pubkey],
      ],
    );
    return publish(event);
  }

  bool isMuted(String pubkey) => _muted.contains(pubkey.toLowerCase());

  /// Sessize aldığım kişiler (ayarlar listesi için).
  List<String> get mutedAuthors => _muted.toList()..sort();

  /// Kişiyi sessize listesine ekler/çıkarır ve tam listeyi `kind:10000`
  /// olarak yayınlar (NIP-10 replaceable; eski sürüm relay'de geçersizdir).
  Future<bool> toggleMute(String pubkey) async {
    final k = _k;
    if (k == null) return false;
    final target = pubkey.toLowerCase();
    final next = {..._muted};
    if (!next.remove(target)) next.add(target);
    final event = NostrEvent.create(
      kind: EventKind.muteList,
      content: jsonEncode({
        for (final p in next) p: {'tags': ['mute']},
      }),
      keys: k,
      tags: [
        for (final p in next) ['p', p],
      ],
    );
    return publish(event);
  }

  /// Sessize aldıklarımın gönderileri ve hikâyeler hariç akış.
  List<NostrEvent> get visibleNotes => notes
      .where((e) =>
          !isMuted(e.pubkey) &&
          !Story.isStory(e) &&
          !Story.isExpired(e))
      .toList();

  /// Akış görünümü: notlar + yeniden gönderimler, zaman damgasına göre karışık.
  /// Yeniden gönderilen not, şeritli kopyada göründüğü için bir kez daha
  /// kendi başına listelenmez.
  List<FeedItem> get feedItems {
    final items = <FeedItem>[];
    final repostedIds = <String>{};
    for (final rp in reposts) {
      if (isMuted(rp.pubkey)) continue;
      final target = _targetOf(rp);
      if (target == null) continue;
      final original = notes.where((n) => n.id == target);
      if (original.isEmpty) continue;
      final note = original.first;
      if (isMuted(note.pubkey)) continue;
      // Kendi gönderini kendin yeniden gönderdiysen ayrı öğe gösterme.
      if (note.pubkey == rp.pubkey) continue;
      repostedIds.add(note.id);
      items.add(FeedItem.repost(note, rp));
    }
    for (final n in visibleNotes) {
      if (repostedIds.contains(n.id)) continue;
      items.add(FeedItem.note(n));
    }
    items.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return items;
  }

  // ------------------------------------------------------------ bildirimler

  /// Eylem kendi gönderimize yöneliyorsa aktivite günlüğüne yazar.
  void _maybeActivity(String action, NostrEvent event,
      {String? target, String? text}) {
    final me = keys?.publicKeyHex;
    if (me == null) return;
    final actor = event.pubkey.toLowerCase();
    if (actor == me.toLowerCase() || isMuted(actor)) return;
    final targetId = target ?? _targetOf(event);
    if (targetId == null) return;
    NostrEvent? note;
    for (final n in notes) {
      if (n.id == targetId) {
        note = n;
        break;
      }
    }
    if (note != null) {
      if (note.pubkey != me) return;
    } else {
      // Gönderi henüz önbellekte yoksa p etiketine güven (NIP-10/NIP-25).
      var mentionsMe = false;
      for (final tag in event.tags) {
        if (tag.length >= 2 &&
            tag[0] == 'p' &&
            tag[1].toLowerCase() == me.toLowerCase()) {
          mentionsMe = true;
          break;
        }
      }
      if (!mentionsMe) return;
    }
    if (activity.any((a) => a.sourceId == event.id)) return;
    activity.insert(
      0,
      ActivityItem(
        action: action,
        actor: actor,
        targetId: targetId,
        sourceId: event.id,
        createdAt: event.createdAt,
        commentText: text,
      ),
    );
  }

  /// Okunmamış bildirim sayısı.
  int get unreadActivity =>
      activity.where((a) => a.createdAt > _activityReadAt).length;

  /// Son okuma anı (unix saniye); ekranlar kendi rozet eşiğini saklar.
  int get activityReadAt => _activityReadAt;

  /// Merkezi açtığımızda okundu işaretini kalıcı olarak günceller.
  Future<void> markActivityRead() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now <= _activityReadAt) return;
    _activityReadAt = now;
    await keyStorage.saveNotifReadAt(now);
    _notify();
  }

  /// id ile gönderi arar (bildirim alıntısı için).
  NostrEvent? noteById(String id) {
    for (final n in notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  void _notify() {
    notifyListeners();
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<bool> publish(NostrEvent event) async {
    final client = _client;
    if (client == null || !connected) return false;
    final ok = await client.publish(event);
    if (ok) _ingest(event);
    return ok;
  }

  /// Manuel event işleme (örn. arama sonucu gelen profil).
  void ingestEvent(NostrEvent event) => _ingest(event);

  /// `kind:1` paylaşım.
  Future<bool> publishNote(String text, {List<List<String>> tags = const []}) async {
    final k = _k;
    if (k == null) return false;
    final event = NostrEvent.create(
      kind: EventKind.note,
      content: text,
      keys: k,
      tags: tags,
    );
    return publish(event);
  }

  /// 24 saatlik hikâye: `kind:1` + `t=story` + NIP-40 `expiration`.
  Future<bool> publishStory(String caption,
      {List<List<String>> tags = const []}) async {
    final k = _k;
    if (k == null) return false;
    final event = NostrEvent.create(
      kind: EventKind.note,
      content: caption.trim(),
      keys: k,
      tags: [...Story.tagsFor(), ...tags],
    );
    return publish(event);
  }

  /// `kind:0` profil (name, about, picture, banner).
  Future<bool> publishProfile({
    required String name,
    required String about,
    String? picture,
    String? banner,
  }) async {
    final k = _k;
    if (k == null) return false;
    final data = <String, String>{
      'name': name.trim(),
      'about': about.trim(),
    };
    if (picture != null && picture.isNotEmpty) data['picture'] = picture;
    if (banner != null && banner.isNotEmpty) data['banner'] = banner;
    final event = NostrEvent.create(
      kind: EventKind.profile,
      content: jsonEncode(data),
      keys: k,
    );
    return publish(event);
  }

  /// `kind:7` beğeni.
  Future<bool> react(NostrEvent target) async {
    final k = _k;
    if (k == null) return false;
    final already = reactedByMe(target.id);
    final event = NostrEvent.create(
      kind: EventKind.reaction,
      content: already ? '-' : '+',
      keys: k,
      tags: [
        ['e', target.id],
        ['p', target.pubkey],
      ],
    );
    final ok = await publish(event);
    if (ok) {
      final set = _reactions.putIfAbsent(target.id, () => <String>{});
      if (already) {
        set.remove(k.publicKeyHex);
      } else {
        set.add(k.publicKeyHex);
      }
      _notify();
    }
    return ok;
  }

  /// `kind:10` yorum (NIP-10 kök etiketi ile).
  Future<bool> comment(NostrEvent target, String text) async {
    final k = _k;
    if (k == null) return false;
    if (text.trim().isEmpty) return false;
    final event = NostrEvent.create(
      kind: EventKind.comment,
      content: text.trim(),
      keys: k,
      tags: [
        ['e', target.id, '', 'root'],
        ['p', target.pubkey],
      ],
    );
    return publish(event);
  }

  /// `kind:3` takip listesi.
  Future<bool> follow(List<String> pubkeys) async {
    final k = _k;
    if (k == null) return false;
    final event = NostrEvent.create(
      kind: EventKind.contacts,
      content: '',
      keys: k,
      tags: [
        for (final pk in pubkeys) ['p', pk, AppConfig.relayUrl],
      ],
    );
    return publish(event);
  }

  /// `kind:5` silme isteği (NIP-09).
  Future<bool> deleteNote(NostrEvent target) async {
    final k = _k;
    if (k == null) return false;
    if (target.pubkey != k.publicKeyHex) return false;
    final event = NostrEvent.create(
      kind: EventKind.delete,
      content: '',
      keys: k,
      tags: [
        ['e', target.id],
        ['k', '${target.kind}'],
      ],
    );
    final ok = await publish(event);
    if (ok) {
      notes.removeWhere((e) => e.id == target.id);
      _notify();
    }
    return ok;
  }

  /// `kind:1059` gift wrap — alıcıya şifreli mesaj (metin + medya opsiyonel).
  Future<bool> sendDm(String recipientPubkey, String text,
      {Uint8List? mediaBytes,
      String? mediaMime,
      MediaType mediaType = MediaType.image,
      bool viewOnce = false}) async {
    final k = _k;
    if (k == null || (text.trim().isEmpty && mediaBytes == null)) return false;

    String content = text.trim();
    String? mediaUrl;
    String? mediaSha256;
    String? mediaDim;
    int? mediaDuration;

    // Upload media if present
    if (mediaBytes != null && mediaMime != null) {
      try {
        final ref = await MediaUploader(AppConfig.mediaUrl).upload(
          bytes: mediaBytes,
          mime: mediaMime,
          keys: k,
          type: mediaType,
        );
        mediaUrl = ref.url;
        mediaSha256 = ref.sha256;
        mediaDim = ref.dim;
        mediaDuration = ref.duration;
      } catch (_) {
        // If upload fails, send text only
      }
    }

    // Build the inner message content (JSON for structured data)
    final innerData = <String, dynamic>{
      if (content.isNotEmpty) 'text': content,
      if (mediaUrl != null) 'media': {
        'url': mediaUrl,
        'mime': mediaMime,
        'sha256': mediaSha256,
        if (mediaDim != null) 'dim': mediaDim,
        if (mediaDuration != null) 'duration': mediaDuration,
        'type': mediaType == MediaType.video ? 'video' : 'image',
        'viewOnce': viewOnce,
      },
    };

    final innerContent = jsonEncode(innerData);
    final event = NostrEvent.create(
      kind: EventKind.giftWrap,
      content: encryptMessage(innerContent, k.privateKeyHex, recipientPubkey),
      keys: k,
      tags: [
        ['p', recipientPubkey],
      ],
    );
    return publish(event);
  }
}
