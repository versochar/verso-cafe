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

Yayınlanan APK'ya gömülen `RELAY_URL`/`MEDIA_URL` neyse uygulama yalnız oraya
bağlanır. `ws://192.168.x.x` gibi yerel adresler aynı ağdaki telefonları
çalıştırır; başka şehirdeki bir arkadaş relay'e ulaşamaz (akış boş kalır).
Sunucuyu dışarı açmanın sudo/router gerektirmeyen yolu Cloudflare tünelidir:
tünel cihazdan **dışarı** bağlanır, port açmak gerekmez.

```bash
./scripts/relay-start.sh && ./scripts/media-server-start.sh
./scripts/tunnel-start.sh          # iki tünel kurar, adresleri yazar
cat .data/public-urls.env          # RELAY_URL=wss://…  MEDIA_URL=https://…
./scripts/tunnel-stop.sh
```

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

Relay/medya adresi `network.json`'dan da okunur (ADR-014). Tünel yeniden
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

## Firebase Hesapları (yalnız geliştirme: Emulator Suite)

Kayıt/giriş, roller ve duyurular Firebase'de; içerik yine relay'de (ADR-013).
Geliştirme için Google hesabı gerekmez — **Firebase Emulator Suite** kullanılır
(`firebase-tools` `~/.npm-global` içinde kurulu, `scripts/env.sh` PATH'ine ekler).

```bash
source scripts/env.sh
cd infra/firebase
firebase emulators:start --project demo-verso-cafe   # auth :9099, firestore :8188
```

Emülatör veri tutmaz (bellek içi); kapatınca hesaplar/duyurular silinir.
Kalıcı snapshot için: `firebase emulators:export .data/firebase` / `--import`.

İstemciyi emülatöre bağlamak için:

```bash
cd apps/mobile
flutter run --dart-define=FIREBASE_EMULATOR=10.0.2.2
```

- `FIREBASE_EMULATOR` doluysa uygulama Auth'u `:9099`, Firestore'u `:8188`
  adresine yönlendirir; boşsa gerçek projeye bağlanır.
- Emülatörde **`10.0.2.2` kullan** (cihazın PC'ye açılan kapısı). `127.0.0.1`
  işe yaramaz: `cloud_firestore` Android tarafı döngü adresini logda görünen
  biçimde zorla `10.0.2.2`'ye çevirir, `adb reverse` de bu yüzden işe yaramaz.
- Emülatör düz HTTP konuşur; `network_security_config.xml` cleartext'i **yalnız**
  `127.0.0.1`/`localhost`/`10.0.2.2` için açar (üretim trafiği HTTPS/WS kalır).
- Bağlantı koparsa ("client is offline", `ENETUNREACH`): emülatörde hem mobil hem
  Wi-Fi ağı açıksa gRPC kanalı bazen IPv6'sız ağa bağlanıp yol bulamıyor. Tek
  ağa indir: `adb -e shell svc wifi disable`.

Kuralların gerçekten uygulandığını (istemciden bağımsız) doğrulamak için:

```bash
python3 infra/firebase/rules_check.py [host_adı host_parolası [üye_adı üye_parolası]]
```

Mod duyuru yazar, sıradan üye yazamaz, kimse kendi rolünü yükseltemez,
token'sız okuma yoktur; betik denemeleri temizleyip rolleri eski hâline döndürür.

### Gerçek proje (yayın için bir kerelik)

1. `firebase login` (tarayıcı) → `firebase projects:create verso-cafe`
2. Firebase Console → Authentication → **Email/Password**'ı etkinleştir
3. Cloud Firestore veritabanı oluştur, `infra/firebase/firestore.rules`'ü yayınla:
   `firebase deploy --only firestore:rules --project verso-cafe`
4. Android uygulaması kaydet (**paket adı `com.sosyal.app`**), indirilen
   `google-services.json`'u `apps/mobile/android/app/` içine koy (depodaki
   dosya `demo-verso-cafe` yer tutucusudur — gerçek anahtar olmadan hesaplar
   çalışmaz, uygulama yerel anahtarla devam eder)
5. `FIREBASE_EMULATOR` define'ı **olmadan** derle

Parola alt sınırı Firebase'de **6 karakterdir** (emülatörde de, gerçek
projede de; firebase-tools ayarla düşürülemez). `12345` gibi 5 haneli parolalar
`WEAK_PASSWORD` ile reddedilir.

Tohum host: host olarak doğabilen tek hesap kuralda yazılıdır —
`hosthesap@hesap.verso.app`. Kendi hesabını host yapma yolu: önce `hosthesap`
kayıt olur, sonra Ayarlar → Yetki yönetimi → hesabın → "Hostluğu devret"
denir; hostluk devredildikten sonra `hosthesap` normal üyeye düşer ve yetkisi
kalmaz (geri alınamaz, yeni host isterse mod verebilir).

## Sorun Giderme

| Belirti | Çözüm |
|---|---|
| `Unsupported class file major version` | `source scripts/env.sh` (JDK 21'e geç) |
| `sdkmanager: command not found` | `source scripts/env.sh` |
| `flutter doctor` Android SDK'yı görmüyor | `flutter config --android-sdk ~/Android/Sdk` |
| Relay başlamıyor | `.data/relay.log` oku; port 7777 dolu mu: `ss -lntp \| grep 7777` |
| Uygulama "Bağlı değil" diyor | Relay çalışıyor mu: `ss -lntp \| grep 7777`; emülatör/telefon için: `adb reverse tcp:7777 tcp:7777` |
| Girişte "client is offline" / `ENETUNREACH` | Firebase emülatörü açık mı (`:9099`, `:8188`); `FIREBASE_EMULATOR=10.0.2.2` kullan; emülatörde `adb -e shell svc wifi disable` ile tek ağa indir |
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
