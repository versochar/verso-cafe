import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../nostr/event.dart';
import '../nostr/keys.dart';
import '../nostr/nip98.dart';

/// Supported media types.
enum MediaType {
  image,
  video,
}

/// Bir yüklenmiş medya dosyasının gönderiye gömülen bilgisi (NIP-92 imeta).
class MediaRef {
  const MediaRef({
    required this.url,
    required this.sha256,
    required this.mime,
    this.dim,
    this.type = MediaType.image,
    this.duration,
  });

  final String url;
  final String sha256;
  final String mime;
  final String? dim;
  final MediaType type;
  final int? duration; // video duration in seconds

  /// Gönderi olayına gömülecek `imeta` etiketi.
  List<String> toImetaTag() {
    final tag = <String>[
      'imeta',
      'url', url,
      'm', mime,
      'x', sha256,
    ];
    if (dim != null) tag.addAll(['dim', dim!]);
    if (type == MediaType.video && duration != null) {
      tag.addAll(['duration', duration.toString()]);
    }
    return tag;
  }

  /// imeta (ya da eski `media`/`thumb` alışkanlıkları) etiketlerinden ilk
  /// görüntü adresini çözer; yoksa null.
  static String? firstImageUrl(NostrEvent event) {
    for (final tag in event.tags) {
      if (tag.length >= 3 && tag[0] == 'imeta') {
        for (var i = 1; i + 1 < tag.length; i += 2) {
          if (tag[i] == 'url' && tag[i + 1].startsWith('http')) {
            return tag[i + 1];
          }
        }
      }
    }
    return null;
  }
}

/// Medya sunucusuna ham gövdeyle yükleme yapar.
class MediaUploader {
  MediaUploader(this.baseUrl);

  /// ör. `http://192.168.1.109:8080`
  final String baseUrl;

  Future<MediaRef> upload({
    required Uint8List bytes,
    required String mime,
    required KeyPair keys,
    String? dim,
    MediaType type = MediaType.image,
    int? duration,
  }) async {
    final url = '$baseUrl/upload';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.contentType = ContentType.parse(mime);
      request.headers.contentLength = bytes.length;
      request.headers.set(
        HttpHeaders.authorizationHeader,
        buildNip98AuthHeader(url: url, method: 'POST', keys: keys),
      );
      request.add(bytes);
      final response =
          await request.close().timeout(const Duration(seconds: 60));
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        var message = body;
        try {
          message = (jsonDecode(body) as Map)['message'] as String? ?? body;
        } catch (_) {}
        throw MediaUploadException(
          'sunucu ${response.statusCode}: $message',
        );
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      return MediaRef(
        url: json['url'] as String,
        sha256: json['sha256'] as String,
        mime: mime,
        dim: dim,
        type: type,
        duration: duration,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class MediaUploadException implements Exception {
  MediaUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}
