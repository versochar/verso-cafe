/// Arka plan görevi (görev izole edicisi).
///
/// Bu dosyadaki kodlar ön plan servisinin KENDİ FlutterEngine/izole edicisinde
/// koşar. Bu yüzden yalnızca saf Dart (`RelayClient`) ve o izole edicide
/// kayıtlı eklentiler kullanılır; `SosyalTaskListener` (MainActivity) eklenti
/// kaydını `GeneratedPluginRegistrant` ile yapar.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_config.dart';
import '../identity/key_storage.dart';
import '../nostr/event.dart';
import '../nostr/nip17_nip44.dart';
import '../nostr/relay_client.dart';

/// Servis izole edicisinin giriş noktası — top-level olmalı.
@pragma('vm:entry-point')
void startSosyalTask() {
  FlutterForegroundTask.setTaskHandler(_SosyalTaskHandler());
}

class _SosyalTaskHandler extends TaskHandler {
  static const _dmChannelId = 'sosyal_dm';
  static const _dmChannelName = 'Mesajlar';
  static const _activityChannelId = 'sosyal_activity';
  static const _activityChannelName = 'Etkinlikler';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final KeyStorage _storage = KeyStorage();

  RelayClient? _client;
  StreamSubscription<NostrEvent>? _eventSub;
  String? _myPub;
  String? _myPriv;

  /// Bildirim tabanı: bundan eskiler asla bildirilmez.
  int _since = 0;

  /// Bildirim merkezi okuma zamanı; her yinelemede tazelenir.
  int _readAt = 0;

  final Set<String> _seen = <String>{};
  int _notified = 0;
  bool _connecting = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _since = _now() - 60; // kısa bir örtüşme payı
    await _refreshKeys();
    await _ensureConnection();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // 20 sn'de bir bekçi: bağlantı koptuysa yeniden dene, okuma zamanını tazele.
    unawaited(_tick());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _eventSub?.cancel();
    _eventSub = null;
    _client?.dispose();
    _client = null;
  }

  Future<void> _tick() async {
    try {
      _readAt = await _storage.loadNotifReadAt();
      final client = _client;
      if (client == null || client.currentState != RelayState.connected) {
        await _ensureConnection();
      }
    } catch (_) {
      // Yineleme asla servisi düşürmemeli.
    }
  }

  Future<void> _refreshKeys() async {
    final keys = await _storage.loadKeys();
    _myPub = keys?.publicKeyHex.toLowerCase();
    _myPriv = keys?.privateKeyHex;
  }

  Future<void> _ensureConnection() async {
    if (_connecting) return;
    _connecting = true;
    try {
      _myPub ??= (await _storage.loadKeys())?.publicKeyHex.toLowerCase();
      final pub = _myPub;
      if (pub == null) return; // kimlik yok: bildirilecek bir şey yok

      await _eventSub?.cancel();
      _client?.dispose();

      final client = RelayClient(AppConfig.relayUrl);
      _client = client;
      _eventSub = client.events.listen((event) {
        unawaited(_onEvent(event));
      });
      await client.connect();
      // Yalnızca bana yönelen olaylar: etkileşimler (p = gönderi sahibi)
      // ve bana yazılmış şifreli zarflar.
      client.subscribe('sosyal-bg-activity', [
        {'kinds': [EventKind.reaction, EventKind.repost, EventKind.comment], 'p': [pub], 'since': _since},
      ]);
      client.subscribe('sosyal-bg-dm', [
        {'kinds': [EventKind.giftWrap], 'p': [pub], 'since': _since},
      ]);
    } catch (_) {
      // Bağlantı yoksa sonraki yineleme tekrar dener.
    } finally {
      _connecting = false;
    }
  }

  Future<void> _onEvent(NostrEvent event) async {
    try {
      final me = _myPub;
      if (me == null) return;
      if (_seen.contains(event.id)) return;
      _seen.add(event.id);
      if (_seen.length > 2000) _seen.remove(_seen.first);

      final actor = event.pubkey.toLowerCase();
      if (actor == me) return; // kendi olaylarımız
      if (event.createdAt <= _since) return; // abone olurkenki geri dönüş
      _readAt = await _storage.loadNotifReadAt();
      if (event.createdAt <= _readAt) return; // zaten okunmuş

      final who = '${actor.substring(0, 8)}…';
      switch (event.kind) {
        case EventKind.giftWrap:
          await _notify(
            id: 2000 + event.createdAt % 100000,
            channelId: _dmChannelId,
            channelName: _dmChannelName,
            high: true,
            title: 'Yeni mesaj',
            body: '$who: ${_dmPreview(event)}',
          );
        case EventKind.reaction:
          await _notify(
            id: 3000 + event.createdAt % 100000,
            channelId: _activityChannelId,
            channelName: _activityChannelName,
            title: 'Beğeni',
            body: '$who gönderini beğendi',
          );
        case EventKind.repost:
          await _notify(
            id: 4000 + event.createdAt % 100000,
            channelId: _activityChannelId,
            channelName: _activityChannelName,
            title: 'Yeniden gönderim',
            body: '$who gönderini yeniden gönderdi',
          );
        case EventKind.comment:
          await _notify(
            id: 5000 + event.createdAt % 100000,
            channelId: _activityChannelId,
            channelName: _activityChannelName,
            title: 'Yorum',
            body: '$who: ${_snippet(event.content)}',
          );
      }
    } catch (_) {
      // Tek olayın hatası servisi düşürmez.
    }
  }

  String _dmPreview(NostrEvent event) {
    final priv = _myPriv;
    if (priv == null) return 'Şifreli mesaj';
    try {
      final decrypted = decryptMessage(event.content, priv, event.pubkey);
      String text = decrypted;
      try {
        final data = jsonDecode(decrypted);
        if (data is Map && data['text'] is String) {
          text = data['text'] as String;
        }
      } catch (_) {}
      return _snippet(text);
    } catch (_) {
      return 'Şifreli mesaj';
    }
  }

  String _snippet(String text) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 90) return oneLine;
    return '${oneLine.substring(0, 90)}…';
  }

  Future<void> _notify({
    required int id,
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    bool high = false,
  }) async {
    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: '${AppConfig.name} arka plan bildirimleri',
          importance: high ? Importance.high : Importance.defaultImportance,
          priority: high ? Priority.high : Priority.defaultPriority,
        ),
      ),
    );
    _notified += 1;
    final stamp = DateTime.now();
    final hh = stamp.hour.toString().padLeft(2, '0');
    final mm = stamp.minute.toString().padLeft(2, '0');
    await FlutterForegroundTask.updateService(
      notificationText: 'Son bildirim $hh:$mm · $_notified toplam',
    );
  }

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
}
