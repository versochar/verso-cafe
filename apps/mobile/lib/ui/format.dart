/// Türkçe, kısa tarih/saat biçimleri.
library;

String relativeTime(int unixSeconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final diff = DateTime.now().difference(date);

  if (diff.inSeconds < 60) return 'şimdi';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk';
  if (diff.inHours < 24) return '${diff.inHours} sa';
  if (diff.inDays < 7) return '${diff.inDays} g';
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
}

/// Akış kartları için büyük harfli, "ÖNCE" sonekli kısa zaman.
String feedTime(int unixSeconds) {
  final rel = relativeTime(unixSeconds);
  if (rel == 'şimdi') return 'ŞİMDİ';
  if (rel.contains('.')) {
    // gg.tt biçimi takvim tarihine dönüşür
    final date = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    const months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
        'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    return '${date.day} ${months[date.month - 1]}';
  }
  return '$rel ÖNCE'.toUpperCase();
}

String clockTime(int unixSeconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

/// `npub1abcdef…wxyz` biçiminde kısaltır.
String shortNpub(String? npub, {int head = 10, int tail = 4}) {
  if (npub == null || npub.length <= head + tail) return npub ?? '';
  return '${npub.substring(0, head)}…${npub.substring(npub.length - tail)}';
}

String relayHost(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  return uri.host;
}
