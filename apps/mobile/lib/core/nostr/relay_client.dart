import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'event.dart';

enum RelayState { disconnected, connecting, connected }

/// Minimal Nostr relay istemcisi.
///
/// Protokolü kendi kontrolümüzde tutmak için bilinçli olarak ince tutuldu;
/// ileride `ndk` gibi bir kütüphaneye geçilirse bu sınıfın arayüzü korunur.
class RelayClient {
  RelayClient(this.url, {this.reconnect = true});

  final String url;
  final bool reconnect;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retryTimer;
  int _attempt = 0;
  bool _closedByUser = false;

  final _events = StreamController<NostrEvent>.broadcast();
  final _state = StreamController<RelayState>.broadcast();
  final _notices = StreamController<String>.broadcast();
  final Map<String, Completer<bool>> _pendingOk = {};
  final Map<String, List<Map<String, dynamic>>> _subscriptions = {};

  RelayState _current = RelayState.disconnected;

  Stream<NostrEvent> get events => _events.stream;
  Stream<RelayState> get state => _state.stream;
  Stream<String> get notices => _notices.stream;
  RelayState get currentState => _current;

  void _setState(RelayState s) {
    _current = s;
    if (!_state.isClosed) _state.add(s);
  }

  Future<void> connect() async {
    _closedByUser = false;
    if (_current == RelayState.connected || _current == RelayState.connecting) {
      return;
    }
    _setState(RelayState.connecting);
    try {
      final channel = IOWebSocketChannel.connect(
        Uri.parse(url),
        connectTimeout: const Duration(seconds: 10),
        pingInterval: const Duration(seconds: 30),
      );
      await channel.ready;
      _channel = channel;
      _attempt = 0;
      _sub = channel.stream.listen(
        _onData,
        onError: (Object e) => _notices.add('WS hata: $e'),
        onDone: _onDone,
        cancelOnError: false,
      );
      _setState(RelayState.connected);
      // Yeniden bağlanmada abonelikleri tazele.
      _subscriptions.forEach((id, filters) {
        try {
          _send(['REQ', id, ...filters]);
        } catch (_) {}
      });
    } catch (e) {
      _notices.add('Bağlantı hatası: $e');
      _setState(RelayState.disconnected);
      _scheduleReconnect();
    }
  }

  void _onDone() {
    _setState(RelayState.disconnected);
    _channel = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!reconnect || _closedByUser) return;
    _attempt = (_attempt + 1).clamp(1, 6);
    final delay = Duration(seconds: 1 << (_attempt - 1));
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, connect);
  }

  void _onData(dynamic raw) {
    if (raw is! String) return;
    dynamic msg;
    try {
      msg = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (msg is! List || msg.isEmpty) return;

    switch (msg[0]) {
      case 'EVENT':
        if (msg.length >= 3 && msg[2] is Map<String, dynamic>) {
          final event = NostrEvent.fromJson(msg[2] as Map<String, dynamic>);
          if (event.verify()) _events.add(event);
        }
      case 'REPLACE':
        // Değiştirilebilir olay eskisinin yerini aldı (NIP-01); aynı şekilde
        // işlenir — alıcı taraf `created_at` ile hangisinin geçerli olduğunu
        // zaten kendi çözüyor (kind:3, kind:10000 vb.).
        if (msg.length >= 3 && msg[2] is Map<String, dynamic>) {
          final event = NostrEvent.fromJson(msg[2] as Map<String, dynamic>);
          if (event.verify()) _events.add(event);
        }
      case 'OK':
        if (msg.length >= 3) {
          final id = msg[1] as String;
          final ok = msg[2] == true;
          final message = msg.length > 3 ? msg[3].toString() : '';
          if (!ok) _notices.add('Reddedildi: $message');
          _pendingOk.remove(id)?.complete(ok);
        }
      case 'NOTICE':
        if (msg.length >= 2) _notices.add(msg[1].toString());
      case 'CLOSED':
        if (msg.length >= 3) _notices.add('Abonelik kapandı: ${msg[2]}');
      case 'EOSE':
        break;
      case 'AUTH':
        break;
      default:
        break;
    }
  }

  void _send(List<dynamic> message) {
    final ch = _channel;
    if (ch == null) throw StateError('Relay bağlı değil');
    ch.sink.add(jsonEncode(message));
  }

  /// Event yayınlar; relay `OK` döndüğünde sonuçlanır.
  Future<bool> publish(NostrEvent event) {
    final completer = Completer<bool>();
    _pendingOk[event.id] = completer;
    try {
      _send(['EVENT', event.toJson()]);
    } catch (e) {
      _pendingOk.remove(event.id);
      return Future.value(false);
    }
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _pendingOk.remove(event.id);
        return false;
      },
    );
  }

  /// Filtreyle abone olur. Örnek filtre:
  /// `{'kinds': [0], 'authors': [pubkey], 'limit': 50}`
  ///
  /// Abonelik kaydedilir; bağlantı kopup yeniden kurulursa otomatik tekrarlanır.
  void subscribe(String subId, List<Map<String, dynamic>> filters) {
    _subscriptions[subId] = filters;
    _send(['REQ', subId, ...filters]);
  }

  void unsubscribe(String subId) {
    _subscriptions.remove(subId);
    try {
      _send(['CLOSE', subId]);
    } catch (_) {}
  }

  Future<void> dispose() async {
    _closedByUser = true;
    _retryTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(RelayState.disconnected);
    await _events.close();
    await _state.close();
    await _notices.close();
  }
}
