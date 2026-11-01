import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../nostr/keys.dart';

/// Android Keystore'unda (`flutter_secure_storage`) `nsec` saklar.
///
/// Anahtar burada saklanmazsa uygulama kapanınca yeni kimlik üretir (v0.1.0 davranışı).
/// Faz 2'de kalıcı saklama zorunludur.
class KeyStorage {
  static const _nsecKey = 'nsec';
  static const _backupPendingKey = 'backup_pending';

  final FlutterSecureStorage _storage;

  KeyStorage({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  /// `nsec`'i Keystore'a yazar. Özel anahtar bellekte kalmaz.
  Future<void> savePrivateKey(KeyPair keys) async {
    await _storage.write(key: _nsecKey, value: keys.nsec);
  }

  /// Keystore'dan `nsec` okur. Yoksa `null` döner.
  Future<KeyPair?> loadKeys() async {
    final nsec = await _storage.read(key: _nsecKey);
    if (nsec == null || nsec.isEmpty) return null;
    try {
      return KeyPair.fromNsec(nsec);
    } catch (_) {
      return null;
    }
  }

  /// Anahtar silme (hesap silme akışı için).
  Future<void> deleteKeys() async => await _storage.delete(key: _nsecKey);

  /// Zorunlu yedek yapılmadıysa `true`.
  Future<bool> isBackupPending() async {
    final value = await _storage.read(key: _backupPendingKey);
    return value == 'true';
  }

  Future<void> setBackupPending(bool pending) async {
    await _storage.write(key: _backupPendingKey, value: pending ? 'true' : 'false');
  }

  static const _notifReadKey = 'notif_read_at';
  static const _bgWatchKey = 'bg_watch';
  static const _updateSkipKey = 'update_skipped';

  /// "Bu sürüm için bir daha hatırlatma" (güncelleme penceresi).
  Future<String?> loadUpdateSkipped() => _storage.read(key: _updateSkipKey);

  Future<void> saveUpdateSkipped(String version) =>
      _storage.write(key: _updateSkipKey, value: version);

  /// Arka plan bağlantısı tercihi (görev izole edicisi de okuyabilir).
  Future<bool> loadBgWatchEnabled() async =>
      await _storage.read(key: _bgWatchKey) == 'true';

  Future<void> saveBgWatchEnabled(bool enabled) async {
    await _storage.write(key: _bgWatchKey, value: enabled ? 'true' : 'false');
  }

  /// Bildirim merkezinin en son okunduğu an (unix saniye).
  Future<int> loadNotifReadAt() async =>
      int.tryParse(await _storage.read(key: _notifReadKey) ?? '') ?? 0;

  Future<void> saveNotifReadAt(int unixSeconds) async {
    await _storage.write(key: _notifReadKey, value: '$unixSeconds');
  }

  // ------------------------------------------------------------ hikâyeler

  static const _storySeenKey = 'story_seen.v1';
  static const _storySeenTtl = Duration(days: 7);

  /// Görülen hikâye id'leri. Eski kayıtlar (7 günden fazla) atılır.
  Future<Set<String>> loadSeenStories() async {
    final map = await _readStorySeenMap();
    return map.keys.toSet();
  }

  /// Hikâyeyi görüldü olarak işaretler; hata dışarı sızmaz.
  Future<void> markStorySeen(Iterable<String> ids) async {
    final map = await _readStorySeenMap();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in ids) {
      if (id.isNotEmpty) map[id] = now;
    }
    await _writeStorySeenMap(map);
  }

  Future<Map<String, int>> _readStorySeenMap() async {
    try {
      final raw = await _storage.read(key: _storySeenKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final cutoff = DateTime.now()
          .subtract(_storySeenTtl)
          .millisecondsSinceEpoch;
      final out = <String, int>{};
      decoded.forEach((key, value) {
        final ms = value is num ? value.toInt() : 0;
        if (key.toString().isNotEmpty && ms >= cutoff) {
          out[key.toString()] = ms;
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeStorySeenMap(Map<String, int> map) async {
    try {
      await _storage.write(key: _storySeenKey, value: jsonEncode(map));
    } catch (_) {
      // Keystore yazılamazsa görüldü durumu bu oturumda kalır.
    }
  }
}
