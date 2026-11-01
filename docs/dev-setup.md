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

## Sorun Giderme

| Belirti | Çözüm |
|---|---|
| `Unsupported class file major version` | `source scripts/env.sh` (JDK 21'e geç) |
| `sdkmanager: command not found` | `source scripts/env.sh` |
| `flutter doctor` Android SDK'yı görmüyor | `flutter config --android-sdk ~/Android/Sdk` |
| Relay başlamıyor | `.data/relay.log` oku; port 7777 dolu mu: `ss -lntp \| grep 7777` |
| Uygulama "Bağlı değil" diyor | Relay çalışıyor mu: `ss -lntp \| grep 7777`; emülatör/telefon için: `adb reverse tcp:7777 tcp:7777` |
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
