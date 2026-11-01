# Verso Cafe

Nostr protokolü üzerine kurulu, davetliye kapalı, P2P çalışan bir sosyal ağ uygulaması.
Android istemcisi Flutter ile yazılır; veri kullanıcı cihazında tutulur, relay yalnızca
posta kutusu görevi görür.

> **Ad:** `Verso Cafe` (kesinleşti, bkz. `docs/decisions.md` → ADR-011). Teknik
> kimlikler — `com.sosyal.app` paket adı, `sosyal.dpdns.org` alanı ve imza anahtarı —
> süreklilik için `sosyal` olarak bırakıldı.

## Durum

| Faz | Konu | Durum |
|---|---|---|
| 1 | Temel altyapı ve test ortamı | ✅ tamamlandı |
| 2 | Kimlik, yedekleme, davet | ✅ tamamlandı |
| 3 | Profil, gönderi, medya | ✅ tamamlandı (fotoğraf + kendi medya sunucusu dahil) |
| 4 | Akış, beğeni, yorum, engelleme | ✅ tamamlandı (engelleme + repost dahil) |
| 5 | Birebir mesajlaşma (NIP-17) | ✅ tamamlandı (gerçek NIP-44) |
| 6 | Push bildirim | ⏸️ ertelendi (yerine bkz. arka plan bağlantısı) |
| 7 | Üretim, dağıtım, sürüm | ✅ [v0.3.0 GitHub Release'te](https://github.com/versochar/verso-cafe/releases/tag/v0.3.0) (kendi hesap sunucusu + hikâyeler) |
| — | Arayüz modernizasyonu | ✅ tamamlandı (Instagram benzeri düzen dahil) |
| — | Bildirim merkezi (zil + rozet) | ✅ tamamlandı |
| — | Arka plan bağlantısı | ✅ tamamlandı (ön plan servisi + Android bildirimi) |
| — | QR ile arkadaş ekleme | ✅ tamamlandı (kamera + galeriden tarama) |
| — | Uygulama içi güncelleme | ✅ tamamlandı (version.json → indirme → sha256 → kurucu) |
| — | Kullanıcı adı + parola hesabı | ✅ tamamlandı (kendi hesap sunucusu; anahtar NIP-49 ile parolayla şifreli) |
| — | Host/mod yetkisi + duyurular | ✅ tamamlandı (rol kapıları sunucuda + istemcide) |
| — | Hikâyeler (24 saat) | ✅ tamamlandı (fotoğraf + yazı, NIP-40 süre sonu) |
| — | Şehirler arası erişim | ✅ tamamlandı (Cloudflare tüneli; adresler `network.json`'dan) |

## Teknoloji

- **İstemci:** Flutter (Dart), Android
- **Protokol:** Nostr — BIP-340 Schnorr (secp256k1) imzalı event log
- **Relay:** `nostr-rs-relay` (yerel test), `strfry` (üretim)
- **Medya:** Kendi sunulan Dart sunucusu (`apps/media-server`, NIP-98 auth)
- **Hesaplar:** Kendi sunulan Dart servisi (`apps/account-server`; yalnız
  kimlik/rol/duyuru — içerik yine relay'de, ADR-015). Parola PBKDF2 ile, Nostr
  anahtarı NIP-49 ile parolaya bağlı şifreli durur.
- **Push:** Gateway servisi → FCM
- **Dağıtım:** GitHub Releases (APK + `version.json`); ağ adresleri `network.json`

## Dokümanlar

- [`docs/plan.md`](docs/plan.md) — ana plan, kapsam, takvim, maliyet
- [`docs/phases.md`](docs/phases.md) — fazlar ve kabul kriterleri
- [`docs/architecture.md`](docs/architecture.md) — mimari, veri akışı, NIP eşlemesi
- [`docs/decisions.md`](docs/decisions.md) — alınan kararlar (ADR)
- [`docs/kurulum.md`](docs/kurulum.md) — arkadaşlar için kurulum (APK, hesap, arkadaş ekleme)
- [`docs/dev-setup.md`](docs/dev-setup.md) — yerel test ortamı
- [`docs/ui.md`](docs/ui.md) — arayüz tasarım sistemi ve ekranlar

## Hızlı Başlangıç

```bash
source scripts/env.sh        # Flutter + JDK 21 + Android SDK yolları

# 1. Yerel relay
./scripts/relay-start.sh

# 1b. Medya sunucusu (fotoğraf yüklemeleri)
./scripts/media-server-start.sh

# 1c. Hesap sunucusu (kayıt/giriş, roller, duyurular)
./scripts/account-server-start.sh

# 2. İstemci
cd apps/mobile
flutter run --dart-define=RELAY_URL=ws://192.168.1.109:7777 \
            --dart-define=MEDIA_URL=http://192.168.1.109:8080 \
            --dart-define=ACCOUNT_URL=http://192.168.1.109:8090
flutter build apk --debug   # aynı --dart-define bayraklarıyla
```

Telefona kurmak için (relay köprüsü dahil):

```bash
./scripts/install-apk.sh
```

Emülatörde (telefon yoksa):

```bash
./scripts/emulator-start.sh --headless
./scripts/e2e.sh             # relay + köprü + uçtan uca test
```

Faz 1 doğrulaması: `docs/phases.md`, ekran görüntüsü:
[`docs/img/phase1-emulator.png`](docs/img/phase1-emulator.png)

## Depo Yapısı

```
sosyal/
├── apps/mobile/           # Flutter istemcisi
├── apps/media-server/     # kendi sunulan medya sunucusu (NIP-98)
├── apps/account-server/   # kendi sunulan hesap servisi (kayıt/giriş/rol/duyuru)
├── services/push-gateway/ # FCM köprüsü (Faz 6)
├── infra/relay/           # relay yapılandırmaları (yerel + üretim)
├── scripts/               # yardımcı betikler
└── docs/                  # plan ve mimari
```
