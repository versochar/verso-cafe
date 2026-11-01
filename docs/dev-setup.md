# Yerel Test Ortamı

Tüm araçlar **kullanıcı alanına** kurulur; `sudo` gerekmez.

## Kurulu Bileşenler

| Bileşen | Konum | Sürüm |
|---|---|---|
| Flutter SDK | `~/flutter` | 3.47.9 (stable), Dart 3.13.7 |
| JDK | `~/.local/opt/jdk21` | Temurin 21.0.13+9 |
| Android SDK | `~/Android/Sdk` | cmdline-tools 23.0.0, platform 36, build-tools 36.0.0 |
| Yerel relay | `~/.cargo/bin/nostr-rs-relay` | 0.8.12 (cargo ile derlendi) |
| Relay verisi | `.data/relay/` | SQLite |

> Sistemdeki `java` 27 sürümü Gradle ile uyumsuz olduğu için proje **JDK 21** kullanır.
> `scripts/env.sh` bunu `JAVA_HOME` ve `GRADLE_OPTS` ile zorlar.

## Ortamı Yükleme

```bash
cd ~/sosyal
source scripts/env.sh
```

Her yeni terminalde bu komutu çalıştır (veya `~/.bashrc` sonuna ekle).

## Yerel Relay

```bash
./scripts/relay-start.sh     # ws://127.0.0.1:7777
./scripts/relay-stop.sh
tail -f .data/relay.log
```

Relay yapılandırması: `infra/relay/local.toml` (whitelist yok, SQLite kalıcı).
Üretim örneği: `infra/relay/prod.example.toml`.

## İstemci

```bash
cd apps/mobile
flutter pub get
flutter run                    # bağlı cihaz/emülatör
flutter build apk --debug      # build/app/outputs/flutter-apk/app-debug.apk
```

## Protokol Duman Testi (Android gerektirmez)

```bash
cd apps/mobile
dart run tool/nostr_smoke.dart
```

Bu betik: anahtar üretir → relay'e bağlanır → `kind:0` yayınlar → abone olup
geri okur. Faz 1'in kabul kriteri budur.

## Android SDK Paketleri

```bash
source scripts/env.sh
sdkmanager --list_installed
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter doctor --android-licenses
```

## Cihaz

```bash
adb devices
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Telefonda **USB hata ayıklama** açık olmalı. Kablosuz için:

```bash
adb pair <ip>:<port>
adb connect <ip>:5555
```

## Emülatör

Telefon yoksa PC'de Android 36 emülatörü kullanılabilir (KVM gerekir):

```bash
./scripts/emulator-start.sh --headless   # pencere yok
./scripts/emulator-start.sh              # pencereli
adb emu kill                             # kapat
```

AVD adı `sosyal_api36`, imaj `system-images;android-36;google_apis;x86_64`.
Betik `adb reverse tcp:7777 tcp:7777` köprüsünü de kurar.

## Uçtan Uca Test (emülatör/cihaz)

```bash
./scripts/relay-start.sh
adb reverse tcp:7777 tcp:7777
cd apps/mobile
flutter test integration_test/phase1_test.dart
```

Test: npub üretimi → relay bağlantısı → `kind:0` yayınlama → akışta listeleme.

## Genel Erişim (şehirler arası)

Yayınlanan APK'ya gömülen `RELAY_URL`/`MEDIA_URL`/`ACCOUNT_URL` neyse uygulama
yalnız oraya bağlanır. `ws://192.168.x.x` gibi yerel adresler aynı ağdaki telefonları
çalıştırır; başka şehirdeki bir arkadaş relay'e ulaşamaz (akış boş kalır).
Sunucuyu dışarı açmanın sudo/router gerektirmeyen yolu Cloudflare tünelidir:
tünel cihazdan **dışarı** bağlanır, port açmak gerekmez.

```bash
./scripts/serve.sh                 # relay + medya + hesap + tünel, adres değiştiyse duyurur
cat .data/public-urls.env          # RELAY_URL=wss://…  MEDIA_URL=…  ACCOUNT_URL=…
./scripts/tunnel-stop.sh           # (durdurma: tunnel-stop + account-server-stop
                                   #  + media-server-stop + relay-stop)
```

Bilgisayar her açıldığında tek komut yeterlidir: `./scripts/serve.sh`.

Adresleri doğrulamak için (genel internet üzerinden, telefondan bağımsız):

