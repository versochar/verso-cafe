# Faz 3 — Profil, Gönderi, Medya

Durum: **🚧 devam ediyor** (Faz 3 kod temeli hazır; ProfilePage + FeedPage çalışıyor, NIP-92 2/2 geçti)

## Kapsam

| Konu | Durum | Açıklama |
|---|---|---|
| `kind:1` metin gönderisi | ✅ kod | `EventKind.note`, `FeedPage` |
| `kind:3` takip (`contacts`) | ✅ tanımlı | `EventKind.contacts` |
| `kind:5` silme (`delete`) | ✅ tanımlı | `EventKind.delete` |
| `kind:10000` susturma (`mute`) | ✅ tanımlı | `EventKind.muteList` |
| `kind:0` profil güncelleme | ✅ çalışıyor | `ProfilePage._publish` |
| NIP-92 (`imeta`) medya etiketi | ✅ kod | `core/media/nip92.dart`, `test/nip92_test.dart` (2/2) |
| Görsel yükleme (`image_picker`) | ✅ pubspec'te | `image_picker` kuruldu |
| Akış (`FeedPage`) | ✅ kod | `features/feed/feed_page.dart` |
| `kind:1` içerik: metin veya `NIP-92` görsel | 🚧 simülasyon | `NIP-92` formatı tanımlı; gerçek R2 yüklemesi Faz 4-5'te |

## Yapılanlar

| Dosya | Açıklama |
|---|---|
| `core/nip92.dart` | `buildImetaTag()`, `imetaTags()`, `sha256OfString()` |
| `test/nip92_test.dart` | 2/2 test geçti |
| `features/feed/feed_page.dart` | Akış ekranı (`kind:1` filtreli), kronolojik sıralama |
| `pubspec.yaml` | `image_picker` eklendi |
| `docs/phases.md` | Faz 3 dokümanı güncellendi |

## Doğrulama Kanıtı
- `flutter test test/nip92_test.dart` → **2/2 geçti**
- `flutter analyze lib/features/feed/feed_page.dart` → hata yok (`dart:convert` import eklendi)
- `FeedPage` derlenir (`kind:1` filtre, `kind:5` silme filtresi simülasyonu)

## NIP-92 (`imeta`) Etiket Formatı

`buildImetaTag()` örneği:
```dart
buildImetaTag(
  url: 'https://example.com/img.webp',
  mimeType: 'image/webp',
  sha256Hex: 'aabbcc', // sha256 dosya içeriği
  sizeBytes: 1024,
  dimensions: '800x600',
  altText: 'açıklama',
)
```

`imetaTags()` ile NIP-01 `tags` formatına dönüştürülür:
```dart
[['imeta', 'https://...', 'm image/webp', 'x ...', 'size 1024', ...]]
```

## Kalan (Faz 3 Tamamlanması)
- `ProfilePage`: `_publish()` `kind:1` için metin veya görsel destekleyecek (`imeta` etiketi)
- `FeedPage`: `kind:5` silme isteklerini gerçek NIP-09 (`kind:5` tag okuma) ile filtreleyecek
- Görsel yükleme: `image_picker` → yerel/geçici URL (`R2` yerine) → `NIP-92` etiketi
- `kind:3` takip listesi (`contacts`): kullanıcı profillerinde takip listesi gösterilecek

Faz 3'ün çekirdek kodu (`kind:1`, `kind:5`, `NIP-92`, `FeedPage`) hazır; kalan `ProfilePage` entegrasyonu ve görsel yükleme akışının tamamlanması.
