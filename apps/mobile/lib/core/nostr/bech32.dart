/// NIP-19 için bech32 kodlama/çözme (BIP-173, bech32m değil).
///
/// `npub`, `nsec`, `note` gibi ön ekleri üretir.
library;

const String _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

const List<int> _generator = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];

int _polymod(List<int> values) {
  var chk = 1;
  for (final v in values) {
    final top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (var i = 0; i < 5; i++) {
      if (((top >> i) & 1) == 1) chk ^= _generator[i];
    }
  }
  return chk;
}

List<int> _hrpExpand(String hrp) {
  final out = <int>[];
  for (final c in hrp.codeUnits) {
    out.add(c >> 5);
  }
  out.add(0);
  for (final c in hrp.codeUnits) {
    out.add(c & 31);
  }
  return out;
}

List<int> _createChecksum(String hrp, List<int> data) {
  final values = <int>[..._hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0];
  final mod = _polymod(values) ^ 1;
  return List<int>.generate(6, (i) => (mod >> (5 * (5 - i))) & 31);
}

/// 8 bitlik baytları 5 bitlik gruplara (veya tersine) çevirir.
List<int> convertBits(List<int> data, int from, int to, {bool pad = true}) {
  var acc = 0;
  var bits = 0;
  final ret = <int>[];
  final maxv = (1 << to) - 1;

  for (final value in data) {
    if (value < 0 || (value >> from) != 0) {
      throw FormatException('Geçersiz değer: $value');
    }
    acc = (acc << from) | value;
    bits += from;
    while (bits >= to) {
      bits -= to;
      ret.add((acc >> bits) & maxv);
    }
  }

  if (pad) {
    if (bits > 0) ret.add((acc << (to - bits)) & maxv);
  } else if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
    throw const FormatException('Geçersiz dolgu');
  }
  return ret;
}

/// 32 baytlık veriyi NIP-19 bech32 stringine çevirir.
String bech32Encode(String hrp, List<int> data8) {
  final data5 = convertBits(data8, 8, 5);
  final checksum = _createChecksum(hrp, data5);
  final combined = [...data5, ...checksum];
  final sb = StringBuffer(hrp)..write('1');
  for (final v in combined) {
    sb.write(_charset[v]);
  }
  return sb.toString();
}

/// NIP-19 bech32 stringini çözer, 8 bitlik baytları döndürür.
///
/// BIP-173'ün 90 karakter sınırı Nostr'da uygulanmaz: `ncryptsec` ~163 karakterdir.
({String hrp, List<int> data}) bech32Decode(String input) {
  if (input.length < 8 || input.length > 1024) {
    throw const FormatException('Geçersiz uzunluk');
  }
  final lower = input.toLowerCase();
  if (input != lower && input != input.toUpperCase()) {
    throw const FormatException('Karışık büyük/küçük harf');
  }
  final sep = lower.lastIndexOf('1');
  if (sep < 1 || sep + 7 > lower.length) {
    throw const FormatException('Ayırıcı bulunamadı');
  }
  final hrp = lower.substring(0, sep);
  final dataPart = lower.substring(sep + 1);
  final data5 = <int>[];
  for (final c in dataPart.codeUnits) {
    final idx = _charset.indexOf(String.fromCharCode(c));
    if (idx < 0) throw FormatException('Geçersiz karakter: $c');
    data5.add(idx);
  }
  if (_polymod([..._hrpExpand(hrp), ...data5]) != 1) {
    throw const FormatException('Sağlama toplamı hatalı');
  }
  final payload = data5.sublist(0, data5.length - 6);
  return (hrp: hrp, data: convertBits(payload, 5, 8, pad: false));
}

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> hexToBytes(String hex) {
  if (hex.length.isOdd) throw const FormatException('Tek sayıda hex karakteri');
  final out = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    out.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return out;
}