```bash
set -a; source .data/public-urls.env; set +a
cd apps/mobile
dart run tool/nostr_smoke.dart "$RELAY_URL"        # yayınla → abone ol → geri oku
dart run tool/relay_peek.dart 1 5                  # relay'deki son gönderileri bas
```

Baskıya hazır derleme hedefleri otomatik alır ve erişilebilirliklerini dener:

```bash
set -a; source .data/public-urls.env; set +a
./scripts/release-apk.sh
```

### Tünel adresi değişince (APK gerekmez)

Relay/medya/hesap adresi `network.json`'dan da okunur (ADR-014). Tünel yeniden
başladıysa yalnız şunu çalıştır — kurulu uygulamalar bir sonraki açılışta yeni
adrese geçer:

```bash
./scripts/tunnel-start.sh       # yeni adresleri üretir
./scripts/publish-network.sh    # network.json'u yazar, commit'ler, push'lar
```

Uygulama adresleri açılışta bir kez okur (3 sn sınır); GitHub'a ulaşılamazsa
son bilinen adres (cihazda saklanır) ya da APK'ya gömülü adres kullanılır.

> **Uyarı:** `tunnel-start.sh` ücretsiz *quick tunnel* kullanır — adresler
> rastgeledir ve tünel yeniden başladığında **değişir**. Adres değişimini
> `publish-network.sh` ile duyurursan APK yayınlamak gerekmez; yine de kalıcı
> yayın adresi için üç yol var:
>
> 1. **Cloudflare named tunnel** (önerilen): ücretsiz Cloudflare hesabı + alan
>    adı (Cloudflare DNS'e alınmış). Bir kez `cloudflared tunnel login` +
>    `tunnel create/route dns` ile `relay.versocafe.app` gibi **sabit** adres
>    elde edilir; quick tunnel ile aynı `cloudflared` süreci, yeniden başlayınca
>    adres değişmez.
> 2. **Router port yönlendirme + Caddy**: hattın genel IP'si CGNAT değilse
>    (bkz. `curl api.ipify.org`) 80/443 yönlendirilir, Caddy otomatik TLS alır,
>    `sosyal.dpdns.org` gibi ücretsiz bir alan adı A kaydı IP'yi takip eder
>    (DDNS). Dezavantaj: ev hattı açık port taşır, modem/router araya girer.
> 3. **Ücretsiz/ucuz VPS** (Oracle Free Tier vb.): relay + medya orada koşar,
>    ev bilgisayarından bağımsız olur. En dayanıklısı ama kurulum sunucu
>    bakımı ister.

## İmzalı Release (Yayın)

Tek komut: `./scripts/release-apk.sh` → `verso-cafe-release-arm64.apk` (~27 MB) ve
`verso-cafe-release-armv7.apk` (~23 MB) üretir, imzayı doğrular.

- **Keystore:** `~/.android/sosyal-release.keystore` (alias `sosyal`, RSA-2048,
  30 yıl). Parola: `~/.android/sosyal-release.password`. **İkisinin de yedeğini
  güvenli bir yerde tut** — gelecekteki tüm güncellemeler bu anahtarla imzalanmak
  zorunda; anahtar kaybolursa mevcut kurulumların üzerine kurulamaz.
- **Gradle bağlantısı:** `apps/mobile/android/key.properties` (dosya yoksa
  derleme sessizce debug anahtara düşer — yayın için var olmalı).
- Sürüm numarası `pubspec.yaml` → `version:` (ör. `0.1.1+2`); her yayında artır
  ve `version.json` + `AppConfig.version` alanlarını senkron tut.

### GitHub'a yayınlama

Depo: `https://github.com/versochar/verso-cafe` (public).

```bash
./scripts/release-apk.sh          # APK'ları üret
# pubspec.yaml sürümünü + version.json'u güncelle, commit'le, push'la
./scripts/publish-release.sh v0.1.1   # release + APK asset'leri + version.json
```

Arkadaşlar `Releases` sayfasından ya da şu sabit adresten indirir:
`…/releases/latest/download/verso-cafe-release-arm64.apk`.
Uygulama içi güncelleme kontrolü `releases/latest/download/version.json`'u okur
(ADR-012 — API rate limit'i yok).

## Hesap Sunucusu (kayıt/giriş, roller, duyurular)

Hesaplar, roller ve duyurular ev bilgisayarında çalışan küçük bir Dart
servisinde tutulur (ADR-015); içerik yine relay + medya sunucusunda.
Firebase/Google hesabı, `google-services.json` ve emülatör gerekmez.

```bash
./scripts/account-server-start.sh    # http://127.0.0.1:8090
./scripts/account-server-stop.sh
```

- **Veri:** `${ACCOUNT_DB:-$HOME/sosyal-accounts/accounts.json}`. Dosyayı
  kopyalamak yedek almak için yeterlidir (parolalar PBKDF2, anahtarlar NIP-49
  ile şifreli).
- **Parola:** en az 6 karakter; sunucuda PBKDF2-HMAC-SHA256 (60.000 tur,
  kullanıcıya özel tuz) özeti durur, düz parola asla yazılmaz.
- **Oturum:** rastgele bearer jeton, sunucuda yalnız sha256 özeti; 30 gün.
- **Tohum host:** ilk kayıt `hosthesap` adıyla yapılırsa o hesap host olur.
  Host, Profil → **Yetki yönetimi**'nden mod atar ve hostluğu devreder.
  Duyuruyu yalnız host/mod yazar, yalnız host siler.
- **Uçlar:** `POST /v1/register`, `/v1/login`, `/v1/logout`, `/v1/password`,
  `/v1/host/transfer`, `/v1/announcements`; `GET /v1/me`, `/v1/users`,
  `/v1/announcements`, `/healthz`; `PATCH /v1/users/<id>/role`,
  `DELETE /v1/announcements/<id>`. Parola denemesi 10 dakikada 8'i aşarsa 429.

İstemciyi yerel sunucuya bağlamak için (emülatörde `10.0.2.2`):

```bash
cd apps/mobile
flutter run --dart-define=ACCOUNT_URL=http://10.0.2.2:8090
```

`network.json` okuması varsayılan olarak açıktır (ADR-014); yerel adresleri
korumak için `--dart-define=NETWORK_URL=` ile kapatılır.

Uçtan uca hızlı deneme (uygulama olmadan):

```bash
PK=$(printf 'a%.0s' {1..64})
curl -s -X POST http://127.0.0.1:8090/v1/register \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"deneme\",\"password\":\"123456\",\"pubkey\":\"$PK\",\
       \"npub\":\"npub1...\",\"ncryptsec\":\"ncryptsec1...\"}"
```

`scripts/serve.sh` hesap sunucusunu da başlatır; `tunnel-start.sh` üçüncü
tüneli açar ve `network.json`'a `account` alanını yazar.

## Sorun Giderme

| Belirti | Çözüm |
|---|---|
| `Unsupported class file major version` | `source scripts/env.sh` (JDK 21'e geç) |
| `sdkmanager: command not found` | `source scripts/env.sh` |
| `flutter doctor` Android SDK'yı görmüyor | `flutter config --android-sdk ~/Android/Sdk` |
| Relay başlamıyor | `.data/relay.log` oku; port 7777 dolu mu: `ss -lntp \| grep 7777` |
| Uygulama "Bağlı değil" diyor | Relay çalışıyor mu: `ss -lntp \| grep 7777`; emülatör/telefon için: `adb reverse tcp:7777 tcp:7777` |
| Girişte "Hesap sunucusuna ulaşılamadı" | Hesap sunucusu açık mı: `curl -s http://127.0.0.1:8090/healthz`; emülatör/telefon için `ACCOUNT_URL` doğru mu (`10.0.2.2`, tünel) |
| `time 0.3.25` derleme hatası | `cargo install nostr-rs-relay` (`--locked` kullanma) |
| `Multiple adb binaries found` uyarısı | Zararsız; `platform-tools` PATH'te önce gelir |
| Gradle indirmesi yavaş | `~/.gradle` ilk build'de ~1 GB indirir, normal |
| Disk dolu | `df -h /home`; `~/.gradle/caches` temizlenebilir |

## Telefondan Yerel Relay'e Erişim

Relay `127.0.0.1`'i dinlediği için telefon doğrudan bağlanamaz. USB ile bağlıyken:

```bash
adb reverse tcp:7777 tcp:7777
```

Bu komut telefonun `127.0.0.1:7777` adresini PC'deki relay'e yönlendirir; uygulama
varsayılan `ws://127.0.0.1:7777` adresini kullanmaya devam eder. `adb reverse`
her USB bağlantısında yeniden çalıştırılmalıdır.

## Sıfırdan Kurulum

`scripts/setup-local.sh` tüm adımları tekrar eder (idempotent).
